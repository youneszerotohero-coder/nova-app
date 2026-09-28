import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/json.dart';
import '../api/api_exception.dart';
import '../api/nova_api.dart';

typedef ReverbListener = void Function(String event, Json data);

/// Minimal Laravel Reverb client (Pusher protocol 7), the mobile
/// counterpart of the web's Laravel Echo setup (`lib/realtime.ts`):
/// private and presence channels are authorized by
/// `POST /broadcasting/auth` with the same session cookie.
///
/// The app key is public by design but not in this repository, so it is
/// supplied at build time (`--dart-define=NOVA_REVERB_KEY=…`). Without
/// it the app polls exactly like the web does when Reverb is down.
class ReverbClient {
  ReverbClient(this._api);

  static const String appKey = String.fromEnvironment('NOVA_REVERB_KEY');
  static const String host = String.fromEnvironment(
    'NOVA_REVERB_HOST',
    defaultValue: 'nova-elearning.com',
  );

  final NovaApi _api;
  final Map<String, List<ReverbListener>> _listeners = <String, List<ReverbListener>>{};
  final Map<String, int> _presenceCounts = <String, int>{};

  /// True while the socket is open and identified.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  String? _socketId;
  Timer? _retry;
  int _failures = 0;
  bool _wanted = false;

  bool get configured => appKey.isNotEmpty;

  /// Members currently in a presence channel (viewer count).
  int? presenceCount(String channel) => _presenceCounts[channel];

  void connect() {
    if (!configured || _socket != null) return;
    _wanted = true;
    final Uri uri = Uri.parse(
      'wss://$host/app/$appKey?protocol=7&client=nova-mobile&version=1.0&flash=false',
    );
    try {
      final WebSocketChannel socket = WebSocketChannel.connect(uri);
      _socket = socket;
      _subscription = socket.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (Object _) => _onClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _onClosed();
    }
  }

  void disconnect() {
    _wanted = false;
    _retry?.cancel();
    _subscription?.cancel();
    _socket?.sink.close();
    _socket = null;
    _socketId = null;
    connected.value = false;
    _presenceCounts.clear();
  }

  /// Listens on [channel] (`private-…`, `presence-…` or public). Returns
  /// a function that stops listening.
  VoidCallback subscribe(String channel, ReverbListener listener) {
    final List<ReverbListener> listeners = _listeners.putIfAbsent(channel, () => <ReverbListener>[]);
    listeners.add(listener);
    if (listeners.length == 1 && _socketId != null) _join(channel);
    return () {
      listeners.remove(listener);
      if (listeners.isEmpty) {
        _listeners.remove(channel);
        _presenceCounts.remove(channel);
        _send('pusher:unsubscribe', <String, String>{'channel': channel});
      }
    };
  }

  void _onMessage(dynamic raw) {
    final Object? decoded = raw is String ? jsonDecode(raw) : null;
    if (decoded is! Map<String, dynamic>) return;
    final String event = decoded.str('event');
    final String channel = decoded.str('channel');
    // Pusher double-encodes `data` as a JSON string.
    final Object? payload = decoded['data'];
    final Object? inner = payload is String && payload.isNotEmpty ? jsonDecode(payload) : payload;
    final Json data = inner is Map<String, dynamic> ? inner : <String, dynamic>{};

    switch (event) {
      case 'pusher:connection_established':
        _socketId = data.str('socket_id');
        _failures = 0;
        connected.value = true;
        for (final String name in _listeners.keys) {
          _join(name);
        }
      case 'pusher:ping':
        _send('pusher:pong', <String, dynamic>{});
      case 'pusher_internal:subscription_succeeded':
        final Json? presence = data.obj('presence');
        if (presence != null) _setPresence(channel, presence.integer('count'));
      case 'pusher_internal:member_added':
        _setPresence(channel, (_presenceCounts[channel] ?? 0) + 1);
      case 'pusher_internal:member_removed':
        _setPresence(channel, ((_presenceCounts[channel] ?? 1) - 1).clamp(0, 1 << 30));
      case 'pusher:error':
        break;
      default:
        // Laravel broadcasts under the event class name, e.g.
        // `App\Events\LiveStateChanged`; listeners get the short name.
        final String name = event.split(r'\').last;
        for (final ReverbListener listener in List<ReverbListener>.of(_listeners[channel] ?? const <ReverbListener>[])) {
          listener(name, data);
        }
    }
  }

  void _setPresence(String channel, int count) {
    _presenceCounts[channel] = count;
    for (final ReverbListener listener in List<ReverbListener>.of(_listeners[channel] ?? const <ReverbListener>[])) {
      listener('presence', <String, dynamic>{'count': count});
    }
  }

  Future<void> _join(String channel) async {
    final String? socketId = _socketId;
    if (socketId == null) return;
    final Map<String, dynamic> subscribe = <String, dynamic>{'channel': channel};
    if (channel.startsWith('private-') || channel.startsWith('presence-')) {
      try {
        final Json auth = await _api.post('/broadcasting/auth', <String, String>{
          'socket_id': socketId,
          'channel_name': channel,
        });
        subscribe['auth'] = auth.str('auth');
        if (auth['channel_data'] != null) subscribe['channel_data'] = auth.str('channel_data');
      } on ApiException {
        return; // Not entitled (any more): the room falls back to polling.
      }
    }
    _send('pusher:subscribe', subscribe);
  }

  void _send(String event, Map<String, dynamic> data) {
    _socket?.sink.add(jsonEncode(<String, Object>{'event': event, 'data': data}));
  }

  void _onClosed() {
    _subscription?.cancel();
    _socket = null;
    _socketId = null;
    connected.value = false;
    if (!_wanted) return;
    _failures++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: (2 * _failures).clamp(2, 30)), connect);
  }
}
