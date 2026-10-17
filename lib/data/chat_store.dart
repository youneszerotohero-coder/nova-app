import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;

import '../core/api/api_exception.dart';
import '../core/api/nova_api.dart';
import '../core/realtime/reverb_client.dart';
import 'chat_models.dart';
import 'json.dart';

export 'chat_models.dart';

/// D-143 group chats (docs/D-143 §3.1, §3.5): the signed-in user's rooms,
/// each room's messages (pages of 30, newest last), optimistic sends,
/// reads, and the Reverb events of every room.
///
/// Screens listen to this store directly (it is not forwarded to
/// [AppState]'s listeners: a chat event rebuilds only the chat UI).
class ChatStore extends ChangeNotifier {
  ChatStore(this._api);

  /// Offline rooms and messages for tests and previews.
  ChatStore.seeded({
    List<ChatRoom> rooms = const <ChatRoom>[],
    Map<int, List<ChatMessage>> messages = const <int, List<ChatMessage>>{},
    Map<int, List<ChatPerson>> members = const <int, List<ChatPerson>>{},
    Map<int, List<ChatMessage>> pdfs = const <int, List<ChatMessage>>{},
    this._me = 0,
  })  : _api = null,
        _seededMembers = members,
        _seededPdfs = pdfs {
    _rooms = _sorted(rooms);
    _roomsLoaded = true;
    messages.forEach((int id, List<ChatMessage> list) {
      _threads[id] = _Thread()
        ..messages = List<ChatMessage>.of(list)
        ..loaded = true
        ..hasMore = false;
    });
  }

  final NovaApi? _api;
  Map<int, List<ChatPerson>> _seededMembers = const <int, List<ChatPerson>>{};
  Map<int, List<ChatMessage>> _seededPdfs = const <int, List<ChatMessage>>{};

  static const int pageSize = 30;
  static const Duration readDebounce = Duration(milliseconds: 700);
  static const Duration pollInterval = Duration(seconds: 10);
  static const int maxTextLength = 2000;
  static const int maxCaptionLength = 500;
  static const int maxPdfBytes = 20 * 1024 * 1024;
  static const Duration maxVoice = Duration(minutes: 5);

  int _me = 0;
  List<ChatRoom> _rooms = const <ChatRoom>[];
  bool _roomsLoaded = false;
  bool _loadingRooms = false;
  bool _reloadRooms = false;
  ApiException? _roomsError;
  final Map<int, _Thread> _threads = <int, _Thread>{};

  /// Bumped by [clear]: an answer to a request of the previous user is
  /// dropped.
  int _session = 0;
  final Map<int, int> _readPosted = <int, int>{};
  final Map<int, Timer> _readTimers = <int, Timer>{};
  final Map<int, ChatFileLink> _links = <int, ChatFileLink>{};
  final Map<String, CancelToken> _uploads = <String, CancelToken>{};
  final StreamController<ChatArrival> _arrivals = StreamController<ChatArrival>.broadcast();
  final StreamController<int> _removed = StreamController<int>.broadcast();

  int? _activeRoom;
  bool _activeAtBottom = false;

  ReverbClient? _realtime;
  final Map<String, VoidCallback> _subscriptions = <String, VoidCallback>{};
  bool _wasConnected = false;
  bool _everConnected = false;
  Timer? _poll;

  /// The signed-in user's id (`sender.id` of their own messages).
  int get me => _me;

  /// Public room first, then the most recent conversation.
  List<ChatRoom> get rooms => _rooms;
  bool get roomsLoaded => _roomsLoaded;
  bool get loadingRooms => _loadingRooms;
  ApiException? get roomsError => _roomsError;

  /// Unread messages of every room (the top bar badge).
  int get unreadTotal => _rooms.fold(0, (int sum, ChatRoom room) => sum + room.unreadCount);

  /// Messages from others delivered in realtime, never for a muted room.
  Stream<ChatArrival> get arrivals => _arrivals.stream;

  /// Rooms the user left or that were deleted: their screens close.
  Stream<int> get removedRooms => _removed.stream;

