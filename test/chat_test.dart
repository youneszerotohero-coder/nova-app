import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show FormData;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/api_exception.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/chat_store.dart';
import 'package:nova_mobile/features/messages/chat_audio.dart';
import 'package:nova_mobile/features/messages/chat_bubble.dart';
import 'package:nova_mobile/features/messages/chat_image.dart';
import 'package:nova_mobile/features/messages/chat_info_screen.dart';
import 'package:nova_mobile/features/messages/chat_list_screen.dart';
import 'package:nova_mobile/features/messages/chat_notice_host.dart';
import 'package:nova_mobile/features/messages/chat_room_screen.dart';
import 'package:nova_mobile/features/messages/chat_widgets.dart';
import 'package:nova_mobile/features/shell/student_top_bar.dart';

import 'fixtures/chat_fixtures.dart';
import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'nova_font_loader.dart';

/// Waits (for real) until [done] holds: the store's requests go through
/// the real [NovaApi] and Dio, served by [FakeBackend].
Future<void> until(bool Function() done, {Duration timeout = const Duration(seconds: 3)}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Map<String, Object?> json(FakeRequest request) => Map<String, Object?>.from(request.data! as Map<dynamic, dynamic>);

const String _yesterday = '2026-10-10T18:00:00+00:00';
const String _today = '2026-10-11T07:00:00+00:00';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingSoundPlayer sounds;

  setUpAll(loadNovaFonts);
  setUp(() {
    sounds = RecordingSoundPlayer();
    ChatSounds.player = sounds;
    ChatSounds.resetThrottle();
    ChatVoicePlayer.instance.reset();
  });

  /// A started store on [backend], `GET /chats` answering [rooms].
  Future<ChatStore> started(FakeBackend backend, {List<Map<String, Object?>>? rooms}) async {
    backend.routes['GET /chats'] = FakeResponse(200, <String, Object?>{
      'data': rooms ?? <Map<String, Object?>>[roomJson(id: 3)],
    });
    final ChatStore store = ChatStore(fakeApi(backend));
    store.start(me: meId);
    addTearDown(store.clear);
    await until(() => store.roomsLoaded);
    return store;
  }

  group('ChatStore', () {
    test('the seen list of an announcement comes by pages of 50 with the total', () async {
      List<Map<String, Object?>> readers(int from, int count) => <Map<String, Object?>>[
            for (int i = from; i < from + count; i++) <String, Object?>{'user_id': i, 'name': 'Lecteur $i', 'role': 'student', 'read_at': '2026-10-17T08:00:00+00:00'},
          ];
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/1/messages/9/seen?page=1': FakeResponse(200, <String, Object?>{'data': readers(1, 50), 'meta': <String, Object?>{'total': 120, 'current_page': 1, 'last_page': 3, 'has_more': true}}),
        'GET /chats/1/messages/9/seen?page=3': FakeResponse(200, <String, Object?>{'data': readers(101, 20), 'meta': <String, Object?>{'total': 120, 'current_page': 3, 'last_page': 3, 'has_more': false}}),
      });
      final ChatStore store = await started(backend);
      final ChatMembersPage first = await store.seenBy(1, 9);
      expect(first.members, hasLength(50));
      expect(first.total, 120);
      expect(first.hasMore, isTrue);
      final ChatMembersPage last = await store.seenBy(1, 9, page: 3);
      expect(last.members, hasLength(20));
      expect(last.hasMore, isFalse);
    });

    test('a muted chat keeps its count but stays out of the badge total', () async {
      final ChatStore store = await started(FakeBackend(<String, FakeResponse>{}), rooms: <Map<String, Object?>>[
        roomJson(id: 3, name: 'Maths', unread: 4, lastMessage: lastJson(30, 'a', createdAt: '2026-10-11T07:00:00+00:00')),
        <String, Object?>{...roomJson(id: 5, name: 'Physique', unread: 2, lastMessage: lastJson(50, 'b', createdAt: '2026-10-11T08:00:00+00:00')), 'muted': true},
      ]);
      expect(store.unreadTotal, 6);
      expect(store.unreadBadgeTotal, 4);
    });

    test('rooms: the public room first, then the latest conversation; unread total', () async {
      final ChatStore store = await started(FakeBackend(<String, FakeResponse>{}), rooms: <Map<String, Object?>>[
        roomJson(id: 3, name: 'Maths', unread: 4, lastMessage: lastJson(30, 'a', createdAt: '2026-10-11T07:00:00+00:00')),
        roomJson(id: 5, name: 'Physique', lastMessage: lastJson(50, 'b', createdAt: '2026-10-11T08:00:00+00:00')),
        roomJson(id: 1, kind: 'public', name: 'public', unread: 1, lastMessage: lastJson(10, 'c', role: 'admin', sender: null, createdAt: '2026-10-01T08:00:00+00:00')),
      ]);
      expect(store.rooms.map((ChatRoom r) => r.id), <int>[1, 5, 3]);
      expect(store.unreadTotal, 5);
      expect(store.unreadBadgeTotal, 5);
      expect(store.rooms.first.isPublic, isTrue);
      expect(store.rooms.first.canViewMembers, isFalse);
    });

    test('pages of 30: latest, then older ones before the oldest id, ascending', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[for (int i = 31; i <= 60; i++) messageJson(id: i)], hasMore: true),
        'GET /chats/3/messages?before_id=31&limit=30': messagesPage(<Map<String, Object?>>[for (int i = 1; i <= 30; i++) messageJson(id: i)]),
      });
      final ChatStore store = await started(backend);

      await store.openThread(3);
      expect(store.messagesOf(3).map((ChatMessage m) => m.id), <int>[for (int i = 31; i <= 60; i++) i]);
      expect(store.hasOlder(3), isTrue);

      await store.loadOlder(3);
      expect(store.messagesOf(3).map((ChatMessage m) => m.id), <int>[for (int i = 1; i <= 60; i++) i]);
      expect(store.hasOlder(3), isFalse);
      // Nothing more to ask.
      final int asked = backend.requests.length;
      await store.loadOlder(3);
      expect(backend.requests.length, asked);
    });

    test('catching up asks after the newest id and merges without duplicates', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[messageJson(id: 1), messageJson(id: 2)]),
        'GET /chats/3/messages?after_id=2&limit=50': messagesPage(<Map<String, Object?>>[messageJson(id: 3), messageJson(id: 4)]),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      // Opened again: what arrived meanwhile.
      await store.openThread(3);
      expect(store.messagesOf(3).map((ChatMessage m) => m.id), <int>[1, 2, 3, 4]);
      // A late broadcast of one of them adds nothing.
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 4)});
      expect(store.messagesOf(3).map((ChatMessage m) => m.id), <int>[1, 2, 3, 4]);
      expect(backend.requests.where((FakeRequest r) => r.query.contains('after_id=2')), hasLength(1));
    });

    test('an optimistic text shows at once, then becomes the server message', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[messageJson(id: 1)]),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);

      backend.routes['POST /chats/3/messages'] = FakeResponse(201, <String, Object?>{
        'data': messageJson(id: 2, body: 'Salam', from: sender(meId, name: 'Ines')),
      });
      final Future<Object?> sending = store.sendText(3, '  Salam  ');
      final ChatMessage pending = store.messagesOf(3).last;
      expect(pending.state, ChatSendState.pending);
      expect(pending.body, 'Salam');
      expect(pending.sender.id, meId);

      expect(await sending, isNull);
      final FakeRequest post = backend.requests.lastWhere((FakeRequest r) => r.method == 'POST' && r.path == '/chats/3/messages');
      expect(json(post)['kind'], 'text');
      expect(json(post)['body'], 'Salam');
      expect(json(post)['client_uuid'], pending.clientUuid);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(pending.clientUuid!), isTrue);
      expect(store.messagesOf(3).map((ChatMessage m) => m.id), <int>[1, 2]);
      expect(store.room(3)!.lastMessage!.preview, 'Salam');
    });

    test('the broadcast of one\'s own message replaces the pending copy (same client_uuid)', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[]),
      }, sequences: <String, List<FakeResponse>>{
        'POST /chats/3/messages': <FakeResponse>[const FakeResponse(503, <String, Object?>{})],
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      final Future<Object?> sending = store.sendText(3, 'Hi');
      final String uuid = store.messagesOf(3).single.clientUuid!;
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{
        'message': messageJson(id: 9, body: 'Hi', from: sender(meId, name: 'Ines'), clientUuid: uuid),
      });
      expect(store.messagesOf(3).single.id, 9);
      expect(store.messagesOf(3).single.state, ChatSendState.sent);
      await sending;
      // Own messages are never unread nor announced.
      expect(store.room(3)!.unreadCount, 0);
    });

    test('a failed send stays marked, and a retry reuses its client_uuid', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[]),
      }, sequences: <String, List<FakeResponse>>{
        'POST /chats/3/messages': <FakeResponse>[
          const FakeResponse(500, <String, Object?>{'error': <String, Object?>{'code': 'SERVER_ERROR', 'message': 'x'}}),
          FakeResponse(201, <String, Object?>{'data': messageJson(id: 4, body: 'Retry me', from: sender(meId, name: 'Ines'))}),
        ],
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);

      final Object? error = await store.sendText(3, 'Retry me');
      expect(error, isNotNull);
      final ChatMessage failed = store.messagesOf(3).single;
      expect(failed.state, ChatSendState.failed);
      expect(failed.error, 'SERVER_ERROR');

      expect(await store.retry(3, failed.clientUuid!), isNull);
      final List<FakeRequest> posts = backend.requests.where((FakeRequest r) => r.method == 'POST' && r.path == '/chats/3/messages').toList();
      expect(posts, hasLength(2));
      expect(json(posts[0])['client_uuid'], json(posts[1])['client_uuid']);
      expect(store.messagesOf(3).single.id, 4);
      expect(store.messagesOf(3).single.state, ChatSendState.sent);
    });

    test('closed writing marks the message failed and reloads the room', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[]),
        'POST /chats/3/messages': const FakeResponse(403, <String, Object?>{'error': <String, Object?>{'code': 'CHAT_SEND_CLOSED', 'message': 'closed'}}),
        'GET /chats/3': FakeResponse(200, <String, Object?>{'data': roomJson(id: 3, studentsCanSend: false)}),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      final Object? error = await store.sendText(3, 'Hello');
      expect((error! as dynamic).code, 'CHAT_SEND_CLOSED');
      await until(() => !store.room(3)!.canSend);
      expect(store.messagesOf(3).single.state, ChatSendState.failed);
    });

    test('deleting removes the message for everyone; a broadcast deletion too', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[messageJson(id: 1), messageJson(id: 2), messageJson(id: 3)]),
        'DELETE /chats/3/messages/2': const FakeResponse(204),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);

      await store.deleteMessage(3, 2);
      expect(backend.requests.any((FakeRequest r) => r.method == 'DELETE' && r.path == '/chats/3/messages/2'), isTrue);
      expect(store.messagesOf(3).map((ChatMessage m) => m.id), <int>[1, 3]);

      store.handleEvent(3, 'ChatMessageDeleted', <String, dynamic>{'room_id': 3, 'message_id': 3});
      expect(store.messagesOf(3).map((ChatMessage m) => m.id), <int>[1]);
    });

    test('realtime: someone else\'s message counts unread and is announced, never for a muted room or one\'s own', () async {
      final ChatStore store = await started(FakeBackend(<String, FakeResponse>{}), rooms: <Map<String, Object?>>[
        roomJson(id: 3, lastMessage: lastJson(10, 'old')),
        roomJson(id: 4, name: 'Muted', muted: true),
      ]);
      final List<ChatArrival> arrivals = <ChatArrival>[];
      final StreamSubscription<ChatArrival> sub = store.arrivals.listen(arrivals.add);
      addTearDown(sub.cancel);

      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 11, body: 'Bonsoir')});
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 11, body: 'Bonsoir')});
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 12, from: sender(meId, name: 'Ines'))});
      store.handleEvent(4, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 13, roomId: 4, createdAt: '2026-10-11T09:00:00+00:00')});
      await Future<void>.delayed(Duration.zero);

      expect(store.room(3)!.unreadCount, 1);
      expect(store.room(4)!.unreadCount, 1);
      expect(store.unreadTotal, 2);
      expect(store.room(3)!.lastMessage!.id, 12);
      expect(arrivals.map((ChatArrival a) => a.message.id), <int>[11]);
      expect(arrivals.single.inOpenRoom, isFalse);
      // The room with the newest message comes first.
      expect(store.rooms.first.id, 4);
    });

    test('a message in the room on screen is read at once: no unread, one debounced read', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[messageJson(id: 1)]),
        'POST /chats/3/read': const FakeResponse(204),
      });
      final ChatStore store = await started(backend, rooms: <Map<String, Object?>>[roomJson(id: 3, unread: 1, lastMessage: lastJson(1, 'x'))]);
      await store.openThread(3);
      store.setActive(3, atBottom: true);
      final List<ChatArrival> arrivals = <ChatArrival>[];
      final StreamSubscription<ChatArrival> sub = store.arrivals.listen(arrivals.add);
      addTearDown(sub.cancel);

      store.markRead(3);
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 2)});
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 3)});
      store.markRead(3);
      await Future<void>.delayed(Duration.zero);
      expect(store.room(3)!.unreadCount, 0);
      expect(arrivals.map((ChatArrival a) => a.inOpenRoom), <bool>[true, true]);
      expect(backend.requests.where((FakeRequest r) => r.path == '/chats/3/read'), isEmpty);

      await Future<void>.delayed(ChatStore.readDebounce + const Duration(milliseconds: 150));
      await until(() => backend.requests.any((FakeRequest r) => r.path == '/chats/3/read'));
      final List<FakeRequest> reads = backend.requests.where((FakeRequest r) => r.path == '/chats/3/read').toList();
      expect(reads, hasLength(1));
      expect(json(reads.single)['message_id'], 3);

      // Already read: nothing more is posted.
      store.markRead(3);
      await Future<void>.delayed(ChatStore.readDebounce + const Duration(milliseconds: 100));
      expect(backend.requests.where((FakeRequest r) => r.path == '/chats/3/read'), hasLength(1));
    });

    test('ChatRead moves ✓✓; one\'s own read elsewhere clears the badge', () async {
      final ChatStore store = await started(FakeBackend(<String, FakeResponse>{}), rooms: <Map<String, Object?>>[
        roomJson(id: 3, unread: 2, lastRead: 8, staffLastRead: 5, lastMessage: lastJson(10, 'x')),
      ]);
      store.handleEvent(3, 'ChatRead', <String, dynamic>{'room_id': 3, 'user_id': teacherUserId, 'role': 'teacher', 'last_read_message_id': 9});
      expect(store.room(3)!.staffLastReadMessageId, 9);
      expect(store.room(3)!.unreadCount, 2);
      store.handleEvent(3, 'ChatRead', <String, dynamic>{'room_id': 3, 'user_id': meId, 'role': 'student', 'last_read_message_id': 10});
      expect(store.room(3)!.unreadCount, 0);
      expect(store.room(3)!.staffLastReadMessageId, 10);
    });

    test('ChatMemberRead adds one reader to the messages between both cursors', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[
          for (int i = 1; i <= 4; i++) messageJson(id: i, from: sender(meId, name: 'Karim', role: 'teacher'), seenCount: 2),
          messageJson(id: 5, from: sender(40, name: 'Lina'), seenCount: 0),
        ]),
      });
      final ChatStore store = await started(backend, rooms: <Map<String, Object?>>[roomJson(id: 3, canModerate: true)]);
      await store.openThread(3);
      store.handleEvent(3, 'ChatMemberRead', <String, dynamic>{'room_id': 3, 'user_id': 40, 'last_read_message_id': 5, 'previous_read_message_id': 2});
      expect(store.messagesOf(3).map((ChatMessage m) => m.seenCount), <int?>[2, 2, 3, 3, 0]);
      // A broadcast copy (no count) keeps the known count.
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 4, from: sender(meId, name: 'Karim', role: 'teacher'))});
      expect(store.messagesOf(3)[3].seenCount, 3);
    });

    test('a deleted room (or one left) is dropped and its screen told', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{});
      final ChatStore store = await started(backend, rooms: <Map<String, Object?>>[roomJson(id: 3), roomJson(id: 4)]);
      final List<int> removed = <int>[];
      final StreamSubscription<int> sub = store.removedRooms.listen(removed.add);
      addTearDown(sub.cancel);

      backend.routes['GET /chats'] = FakeResponse(200, <String, Object?>{'data': <Map<String, Object?>>[roomJson(id: 4)]});
      store.handleEvent(3, 'ChatRoomUpdated', <String, dynamic>{'room_id': 3, 'reason': 'deleted'});
      expect(store.room(3), isNull);
      await until(() => backend.requests.where((FakeRequest r) => r.path == '/chats').length >= 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(removed, <int>[3]);
      expect(store.rooms.map((ChatRoom r) => r.id), <int>[4]);

      // Membership lost on the server: the next list drops it too.
      backend.routes['GET /chats'] = const FakeResponse(200, <String, Object?>{'data': <Object?>[]});
      store.handleEvent(4, 'ChatRoomUpdated', <String, dynamic>{'room_id': 4, 'reason': 'members'});
      await until(() => removed.length == 2);
      expect(removed, <int>[3, 4]);
    });

    test('voice notes and PDFs upload as multipart with their kind and client_uuid', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[]),
        'POST /chats/3/messages': FakeResponse(201, <String, Object?>{
          'data': messageJson(id: 7, kind: 'voice', from: sender(meId, name: 'Ines'), attachment: voiceAttachment(durationMs: 4200)),
        }),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      final String path = '${(await Directory.systemTemp.createTemp('nova-chat')).path}/voice.m4a';
      await File(path).writeAsBytes(List<int>.filled(64, 1));

      expect(await store.sendVoice(3, path: path, durationMs: 4200, waveform: const <int>[10, 50]), isNull);
      final FakeRequest post = backend.requests.lastWhere((FakeRequest r) => r.method == 'POST' && r.path == '/chats/3/messages');
      final FormData form = post.data! as FormData;
      final Map<String, String> fields = <String, String>{for (final MapEntry<String, String> f in form.fields) f.key: f.value};
      expect(fields['kind'], 'voice');
      expect(fields['duration_ms'], '4200');
      expect(fields['client_uuid'], isNotEmpty);
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'voice.m4a');
      expect(form.files.single.value.contentType.toString(), 'audio/mp4');
      expect(store.messagesOf(3).single.id, 7);
      // The recording is deleted once the server has it.
      expect(File(path).existsSync(), isFalse);
    });

    // ── D-156 photos, pins, reactions ──────────────────────────────────

    List<String> counts(ChatMessage m) => <String>[for (final ChatReaction r in m.reactions) '${r.emoji}${r.count}'];

    test('D-156: a room and a message parse photos, pins and reactions', () {
      final ChatRoom staff = room(roomJson(id: 3, canSendPdf: true, canPin: true, pinnedCount: 2));
      expect(staff.canSendImage, isTrue);
      expect(staff.canPin, isTrue);
      expect(staff.canReact, isTrue);
      expect(staff.pinnedCount, 2);
      expect(staff.reactionEmojis, <String>['👍', '❤️', '😂', '😮', '😢', '🙏']);
      // A payload without the new fields offers none of them.
      final ChatRoom older = ChatRoom.fromJson(<String, dynamic>{'id': 4, 'kind': 'group', 'name': 'x'});
      expect(older.canSendImage || older.canPin || older.canReact, isFalse);
      expect(older.pinnedCount, 0);
      expect(older.reactionEmojis, chatDefaultReactions);

      final ChatMessage photo = message(messageJson(
        id: 9,
        kind: 'image',
        body: 'Le tableau',
        attachment: imageAttachment(width: 1200, height: 1600),
        pinnedAt: '2026-10-25T10:00:00+00:00',
        reactions: <Map<String, Object?>>[reaction('👍', 12), reaction('❤️', 3), reaction('😂', 0)],
        myReaction: '👍',
      ));
      expect(photo.kind, ChatMessageKind.image);
      expect(photo.attachment!.width, 1200);
      expect(photo.attachment!.height, 1600);
      expect(photo.attachment!.aspectRatio, 0.75);
      expect(photo.isPinned, isTrue);
      expect(counts(photo), <String>['👍12', '❤️3']);
      expect(photo.myReaction, '👍');
      final ChatMessage plain = message(messageJson(id: 10));
      expect(plain.isPinned, isFalse);
      expect(plain.reactions, isEmpty);
      expect(plain.myReaction, isNull);
      // A photo without caption previews as '' (the app shows "Photo").
      expect(ChatLastMessage.of(message(messageJson(id: 11, kind: 'image', attachment: imageAttachment()))).preview, '');
    });

    test('D-156: a reaction shows at once and the answer settles it; another emoji replaces it, the same one removes it', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[
          messageJson(id: 5, reactions: <Map<String, Object?>>[reaction('👍', 2)]),
        ]),
      }, sequences: <String, List<FakeResponse>>{
        'PUT /chats/3/messages/5/reaction': <FakeResponse>[
          FakeResponse(200, <String, Object?>{
            'data': <String, Object?>{'message_id': 5, 'reactions': <Object?>[reaction('👍', 3)], 'my_reaction': '👍'},
          }),
          // Someone else's ❤️ landed meanwhile.
          FakeResponse(200, <String, Object?>{
            'data': <String, Object?>{'message_id': 5, 'reactions': <Object?>[reaction('👍', 2), reaction('❤️', 2)], 'my_reaction': '❤️'},
          }),
        ],
        'DELETE /chats/3/messages/5/reaction': <FakeResponse>[
          FakeResponse(200, <String, Object?>{
            'data': <String, Object?>{'message_id': 5, 'reactions': <Object?>[reaction('👍', 2), reaction('❤️', 1)], 'my_reaction': null},
          }),
        ],
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      ChatMessage shown() => store.messagesOf(3).single;

      final Future<ApiException?> liking = store.react(3, 5, '👍');
      expect(shown().myReaction, '👍');
      expect(counts(shown()), <String>['👍3']);
      expect(await liking, isNull);
      final FakeRequest put = backend.requests.lastWhere((FakeRequest r) => r.method == 'PUT');
      expect(put.path, '/chats/3/messages/5/reaction');
      expect(json(put)['emoji'], '👍');

      final Future<ApiException?> loving = store.react(3, 5, '❤️');
      expect(counts(shown()), <String>['👍2', '❤️1']);
      expect(await loving, isNull);
      expect(counts(shown()), <String>['👍2', '❤️2']);
      expect(shown().myReaction, '❤️');

      expect(await store.react(3, 5, '❤️'), isNull);
      expect(backend.requests.where((FakeRequest r) => r.method == 'DELETE' && r.path == '/chats/3/messages/5/reaction'), hasLength(1));
      expect(shown().myReaction, isNull);
      expect(counts(shown()), <String>['👍2', '❤️1']);
    });

    test('D-156: a refused reaction goes back to the counts the server knows', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[
          messageJson(id: 5, reactions: <Map<String, Object?>>[reaction('👍', 2)], myReaction: '👍'),
        ]),
        'PUT /chats/3/messages/5/reaction': const FakeResponse(429, <String, Object?>{'error': <String, Object?>{'code': 'TOO_MANY_REQUESTS', 'message': 'x'}}),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      final Future<ApiException?> reacting = store.react(3, 5, '😮');
      expect(counts(store.messagesOf(3).single), <String>['👍1', '😮1']);
      final ApiException? error = await reacting;
      expect(error?.status, 429);
      expect(counts(store.messagesOf(3).single), <String>['👍2']);
      expect(store.messagesOf(3).single.myReaction, '👍');
    });

    test('D-156: ChatReactionsChanged sets the counts; the viewer\'s own emoji changes only with their own reaction', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[
          messageJson(id: 5, reactions: <Map<String, Object?>>[reaction('👍', 1)], myReaction: '👍'),
        ]),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      store.handleEvent(3, 'ChatReactionsChanged', <String, dynamic>{
        'room_id': 3,
        'message_id': 5,
        'reactions': <Object?>[reaction('👍', 1), reaction('😂', 1)],
        'user_id': 40,
        'emoji': '😂',
      });
      expect(counts(store.messagesOf(3).single), <String>['👍1', '😂1']);
      expect(store.messagesOf(3).single.myReaction, '👍');

      // This user's own reaction from another device.
      store.handleEvent(3, 'ChatReactionsChanged', <String, dynamic>{
        'room_id': 3,
        'message_id': 5,
        'reactions': <Object?>[reaction('😂', 2)],
        'user_id': meId,
        'emoji': '😂',
      });
      expect(store.messagesOf(3).single.myReaction, '😂');
      // A repeated broadcast of the message (no reactions) keeps them.
      store.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 5)});
      expect(counts(store.messagesOf(3).single), <String>['😂2']);
      expect(store.messagesOf(3).single.myReaction, '😂');
    });

    test('D-156: ChatPinsChanged marks the message and fetches the pins again; a deleted message drops its pin', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[messageJson(id: 1), messageJson(id: 2, body: 'Le devoir')]),
        'GET /chats/3/pins': FakeResponse(200, <String, Object?>{
          'data': <Object?>[messageJson(id: 2, body: 'Le devoir', pinnedAt: '2026-10-25T10:00:00+00:00')],
        }),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);

      store.handleEvent(3, 'ChatPinsChanged', <String, dynamic>{'room_id': 3, 'message_id': 2, 'pinned_at': '2026-10-25T10:00:00+00:00'});
      expect(store.messagesOf(3)[1].isPinned, isTrue);
      expect(store.room(3)!.pinnedCount, 1);
      await until(() => backend.requests.any((FakeRequest r) => r.path == '/chats/3/pins'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(store.pinsOf(3).map((ChatMessage m) => m.id), <int>[2]);
      expect(store.room(3)!.pinnedCount, 1);

      store.handleEvent(3, 'ChatMessageDeleted', <String, dynamic>{'room_id': 3, 'message_id': 2});
      expect(store.pinsOf(3), isEmpty);
      expect(store.room(3)!.pinnedCount, 0);
    });

    test('D-156: pin and unpin call the API; pinning twice counts once', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[messageJson(id: 1), messageJson(id: 2)]),
        'PUT /chats/3/messages/2/pin': FakeResponse(200, <String, Object?>{'data': messageJson(id: 2, pinnedAt: '2026-10-25T10:00:00+00:00')}),
        'DELETE /chats/3/messages/2/pin': const FakeResponse(204),
      });
      final ChatStore store = await started(backend, rooms: <Map<String, Object?>>[roomJson(id: 3, canModerate: true, canPin: true)]);
      await store.openThread(3);

      await store.pin(3, 2);
      await store.pin(3, 2);
      expect(backend.requests.where((FakeRequest r) => r.method == 'PUT' && r.path == '/chats/3/messages/2/pin'), hasLength(2));
      expect(store.room(3)!.pinnedCount, 1);
      expect(store.pinsOf(3).single.id, 2);
      expect(store.messagesOf(3)[1].pinnedAt, DateTime.parse('2026-10-25T10:00:00+00:00').toLocal());

      await store.unpin(3, 2);
      expect(backend.requests.any((FakeRequest r) => r.method == 'DELETE' && r.path == '/chats/3/messages/2/pin'), isTrue);
      expect(store.room(3)!.pinnedCount, 0);
      expect(store.pinsOf(3), isEmpty);
      expect(store.messagesOf(3)[1].isPinned, isFalse);
    });

    test('D-156: jumping to a pin far up loads older pages until it is there', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[for (int i = 61; i <= 90; i++) messageJson(id: i)], hasMore: true),
        'GET /chats/3/messages?before_id=61&limit=30': messagesPage(<Map<String, Object?>>[for (int i = 31; i <= 60; i++) if (i != 45) messageJson(id: i)], hasMore: true),
        'GET /chats/3/messages?before_id=31&limit=30': messagesPage(<Map<String, Object?>>[for (int i = 1; i <= 30; i++) messageJson(id: i)]),
      });
      final ChatStore store = await started(backend);
      await store.openThread(3);
      expect(await store.loadUntil(3, 12), isTrue);
      expect(store.messagesOf(3).first.id, 1);
      // Deleted since: not there, and nothing more to ask.
      final int asked = backend.requests.length;
      expect(await store.loadUntil(3, 45), isFalse);
      expect(backend.requests.length, asked);
    });

    test('D-156: a photo uploads as multipart kind image with its caption; its preview link asks variant=preview', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /chats/3/messages?limit=30': messagesPage(<Map<String, Object?>>[]),
        'POST /chats/3/messages': FakeResponse(201, <String, Object?>{
          'data': messageJson(id: 8, kind: 'image', body: 'Le tableau', from: sender(meId, name: 'Karim', role: 'teacher'), attachment: imageAttachment()),
        }),
        'GET /chats/3/messages/8/file': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{'url': 'https://nova.test/api/v1/chat-files/8?signature=a', 'expires_at': '2099-01-01T00:00:00+00:00', 'mime': 'image/jpeg', 'name': 'tableau.jpg'},
        }),
      });
      final ChatStore store = await started(backend, rooms: <Map<String, Object?>>[roomJson(id: 3, canModerate: true, canSendPdf: true)]);
      await store.openThread(3);
      final String path = '${(await Directory.systemTemp.createTemp('nova-chat')).path}/tableau.png';
      await File(path).writeAsBytes(List<int>.filled(64, 1));

      final Future<ApiException?> sending = store.sendImage(3, path: path, name: 'tableau.png', caption: '  Le tableau ', width: 800, height: 600);
      final ChatMessage pending = store.messagesOf(3).single;
      expect(pending.kind, ChatMessageKind.image);
      expect(pending.state, ChatSendState.pending);
      expect(pending.attachment!.aspectRatio, 800 / 600);
      expect(await sending, isNull);
      final FakeRequest post = backend.requests.lastWhere((FakeRequest r) => r.method == 'POST' && r.path == '/chats/3/messages');
      final FormData form = post.data! as FormData;
      final Map<String, String> fields = <String, String>{for (final MapEntry<String, String> f in form.fields) f.key: f.value};
      expect(fields['kind'], 'image');
      expect(fields['body'], 'Le tableau');
      expect(fields['client_uuid'], pending.clientUuid);
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'tableau.png');
      expect(form.files.single.value.contentType.toString(), 'image/png');
      expect(store.messagesOf(3).single.id, 8);
      // A picked photo is the user's own: it stays on the phone.
      expect(File(path).existsSync(), isTrue);

      await store.fileLink(3, 8, preview: true);
      await store.fileLink(3, 8, preview: true);
      await store.fileLink(3, 8);
      final List<FakeRequest> links = backend.requests.where((FakeRequest r) => r.path == '/chats/3/messages/8/file').toList();
      expect(links.map((FakeRequest r) => r.query), <String>['variant=preview', '']);

      expect(ChatStore.imageMimeOf('IMG_0001.JPG'), 'image/jpeg');
      expect(ChatStore.imageMimeOf('a.webp'), 'image/webp');
      expect(ChatStore.imageMimeOf('IMG_0001.HEIC'), isNull);
    });
  });

  group('chat screens', () {
    late ChatStore chat;

    Future<void> pump(WidgetTester tester, Widget screen, {NovaLang lang = NovaLang.en, Widget Function(BuildContext, Widget?)? builder, GlobalKey<NavigatorState>? navigator}) async {
      final AppState base = installFixtureApp(lang: lang);
      final AppState state = AppState.seeded(
        session: base.session,
        catalog: base.catalog,
        learning: base.learning,
        commerce: base.commerce,
        account: base.account,
        lang: lang,
        chat: chat,
      );
      AppState.instance = state;
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      // A fresh tree: a screen pumped again starts over with this state.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            navigatorKey: navigator,
            theme: NovaTheme.light,
            locale: lang.locale,
            supportedLocales: const <Locale>[Locale('en'), Locale('fr'), Locale('ar')],
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: builder,
            home: screen,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
    }

    /// Frames 50 ms apart: animations started by a stream event or a tap
    /// get their first tick before time jumps.
    Future<void> frames(WidgetTester tester, int ms) async {
      for (int i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// Lets the debounced read and the entrances run out.
    Future<void> finish(WidgetTester tester) => tester.pump(const Duration(seconds: 1));

    goldenTestWidgets('the list shows the announcements first, unread counts and the muted mark', (tester) async {
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[
        room(roomJson(id: 3, name: 'Maths 3AS', unread: 3, lastMessage: lastJson(30, 'Bonsoir', createdAt: '2026-10-11T08:30:00+00:00'))),
        room(roomJson(id: 4, name: 'Physique', muted: true, unread: 2, lastMessage: lastJson(40, '', kind: 'voice', createdAt: '2026-10-11T08:40:00+00:00'))),
        room(roomJson(id: 1, kind: 'public', name: 'x', lastMessage: lastJson(10, 'Rentrée', role: 'admin', sender: null, createdAt: '2026-10-01T08:00:00+00:00'))),
      ]);
      await pump(tester, const ChatListScreen());

      final double announcements = tester.getTopLeft(find.text('NOVA announcements')).dy;
      expect(announcements, lessThan(tester.getTopLeft(find.text('Physique')).dy));
      expect(tester.getTopLeft(find.text('Physique')).dy, lessThan(tester.getTopLeft(find.text('Maths 3AS')).dy));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_rounded), findsOneWidget);
      expect(find.textContaining('Karim Benali: Voice message'), findsOneWidget);
      // The muted chat keeps its grey 2 but stays out of the header total, as on the website.
      expect(find.text('3 unread'), findsOneWidget);
      await finish(tester);
    });

    ChatStore roomStore({bool canModerate = false, bool canSend = true, String kind = 'group'}) => ChatStore.seeded(
          me: meId,
          rooms: <ChatRoom>[
            room(roomJson(id: 3, kind: kind, canModerate: canModerate, canSend: canSend, staffLastRead: 3, lastRead: 6, lastMessage: lastJson(6, 'x'))),
          ],
          messages: <int, List<ChatMessage>>{
            3: <ChatMessage>[
              message(messageJson(id: 1, body: 'Yesterday’s homework', createdAt: _yesterday)),
              message(messageJson(id: 2, body: 'Mine, seen', from: sender(meId, name: 'Ines'), createdAt: _today)),
              message(messageJson(id: 3, body: 'Mine too, seen', from: sender(meId, name: 'Ines'), createdAt: _today)),
              message(messageJson(id: 4, body: 'From Lina', from: sender(40, name: 'Lina Haddad'), createdAt: _today)),
              message(messageJson(id: 5, body: 'From NOVA', from: sender(1, role: 'admin'), createdAt: _today)),
              message(messageJson(id: 6, body: 'Mine, not seen yet', from: sender(meId, name: 'Ines'), createdAt: _today)),
            ],
          },
        );

    testWidgets('D-193 PC app: the chosen room opens beside the list, without a back arrow', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        chat = roomStore();
        await pump(tester, const ChatListScreen());
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Choose a conversation on the left.'), findsOneWidget);
        expect(find.byType(ChatRoomScreen), findsNothing);

        await tester.tap(find.byType(ChatRoomAvatar).first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(ChatListScreen), findsOneWidget);
        expect(find.byType(ChatRoomScreen), findsOneWidget);
        expect(find.text('From Lina'), findsOneWidget);
        expect(find.descendant(of: find.byType(ChatRoomScreen), matching: find.byIcon(Icons.arrow_back_rounded)), findsNothing);
        // A banner or notification for a room shows it here too.
        expect(ChatListScreen.openBeside(3), isTrue);
        await finish(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    goldenTestWidgets('a room shows day separators, ✓/✓✓ on own messages, the Teacher badge and NOVA Administration', (tester) async {
      chat = roomStore();
      await pump(tester, const ChatRoomScreen(roomId: 3));

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('tick-seen')), findsNWidgets(2));
      expect(find.byKey(const ValueKey<String>('tick-sent')), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Karim Benali'), findsOneWidget);
      expect(find.text('NOVA Administration'), findsOneWidget);
      expect(find.text('Lina Haddad'), findsOneWidget);
      // The time of every message, Algeria time (UTC+1).
      expect(find.text('08:00'), findsNWidgets(5));
      expect(find.text('19:00'), findsOneWidget);
      // Own messages sit at the end side (the right in English).
      expect(tester.getTopRight(find.text('Mine, seen')).dx, greaterThan(tester.getTopRight(find.text('From Lina')).dx));
      await finish(tester);
    });

    goldenTestWidgets('Students without writing rights see the locked banner instead of the composer', (tester) async {
      chat = roomStore(canSend: false);
      await pump(tester, const ChatRoomScreen(roomId: 3));
      expect(find.byKey(const ValueKey<String>('composer-locked')), findsOneWidget);
      expect(find.text('Only the teacher writes in this group.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await finish(tester);

      chat = roomStore(canSend: false, kind: 'public');
      await pump(tester, const ChatRoomScreen(roomId: 3));
      expect(find.text('Only NOVA posts in the announcements.'), findsOneWidget);
      await finish(tester);
    });

    goldenTestWidgets('a Student deletes only their own messages; the Teacher any message', (tester) async {
      chat = roomStore();
      await pump(tester, const ChatRoomScreen(roomId: 3));

      await tester.longPress(find.text('From Lina'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Message info'), findsNothing);
      Navigator.of(tester.element(find.text('Copy'))).pop();
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Mine, seen'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Message info'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this message?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Mine, seen'), findsNothing);
      await finish(tester);

      chat = roomStore(canModerate: true);
      await pump(tester, const ChatRoomScreen(roomId: 3));
      await tester.longPress(find.text('From Lina'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Message info'), findsOneWidget);
      await finish(tester);
    });

    goldenTestWidgets('a voice note draws its waveform and its duration', (tester) async {
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3))], messages: <int, List<ChatMessage>>{
        3: <ChatMessage>[message(messageJson(id: 8, kind: 'voice', attachment: voiceAttachment(durationMs: 42000), createdAt: _today))],
      });
      await pump(tester, const ChatRoomScreen(roomId: 3));
      final CustomPaint paint = tester.widget<CustomPaint>(find.byKey(const ValueKey<String>('waveform-m8')));
      final ChatWaveformPainter painter = paint.painter! as ChatWaveformPainter;
      expect(painter.peaks, hasLength(48));
      expect(painter.progress, 0);
      expect(find.text('0:42'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await finish(tester);
    });

    goldenTestWidgets('recording: the bar with its timer, then the voice note is sent', (tester) async {
      final FakeRecorder recorder = FakeRecorder();
      final ChatRecorder Function() previous = ChatRecorder.factory;
      ChatRecorder.factory = () => recorder;
      addTearDown(() => ChatRecorder.factory = previous);
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3))], messages: <int, List<ChatMessage>>{3: <ChatMessage>[]});
      await pump(tester, const ChatRoomScreen(roomId: 3));

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(recorder.started, isTrue);
      expect(find.byKey(const ValueKey<String>('composer-recording')), findsOneWidget);
      for (int i = 0; i < 20; i++) {
        recorder.emit((i % 5) / 5);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('0:02'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Send the voice message'));
      await tester.pump(const Duration(milliseconds: 400));
      final ChatMessage sent = chat.messagesOf(3).single;
      expect(sent.kind, ChatMessageKind.voice);
      expect(sent.attachment!.waveform, hasLength(48));
      expect(sent.attachment!.durationMs, greaterThanOrEqualTo(2000));
      expect(sounds.played.map(((ChatSound, double) p) => p.$1), <ChatSound>[ChatSound.send]);
      await finish(tester);
    });

    goldenTestWidgets('a refused microphone says how to allow it', (tester) async {
      final ChatRecorder Function() previous = ChatRecorder.factory;
      ChatRecorder.factory = () => FakeRecorder(allowed: false);
      addTearDown(() => ChatRecorder.factory = previous);
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3))], messages: <int, List<ChatMessage>>{3: <ChatMessage>[]});
      await pump(tester, const ChatRoomScreen(roomId: 3));
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Microphone access is off'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('composer-recording')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    goldenTestWidgets('a message for another room slides in the notice with the receive sound; tapping opens it', (tester) async {
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3, name: 'Maths 3AS'))], messages: <int, List<ChatMessage>>{3: <ChatMessage>[]});
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await pump(
        tester,
        const Scaffold(body: SizedBox.expand()),
        navigator: navigator,
        builder: (BuildContext context, Widget? child) => ChatNoticeHost(navigatorKey: navigator, child: child!),
      );

      chat.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 1, body: 'Le devoir est en ligne')});
      await frames(tester, 500);
      expect(find.text('Maths 3AS'), findsOneWidget);
      expect(find.text('Karim Benali: Le devoir est en ligne'), findsOneWidget);
      expect(sounds.played, <(ChatSound, double)>[(ChatSound.receive, 0.7)]);
      expect(chat.unreadTotal, 1);

      await tester.tap(find.text('Maths 3AS'));
      await frames(tester, 600);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(chat.activeRoom, 3);

      // In the room on screen: the soft sound only, no notice.
      ChatSounds.resetThrottle();
      chat.handleEvent(3, 'ChatMessageSent', <String, dynamic>{'message': messageJson(id: 2, body: 'Second')});
      await frames(tester, 400);
      expect(sounds.played.last, (ChatSound.receive, 0.3));
      expect(find.text('Karim Benali: Second'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    goldenTestWidgets('a 360 px phone in Arabic: list (also as the Teacher tab), room and info fit', (tester) async {
      chat = tourChatStore();
      for (final Widget screen in <Widget>[
        const ChatListScreen(),
        const ChatListScreen(embedded: true),
        const ChatRoomScreen(roomId: 3),
        const ChatInfoScreen(roomId: 3),
      ]) {
        await pump(tester, screen, lang: NovaLang.ar);
        tester.view.physicalSize = const Size(1080, 2220);
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: '$screen');
        if (screen is ChatListScreen) expect(find.byType(BackPill), screen.embedded ? findsNothing : findsOneWidget);
        await finish(tester);
      }
    });

    goldenTestWidgets('the top bar holds the chat icon with the unread total, next to the bell', (tester) async {
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3, unread: 4)), room(roomJson(id: 1, kind: 'public', unread: 1))]);
      await pump(tester, const Scaffold(body: Column(children: <Widget>[StudentTopBar()])));
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.forum_outlined));
      await frames(tester, 600);
      expect(find.byType(ChatListScreen), findsOneWidget);
      await finish(tester);
    });

    // ── D-156 photos, pins, reactions ──────────────────────────────────

    goldenTestWidgets('D-156: the photo button is for the staff; a photo keeps its aspect ratio and offers a retry', (tester) async {
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3))], messages: <int, List<ChatMessage>>{
        3: <ChatMessage>[
          message(messageJson(id: 8, kind: 'image', body: 'Le tableau', attachment: imageAttachment(width: 1600, height: 1200), createdAt: _today)),
        ],
      });
      await pump(tester, const ChatRoomScreen(roomId: 3));
      expect(find.byKey(const ValueKey<String>('composer-photo')), findsNothing);
      final Size box = tester.getSize(find.byKey(const ValueKey<String>('chat-image-8-0')));
      expect(box.width / box.height, closeTo(4 / 3, 0.01));
      expect(find.text('Le tableau'), findsOneWidget);
      // Offline: the picture cannot load, and says how to retry.
      expect(find.text('The photo did not load. Tap to retry.'), findsOneWidget);
      await finish(tester);

      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3, canModerate: true, canSendPdf: true))], messages: <int, List<ChatMessage>>{3: <ChatMessage>[]});
      await pump(tester, const ChatRoomScreen(roomId: 3));
      expect(find.byKey(const ValueKey<String>('composer-photo')), findsOneWidget);
      expect(find.bySemanticsLabel('Send a photo'), findsOneWidget);
      await finish(tester);
    });

    goldenTestWidgets('D-156: the quick bar reacts and a chip toggles; Pin is offered only when the room allows it', (tester) async {
      List<ChatMessage> thread() => <ChatMessage>[
            message(messageJson(id: 4, body: 'From Lina', from: sender(40, name: 'Lina Haddad'), createdAt: _today, reactions: <Map<String, Object?>>[reaction('👍', 2)])),
          ];
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3))], messages: <int, List<ChatMessage>>{3: thread()});
      await pump(tester, const ChatRoomScreen(roomId: 3));
      expect(find.byKey(const ValueKey<String>('reaction-4-👍')), findsOneWidget);

      await tester.longPress(find.text('From Lina'));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('quick-❤️')));
      await tester.pumpAndSettle();
      expect(chat.messagesOf(3).single.myReaction, '❤️');
      expect(find.byKey(const ValueKey<String>('reaction-4-❤️')), findsOneWidget);

      // Tapping one's own chip again removes it.
      await tester.tap(find.byKey(const ValueKey<String>('reaction-4-❤️')));
      await tester.pumpAndSettle();
      expect(chat.messagesOf(3).single.myReaction, isNull);
      expect(find.byKey(const ValueKey<String>('reaction-4-❤️')), findsNothing);
      await finish(tester);

      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3, canModerate: true, canPin: true))], messages: <int, List<ChatMessage>>{3: thread()});
      await pump(tester, const ChatRoomScreen(roomId: 3));
      expect(find.byKey(const ValueKey<String>('chat-pinned-bar')), findsNothing);
      await tester.longPress(find.text('From Lina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();
      expect(chat.room(3)!.pinnedCount, 1);
      expect(find.byKey(const ValueKey<String>('chat-pinned-bar')), findsOneWidget);
      expect(find.text('Pinned message'), findsOneWidget);
      expect(find.text('Lina Haddad: From Lina'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('pin-mark')), findsOneWidget);

      // The toast goes first.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('From Lina'));
      await tester.pumpAndSettle();
      expect(find.text('Unpin'), findsOneWidget);
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('chat-pinned-bar')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    goldenTestWidgets('D-156: the pinned bar shows the newest pin and the count; its list scrolls to a pin', (tester) async {
      final List<ChatMessage> thread = <ChatMessage>[
        for (int i = 1; i <= 40; i++)
          message(messageJson(id: i, body: 'Message $i', createdAt: _today, pinnedAt: i == 2 || i == 30 ? '2026-10-11T08:00:00+00:00' : null)),
      ];
      chat = ChatStore.seeded(
        me: meId,
        rooms: <ChatRoom>[room(roomJson(id: 3, pinnedCount: 2))],
        messages: <int, List<ChatMessage>>{3: thread},
        pins: <int, List<ChatMessage>>{3: <ChatMessage>[thread[29], thread[1]]},
      );
      await pump(tester, const ChatRoomScreen(roomId: 3));
      expect(find.text('2 pinned messages'), findsOneWidget);
      expect(find.text('Karim Benali: Message 30'), findsOneWidget);
      expect(find.text('Message 2').hitTestable(), findsNothing);

      await tester.tap(find.bySemanticsLabel('Pinned messages'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('pin-30')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('pin-2')));
      await frames(tester, 1500);
      expect(find.text('Message 2').hitTestable(), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    goldenTestWidgets('D-156: the photo viewer is black, zooms and closes', (tester) async {
      final ChatMessage photo = message(messageJson(id: 8, kind: 'image', body: 'Le tableau', attachment: imageAttachment(), createdAt: _today));
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[room(roomJson(id: 3))], messages: <int, List<ChatMessage>>{3: <ChatMessage>[photo]});
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await pump(tester, const Scaffold(body: SizedBox.expand()), navigator: navigator);
      navigator.currentState!.push(chatImageRoute(chat, photo));
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, Colors.black);
      final InteractiveViewer viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(viewer.maxScale, greaterThan(1));
      expect(find.text('Le tableau'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatImageViewer), findsNothing);
    });

    goldenTestWidgets('D-156: the list previews a photo without caption as "Photo"', (tester) async {
      chat = ChatStore.seeded(me: meId, rooms: <ChatRoom>[
        room(roomJson(id: 3, name: 'Maths 3AS', lastMessage: lastJson(30, '', kind: 'image'))),
      ]);
      await pump(tester, const ChatListScreen());
      expect(find.textContaining('Karim Benali: Photo'), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
      await finish(tester);
    });
  });
}