  ChatRoom? room(int id) {
    for (final ChatRoom room in _rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  List<ChatMessage> messagesOf(int roomId) => _threads[roomId]?.messages ?? const <ChatMessage>[];
  bool threadLoaded(int roomId) => _threads[roomId]?.loaded ?? false;
  bool hasOlder(int roomId) => _threads[roomId]?.hasMore ?? false;
  bool loadingOlder(int roomId) => _threads[roomId]?.loadingOlder ?? false;
  ApiException? threadError(int roomId) => _threads[roomId]?.error;
  int? get activeRoom => _activeRoom;

  // ── Session ──────────────────────────────────────────────────────────

  /// After sign-in: the rooms, their channels, and the polling fallback
  /// used while Reverb is unavailable.
  void start({required int me, ReverbClient? realtime}) {
    _me = me;
    _attach(realtime);
    loadRooms();
    if (_api != null) {
      _poll?.cancel();
      _poll = Timer.periodic(pollInterval, (_) => _pollTick());
    }
  }

  /// Sign-out: nothing of this user survives.
  void clear() {
    _session++;
    _poll?.cancel();
    _poll = null;
    _detach();
    for (final Timer timer in _readTimers.values) {
      timer.cancel();
    }
    _readTimers.clear();
    for (final CancelToken token in _uploads.values) {
      token.cancel();
    }
    _uploads.clear();
    _rooms = const <ChatRoom>[];
    _roomsLoaded = false;
    _loadingRooms = false;
    _reloadRooms = false;
    _roomsError = null;
    _threads.clear();
    _readPosted.clear();
    _links.clear();
    _activeRoom = null;
    _activeAtBottom = false;
    _me = 0;
    notifyListeners();
  }

  /// The app came back to the foreground: what happened meanwhile.
  void onResumed() {
    if (_api == null || _me == 0) return;
    loadRooms();
    final int? active = _activeRoom;
    if (active != null) catchUp(active);
  }

  // ── Rooms ────────────────────────────────────────────────────────────

  Future<void> loadRooms() async {
    final NovaApi? api = _api;
    if (api == null) return;
    if (_loadingRooms) {
      _reloadRooms = true;
      return;
    }
    final int session = _session;
    _loadingRooms = true;
    if (!_roomsLoaded) notifyListeners();
    try {
      final Json body = await api.get('/chats');
      if (session != _session) return;
      _setRooms(body.list('data').map(ChatRoom.fromJson).toList());
      _roomsError = null;
    } on ApiException catch (error) {
      if (session != _session) return;
      _roomsError = error;
    } finally {
      if (session == _session) {
        _loadingRooms = false;
        notifyListeners();
        if (_reloadRooms) {
          _reloadRooms = false;
          loadRooms();
        }
      }
    }
  }

  /// One room again (`GET /chats/{id}`), e.g. opened from a push before
  /// the list loaded, or after its last message was deleted.
  Future<ChatRoom?> refreshRoom(int roomId) async {
    final NovaApi? api = _api;
    if (api == null) return room(roomId);
    final int session = _session;
    try {
      final Json body = await api.get('/chats/$roomId');
      if (session != _session) return null;
      final ChatRoom fresh = ChatRoom.fromJson(body.obj('data') ?? <String, dynamic>{});
      _replaceRoom(fresh, add: true);
      _syncSubscriptions();
      notifyListeners();
      return fresh;
    } on ApiException catch (error) {
      if (session == _session && (error.status == 403 || error.status == 404)) _dropRoom(roomId);
      rethrow;
    }
  }

  Future<void> setMuted(int roomId, bool muted) async {
    final ChatRoom? before = room(roomId);
    if (before == null) return;
    _replaceRoom(before.copyWith(muted: muted));
    notifyListeners();
    final NovaApi? api = _api;
    if (api == null) return;
    try {
      final Json body = await api.put('/chats/$roomId/mute', <String, bool>{'muted': muted});
      final Json? data = body.obj('data');
      if (data != null) _replaceRoom(ChatRoom.fromJson(data));
      notifyListeners();
    } on ApiException {
      _replaceRoom((room(roomId) ?? before).copyWith(muted: before.muted));
      notifyListeners();
      rethrow;
    }
  }

  void _setRooms(List<ChatRoom> fresh) {
    final Set<int> ids = <int>{for (final ChatRoom room in fresh) room.id};
    final List<int> gone = <int>[
      for (final ChatRoom room in _rooms)
        if (!ids.contains(room.id)) room.id,
    ];
    _rooms = _sorted(fresh);
    _roomsLoaded = true;
    for (final ChatRoom room in fresh) {
      _readPosted[room.id] = math.max(_readPosted[room.id] ?? 0, room.lastReadMessageId);
    }
    for (final int id in gone) {
      _forget(id);
      _removed.add(id);
    }
    _syncSubscriptions();
  }

  void _replaceRoom(ChatRoom fresh, {bool add = false}) {
    final bool found = _rooms.any((ChatRoom room) => room.id == fresh.id);
    if (!found && !add) return;
    final List<ChatRoom> next = <ChatRoom>[
      for (final ChatRoom room in _rooms) room.id == fresh.id ? fresh : room,
      if (!found) fresh,
    ];
    _rooms = _sorted(next);
  }

  void _dropRoom(int roomId) {
    if (room(roomId) == null && !_threads.containsKey(roomId)) return;
    _rooms = <ChatRoom>[
      for (final ChatRoom room in _rooms)
        if (room.id != roomId) room,
    ];
    _forget(roomId);
    _syncSubscriptions();
    _removed.add(roomId);
    notifyListeners();
  }

  void _forget(int roomId) {
    _threads.remove(roomId);
    _readTimers.remove(roomId)?.cancel();
    if (_activeRoom == roomId) _activeRoom = null;
  }

  static List<ChatRoom> _sorted(List<ChatRoom> rooms) {
    final List<ChatRoom> sorted = List<ChatRoom>.of(rooms);
    int rank(ChatRoom room) => room.isPublic ? 0 : 1;
    final DateTime never = DateTime.fromMillisecondsSinceEpoch(0);
    // `List.sort` is not stable: the index breaks ties, so rooms without
    // a message keep the server's order.
    final Map<int, int> order = <int, int>{for (int i = 0; i < rooms.length; i++) rooms[i].id: i};
    sorted.sort((ChatRoom a, ChatRoom b) {
      final int byKind = rank(a).compareTo(rank(b));
      if (byKind != 0) return byKind;
      final int byDate = (b.lastMessageAt ?? never).compareTo(a.lastMessageAt ?? never);
      if (byDate != 0) return byDate;
      return order[a.id]!.compareTo(order[b.id]!);
    });
    return sorted;
  }

  // ── Messages ─────────────────────────────────────────────────────────

  _Thread _thread(int roomId) => _threads.putIfAbsent(roomId, _Thread.new);

  /// The room screen opened: the latest page, or what arrived since.
  Future<void> openThread(int roomId) async {
    final _Thread? thread = _threads[roomId];
    if (thread != null && thread.loaded) return catchUp(roomId);
    return loadLatest(roomId);
  }

  /// The newest page (30 messages).
  Future<void> loadLatest(int roomId) async {
    final NovaApi? api = _api;
    if (api == null) return;
    final _Thread thread = _thread(roomId);
    final int session = _session;
    final int generation = ++thread.generation;
    try {
      final Json body = await api.get('/chats/$roomId/messages', query: <String, Object?>{'limit': pageSize});
      if (session != _session || generation != thread.generation || _threads[roomId] != thread) return;
      _merge(thread, _parse(body));
      thread.hasMore = body.obj('meta')?.flag('has_more') ?? false;
      thread.loaded = true;
      thread.error = null;
    } on ApiException catch (error) {
      if (session != _session || _threads[roomId] != thread) return;
      if (!thread.loaded) thread.error = error;
      if (error.code == 'CHAT_FORBIDDEN' || error.status == 404) _dropRoom(roomId);
    }
    notifyListeners();
  }

  /// The page before the oldest message shown, when scrolling up.
  Future<void> loadOlder(int roomId) async {
    final NovaApi? api = _api;
    final _Thread? thread = _threads[roomId];
    if (api == null || thread == null || !thread.loaded || !thread.hasMore || thread.loadingOlder) return;
    final int oldest = thread.oldestId;
    if (oldest == 0) return;
    final int session = _session;
    thread.loadingOlder = true;
    notifyListeners();
    try {
      final Json body = await api.get('/chats/$roomId/messages', query: <String, Object?>{
        'before_id': oldest,
        'limit': pageSize,
      });
      if (session != _session || _threads[roomId] != thread) return;
      _merge(thread, _parse(body));
      thread.hasMore = body.obj('meta')?.flag('has_more') ?? false;
    } on ApiException {
      // Kept as is; the next scroll retries.
    } finally {
      thread.loadingOlder = false;
      if (session == _session) notifyListeners();
    }
  }

  /// What arrived after the newest message shown (reconnection, resume,
  /// polling). A long gap starts the thread again from the latest page.
  Future<void> catchUp(int roomId) async {
    final NovaApi? api = _api;
    final _Thread? thread = _threads[roomId];
    if (api == null) return;
    if (thread == null || !thread.loaded || thread.newestId == 0) return loadLatest(roomId);
    final int session = _session;
    try {
      for (int page = 0; page < 4; page++) {
        final Json body = await api.get('/chats/$roomId/messages', query: <String, Object?>{
          'after_id': thread.newestId,
          'limit': 50,
        });
        if (session != _session || _threads[roomId] != thread) return;
        final List<ChatMessage> fresh = _parse(body);
        for (final ChatMessage message in fresh) {
          _noteRoomMessage(roomId, message, announce: false);
        }
        _merge(thread, fresh);
        notifyListeners();
        if (!(body.obj('meta')?.flag('has_more') ?? false)) {
          if (_activeRoom == roomId && _activeAtBottom) markRead(roomId);
          return;
        }
      }
      // Too far behind: the latest page, older ones on scroll.
      thread
        ..messages = <ChatMessage>[...thread.messages.where((ChatMessage m) => !m.isConfirmed)]
        ..loaded = false;
      await loadLatest(roomId);
    } on ApiException catch (error) {
      if (error.code == 'CHAT_FORBIDDEN') _dropRoom(roomId);
    }
  }

  List<ChatMessage> _parse(Json body) => body.list('data').map(ChatMessage.fromJson).toList();

  /// Confirmed messages by id (ascending), then the unsent ones in send
  /// order; a server copy replaces the pending message of its
  /// `client_uuid`, and keeps a known "seen by" count the broadcast lacks.
  void _merge(_Thread thread, List<ChatMessage> incoming) {
    if (incoming.isEmpty) return;
    final Map<int, ChatMessage> byId = <int, ChatMessage>{
      for (final ChatMessage m in thread.messages)
        if (m.isConfirmed) m.id: m,
    };
    final List<ChatMessage> unsent = <ChatMessage>[
      for (final ChatMessage m in thread.messages)
        if (!m.isConfirmed) m,
    ];
    for (final ChatMessage message in incoming) {
      if (message.id <= 0) continue;
      final ChatMessage? known = byId[message.id];
      byId[message.id] = message.seenCount == null && known?.seenCount != null
          ? message.copyWith(seenCount: known!.seenCount)
          : message;
      final String? uuid = message.clientUuid;
      if (uuid != null) unsent.removeWhere((ChatMessage m) => m.clientUuid == uuid);
    }
    final List<ChatMessage> confirmed = byId.values.toList()..sort((ChatMessage a, ChatMessage b) => a.id.compareTo(b.id));
    thread.messages = <ChatMessage>[...confirmed, ...unsent];
  }

  // ── Sending ──────────────────────────────────────────────────────────

  /// Sends a text; resolves to null once the server has it, or to the
  /// failure (the message stays, marked failed, for a retry).
  Future<ApiException?> sendText(int roomId, String text) {
    final String body = text.trim();
    return _send(ChatMessage(
      id: 0,
      roomId: roomId,
      kind: ChatMessageKind.text,
      body: body.length > maxTextLength ? body.substring(0, maxTextLength) : body,
      sender: _meAs(roomId),
      clientUuid: newClientUuid(),
      createdAt: DateTime.now(),
      state: ChatSendState.pending,
    ));
  }

  /// Sends a recorded voice note (AAC `.m4a` at [path]).
  Future<ApiException?> sendVoice(int roomId, {required String path, required int durationMs, List<int> waveform = const <int>[]}) {
    return _send(ChatMessage(
      id: 0,
      roomId: roomId,
      kind: ChatMessageKind.voice,
      sender: _meAs(roomId),
      attachment: ChatAttachment(
        name: 'voice.m4a',
        size: _sizeOf(path),
        mime: 'audio/mp4',
        durationMs: durationMs,
        waveform: waveform,
      ),
      clientUuid: newClientUuid(),
      createdAt: DateTime.now(),
      state: ChatSendState.pending,
      progress: 0,
      localPath: path,
    ));
  }

  /// Sends a picked PDF with an optional caption.
  Future<ApiException?> sendPdf(int roomId, {required String path, required String name, String caption = ''}) {
    final String text = caption.trim();
    return _send(ChatMessage(
      id: 0,
      roomId: roomId,
      kind: ChatMessageKind.pdf,
      body: text.isEmpty ? null : (text.length > maxCaptionLength ? text.substring(0, maxCaptionLength) : text),
      sender: _meAs(roomId),
      attachment: ChatAttachment(name: name, size: _sizeOf(path), mime: 'application/pdf'),
      clientUuid: newClientUuid(),
      createdAt: DateTime.now(),
      state: ChatSendState.pending,
      progress: 0,
      localPath: path,
    ));
  }

  /// Sends a failed message again (same `client_uuid`: never twice).
  Future<ApiException?> retry(int roomId, String clientUuid) => _deliver(roomId, clientUuid);

  /// Drops a failed message from the screen.
  void discard(int roomId, String clientUuid) {
    final _Thread? thread = _threads[roomId];
    if (thread == null) return;
    thread.messages = <ChatMessage>[
      for (final ChatMessage m in thread.messages)
        if (m.clientUuid != clientUuid || m.isConfirmed) m,
    ];
    notifyListeners();
  }

  /// Stops an upload in progress: nothing is sent (BR-C5).
  void cancelUpload(int roomId, String clientUuid) {
    final CancelToken? token = _uploads.remove(clientUuid);
    if (token != null) token.cancel();
    discard(roomId, clientUuid);
  }

  Future<ApiException?> _send(ChatMessage pending) {
    _thread(pending.roomId).messages.add(pending);
    notifyListeners();
    return _deliver(pending.roomId, pending.clientUuid!);
  }

  Future<ApiException?> _deliver(int roomId, String uuid) async {
    final _Thread? thread = _threads[roomId];
    final ChatMessage? message = thread?.messages.where((ChatMessage m) => m.clientUuid == uuid && !m.isConfirmed).firstOrNull;
    if (thread == null || message == null) return null;
    _update(thread, uuid, (ChatMessage m) => m.copyWith(
          state: ChatSendState.pending,
          progress: m.kind == ChatMessageKind.text ? null : 0,
        ));
    notifyListeners();
    final NovaApi? api = _api;
    if (api == null) {
      // Offline previews: delivered at once.
      _update(thread, uuid, (ChatMessage m) => m.copyWith(state: ChatSendState.sent));
      notifyListeners();
      return null;
    }
    final int session = _session;
    try {
      final Json body;
      if (message.kind == ChatMessageKind.text) {
        body = await api.post('/chats/$roomId/messages', <String, Object?>{
          'kind': 'text',
          'body': message.body,
          'client_uuid': uuid,
        });
      } else {
        final CancelToken token = CancelToken();
        _uploads[uuid] = token;
        double shown = 0;
        final bool voice = message.kind == ChatMessageKind.voice;
        body = await api.postMultipart(
          '/chats/$roomId/messages',
          fields: <String, Object?>{
            'kind': voice ? 'voice' : 'pdf',
            'client_uuid': uuid,
            if (voice) 'duration_ms': message.attachment?.durationMs,
            if (!voice && (message.body?.isNotEmpty ?? false)) 'body': message.body,
          },
          fileField: 'file',
          filePath: message.localPath!,
          fileName: voice ? 'voice.m4a' : message.attachment?.name,
          contentType: voice ? 'audio/mp4' : 'application/pdf',
          cancelToken: token,
          onProgress: (double progress) {
            // A redraw per 5 % is plenty.
            if (session != _session || progress - shown < 0.05 && progress < 1) return;
            shown = progress;
            _update(thread, uuid, (ChatMessage m) => m.copyWith(state: ChatSendState.pending, progress: progress));
            notifyListeners();
          },
        );
        _uploads.remove(uuid);
      }
      if (session != _session) return null;
      final ChatMessage sent = ChatMessage.fromJson(body.obj('data') ?? <String, dynamic>{});
      if (sent.id <= 0) throw const ApiException(status: 500, code: 'HTTP_500', message: 'Unexpected answer');
      final bool known = thread.messages.any((ChatMessage m) => m.id == sent.id);
      // The server copy takes the pending one's place, whatever it echoes.
      thread.messages = <ChatMessage>[
        for (final ChatMessage m in thread.messages)
          if (m.isConfirmed || m.clientUuid != uuid) m,
      ];
      _merge(thread, <ChatMessage>[sent]);
      if (!known) _noteRoomMessage(roomId, sent, announce: false);
      _deleteLocal(message);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      _uploads.remove(uuid);
      if (session != _session) return error;
      if (error.code == NovaApi.cancelled) {
        discard(roomId, uuid);
        return error;
      }
      _update(thread, uuid, (ChatMessage m) => m.copyWith(state: ChatSendState.failed, error: error.code));
      notifyListeners();
      // The rights changed (writing closed, kind refused): the room again.
      if (error.code == 'CHAT_SEND_CLOSED' || error.code == 'CHAT_KIND_FORBIDDEN') {
        refreshRoom(roomId).catchError((Object _) => null);
      }
      return error;
    }
  }

  void _update(_Thread thread, String uuid, ChatMessage Function(ChatMessage) change) {
    thread.messages = <ChatMessage>[
      for (final ChatMessage m in thread.messages)
        if (m.clientUuid == uuid && !m.isConfirmed) change(m) else m,
    ];
  }

  ChatSender _meAs(int roomId) => ChatSender(
        id: _me,
        role: room(roomId)?.canModerate ?? false ? ChatRole.teacher : ChatRole.student,
      );

  static int _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  void _deleteLocal(ChatMessage message) {
    // Only the recording is ours to delete; a picked PDF is the user's.
    final String? path = message.localPath;
    if (message.kind != ChatMessageKind.voice || path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {
      // Already gone.
    }
  }

  /// A random RFC 4122 v4 UUID: the server answers a repeated one with the
  /// same message, so a retry never posts twice.
  static String newClientUuid() {
    final math.Random random = math.Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final String hex = bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // ── Deleting, files, lists ───────────────────────────────────────────

  /// Deletes a message for everyone (BR-C5).
  Future<void> deleteMessage(int roomId, int messageId) async {
    await _api?.delete('/chats/$roomId/messages/$messageId');
    _removeMessage(roomId, messageId);
  }

  void _removeMessage(int roomId, int messageId) {
    final _Thread? thread = _threads[roomId];
    if (thread != null) {
      thread.messages = <ChatMessage>[
        for (final ChatMessage m in thread.messages)
          if (m.id != messageId) m,
      ];
    }
    _links.remove(messageId);
    final ChatRoom? current = room(roomId);
    if (current != null && current.lastMessage?.id == messageId) {
      // The list previews the message before it.
      refreshRoom(roomId).catchError((Object _) => null);
    }
    notifyListeners();
  }

  /// The signed URL of a voice note or PDF, reused until shortly before
  /// it expires.
  Future<ChatFileLink> fileLink(int roomId, int messageId) async {
    final ChatFileLink? cached = _links[messageId];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) return cached;
    final NovaApi? api = _api;
    if (api == null) {
      throw const ApiException(status: 0, code: ApiException.network, message: 'Offline preview');
    }
    final Json body = await api.get('/chats/$roomId/messages/$messageId/file');
    final ChatFileLink link = ChatFileLink.fromJson(body.obj('data') ?? <String, dynamic>{});
    _links[messageId] = link;
    return link;
  }

  /// A chat PDF's bytes, kept in memory only (never written to disk).
  Future<List<int>> pdfBytes(int roomId, int messageId) async {
    final ChatFileLink link = await fileLink(roomId, messageId);
    return _api!.getBytes(link.url);
  }

  /// Who read a message, with when.
  Future<List<ChatPerson>> seenBy(int roomId, int messageId) async {
    final NovaApi? api = _api;
    if (api == null) return const <ChatPerson>[];
    final Json body = await api.get('/chats/$roomId/messages/$messageId/seen');
    return body.list('data').map(ChatPerson.fromJson).toList();
  }

  Future<ChatMembersPage> members(int roomId, {String search = '', int page = 1}) async {
    final NovaApi? api = _api;
    if (api == null) {
      final String needle = search.trim().toLowerCase();
      final List<ChatPerson> all = <ChatPerson>[
        for (final ChatPerson person in _seededMembers[roomId] ?? const <ChatPerson>[])
          if (needle.isEmpty || (person.name ?? '').toLowerCase().contains(needle)) person,
      ];
      return ChatMembersPage(members: all, total: needle.isEmpty ? room(roomId)?.membersCount ?? all.length : all.length, hasMore: false);
    }
    final Json body = await api.get('/chats/$roomId/members', query: <String, Object?>{
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
    });
    final Json meta = body.obj('meta') ?? <String, dynamic>{};
    final List<ChatPerson> people = body.list('data').map(ChatPerson.fromJson).toList();
    return ChatMembersPage(
      members: people,
      total: meta.integer('total', people.length),
      hasMore: meta.integer('current_page', page) < meta.integer('last_page', page),
    );
  }

  Future<ChatPdfsPage> pdfs(int roomId, {int? beforeId}) async {
    final NovaApi? api = _api;
    if (api == null) return ChatPdfsPage(pdfs: _seededPdfs[roomId] ?? const <ChatMessage>[], hasMore: false);
    final Json body = await api.get('/chats/$roomId/pdfs', query: <String, Object?>{'before_id': beforeId});
    return ChatPdfsPage(
      pdfs: _parse(body),
      hasMore: body.obj('meta')?.flag('has_more') ?? false,
    );
  }

  // ── Reading ──────────────────────────────────────────────────────────

  /// The room on screen, and whether its latest message is shown: such a
  /// room is read as messages arrive, and makes no in-app notice.
  void setActive(int roomId, {required bool atBottom}) {
    _activeRoom = roomId;
    _activeAtBottom = atBottom;
  }

  void leave(int roomId) {
    if (_activeRoom != roomId) return;
    _activeRoom = null;
    _activeAtBottom = false;
  }

  /// The user saw the room's latest message: the badge clears at once and
  /// `POST /chats/{id}/read` follows, debounced (the cursor only moves
  /// forward on the server).
  void markRead(int roomId) {
    final ChatRoom? current = room(roomId);
    if (current == null) return;
    final int newest = math.max(_threads[roomId]?.newestId ?? 0, current.lastMessage?.id ?? 0);
    if (newest == 0) return;
    if (current.unreadCount != 0 || current.lastReadMessageId < newest) {
      _replaceRoom(current.copyWith(unreadCount: 0, lastReadMessageId: math.max(current.lastReadMessageId, newest)));
      notifyListeners();
    }
    if ((_readPosted[roomId] ?? 0) >= newest || _readTimers.containsKey(roomId)) return;
    _readTimers[roomId] = Timer(readDebounce, () => _postRead(roomId));
  }

  Future<void> _postRead(int roomId) async {
    _readTimers.remove(roomId);
    final ChatRoom? current = room(roomId);
    final int newest = math.max(_threads[roomId]?.newestId ?? 0, current?.lastReadMessageId ?? 0);
    if (newest <= (_readPosted[roomId] ?? 0)) return;
    final int previous = _readPosted[roomId] ?? 0;
    _readPosted[roomId] = newest;
    try {
      await _api?.post('/chats/$roomId/read', <String, int>{'message_id': newest});
    } on ApiException {
      // The next read tries again.
      if ((_readPosted[roomId] ?? 0) == newest) _readPosted[roomId] = previous;
    }
  }

  // ── Realtime (docs/D-143 §3.5) ───────────────────────────────────────

  /// One Reverb event of `private-chat.{roomId}` or its `.staff` channel.
  void handleEvent(int roomId, String event, Json data) {
    switch (event) {
      case 'ChatMessageSent':
        final ChatMessage message = ChatMessage.fromJson(data.obj('message') ?? data);
        if (message.id > 0) _onMessage(message.roomId == 0 ? roomId : message.roomId, message);
      case 'ChatMessageDeleted':
        _removeMessage(data.integer('room_id', roomId), data.integer('message_id'));
      case 'ChatRoomUpdated':
        if (data.str('reason') == 'deleted') _dropRoom(data.integer('room_id', roomId));
        loadRooms();
      case 'ChatRead':
        _onRead(data.integer('room_id', roomId), data.integer('user_id'), data.integer('last_read_message_id'));
      case 'ChatMemberRead':
        _onMemberRead(
          data.integer('room_id', roomId),
          data.integer('user_id'),
          data.integer('last_read_message_id'),
          data.integer('previous_read_message_id'),
        );
    }
  }

  void _onMessage(int roomId, ChatMessage message) {
    final ChatRoom? current = room(roomId);
    if (current == null) {
      // A room this user just joined.
      loadRooms();
      return;
    }
    final _Thread? thread = _threads[roomId];
    // Already listed, or already the room's latest (a repeated broadcast).
    final bool known = (thread?.messages.any((ChatMessage m) => m.id == message.id) ?? false) ||
        message.id <= (current.lastMessage?.id ?? 0);
    if (thread != null) _merge(thread, <ChatMessage>[message]);
    if (!known) _noteRoomMessage(roomId, message, announce: true);
    notifyListeners();
  }

  /// A new message updates its room: preview, order, unread count, and
  /// the in-app notice for someone else's message.
  void _noteRoomMessage(int roomId, ChatMessage message, {required bool announce}) {
    final ChatRoom? current = room(roomId);
    if (current == null) return;
    final bool newer = message.id > (current.lastMessage?.id ?? 0);
    final bool own = message.sender.id == _me;
    final bool reading = _activeRoom == roomId && _activeAtBottom && _foreground;
    // Not counted twice when the room list already has it.
    final bool unread = !own && newer && message.id > current.lastReadMessageId && !reading;
    final ChatRoom next = current.copyWith(
      lastMessage: newer ? ChatLastMessage.of(message) : null,
      lastMessageAt: newer ? message.createdAt ?? DateTime.now() : null,
      unreadCount: unread ? current.unreadCount + 1 : null,
      lastReadMessageId: own ? math.max(current.lastReadMessageId, message.id) : null,
    );
    _replaceRoom(next);
    if (!own && reading) markRead(roomId);
    if (announce && !own && !current.muted) {
      _arrivals.add(ChatArrival(room: next, message: message, inOpenRoom: _activeRoom == roomId));
    }
  }

  /// `ChatRead`: the Teacher or the Admin read up to a message (✓✓), or
  /// this user read on another device.
  void _onRead(int roomId, int userId, int lastRead) {
    final ChatRoom? current = room(roomId);
    if (current == null) return;
    final bool mine = userId == _me;
    final bool caughtUp = mine && lastRead >= (current.lastMessage?.id ?? 0);
    _replaceRoom(current.copyWith(
      staffLastReadMessageId: math.max(current.staffLastReadMessageId, lastRead),
      lastReadMessageId: mine ? math.max(current.lastReadMessageId, lastRead) : null,
      unreadCount: caughtUp ? 0 : null,
    ));
    if (mine) _readPosted[roomId] = math.max(_readPosted[roomId] ?? 0, lastRead);
    notifyListeners();
  }

  /// `ChatMemberRead` (staff channel): one more reader for every message
  /// between the member's previous and new cursor ("Seen by N").
  void _onMemberRead(int roomId, int userId, int lastRead, int previous) {
    final _Thread? thread = _threads[roomId];
    if (thread == null || lastRead <= previous) return;
    bool changed = false;
    final List<ChatMessage> next = <ChatMessage>[];
    for (final ChatMessage m in thread.messages) {
      final int? seen = m.seenCount;
      if (m.isConfirmed && seen != null && m.id > previous && m.id <= lastRead && m.sender.id != userId) {
        next.add(m.copyWith(seenCount: seen + 1));
        changed = true;
      } else {
        next.add(m);
      }
    }
    thread.messages = next;
    if (changed) notifyListeners();
  }

  bool get _foreground {
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _attach(ReverbClient? realtime) {
    _detach();
    _realtime = realtime;
    if (realtime == null) return;
    _wasConnected = realtime.connected.value;
    _everConnected = _wasConnected;
    realtime.connected.addListener(_onConnection);
    if (realtime.configured) realtime.connect();
    _syncSubscriptions();
  }

  void _detach() {
    for (final VoidCallback stop in _subscriptions.values) {
      stop();
    }
    _subscriptions.clear();
    _realtime?.connected.removeListener(_onConnection);
    _realtime = null;
    _wasConnected = false;
    _everConnected = false;
  }

  /// Back after a disconnection: the rooms and the messages missed.
  void _onConnection() {
    final bool up = _realtime?.connected.value ?? false;
    if (up && !_wasConnected && _everConnected) {
      loadRooms();
      for (final int roomId in <int>[..._threads.keys]) {
        if (_threads[roomId]!.loaded) catchUp(roomId);
      }
    }
    if (up) _everConnected = true;
    _wasConnected = up;
  }

  /// One subscription per room, plus the staff channel of rooms this user
  /// moderates.
  void _syncSubscriptions() {
    final ReverbClient? realtime = _realtime;
    if (realtime == null) return;
    final Map<String, int> wanted = <String, int>{
      for (final ChatRoom room in _rooms) ...<String, int>{
        'private-${room.channel}': room.id,
        if (room.canModerate) 'private-${room.channel}.staff': room.id,
      },
    };
    for (final String channel in <String>[..._subscriptions.keys]) {
      if (!wanted.containsKey(channel)) _subscriptions.remove(channel)!();
    }
    wanted.forEach((String channel, int roomId) {
      _subscriptions.putIfAbsent(
        channel,
        () => realtime.subscribe(channel, (String event, Json data) => handleEvent(roomId, event, data)),
      );
    });
  }

  /// While Reverb is down (or not configured), the unread total and the
  /// open room are checked every [pollInterval].
  Future<void> _pollTick() async {
    final NovaApi? api = _api;
    if (api == null || _me == 0 || !_foreground) return;
    if (_realtime?.connected.value ?? false) return;
    final int session = _session;
    try {
      final Json body = await api.get('/chats/unread-count');
      if (session != _session) return;
      if (body.obj('data')?.integer('total') != unreadTotal) await loadRooms();
    } on ApiException {
      return;
    }
    final int? active = _activeRoom;
    if (active != null && session == _session) await catchUp(active);
  }

  @override
  void dispose() {
    clear();
    _arrivals.close();
    _removed.close();
    super.dispose();
  }
}

class _Thread {
  List<ChatMessage> messages = <ChatMessage>[];
  bool loaded = false;
  bool hasMore = false;
  bool loadingOlder = false;
  ApiException? error;
  int generation = 0;

  int get oldestId {
    for (final ChatMessage m in messages) {
      if (m.isConfirmed) return m.id;
    }
    return 0;
  }

  int get newestId {
    for (final ChatMessage m in messages.reversed) {
      if (m.isConfirmed) return m.id;
    }
    return 0;
  }
}
