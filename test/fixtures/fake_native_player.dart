import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the native players (Android `ProtectedPlayerView`, iPhone
/// `ClearPlayerView`): records each platform view's creation params and
/// lets a test push the native events (`error`, `tracks`…) the Dart
/// controller listens to.
class FakeNativePlayers {
  /// Creation params of every player view, in creation order.
  final List<Map<String, Object?>> created = <Map<String, Object?>>[];

  /// Method calls sent to each view (`play`, `setQuality`…), by view id.
  final Map<int, List<MethodCall>> commands = <int, List<MethodCall>>{};
  final Map<int, MockStreamHandlerEventSink> _sinks = <int, MockStreamHandlerEventSink>{};
  final List<int> _ids = <int>[];

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(SystemChannels.platform_views, (MethodCall call) async {
      if (call.method != 'create') return null;
      final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
      final int id = args['id']! as int;
      final Object? encoded = args['params'];
      final Object? params = encoded is Uint8List
          ? const StandardMessageCodec().decodeMessage(ByteData.sublistView(encoded))
          : null;
      created.add(<String, Object?>{
        for (final MapEntry<Object?, Object?> entry in (params as Map<Object?, Object?>? ?? const <Object?, Object?>{}).entries)
          '${entry.key}': entry.value,
      });
      _ids.add(id);
      _messenger.setMockStreamHandler(
        EventChannel('nova/protected_player_$id/events'),
        MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink sink) {
          _sinks[id] = sink;
        }),
      );
      _messenger.setMockMethodCallHandler(MethodChannel('nova/protected_player_$id'), (MethodCall command) async {
        commands.putIfAbsent(id, () => <MethodCall>[]).add(command);
        return null;
      });
      return null;
    });
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final int id in _ids) {
      _messenger.setMockStreamHandler(EventChannel('nova/protected_player_$id/events'), null);
      _messenger.setMockMethodCallHandler(MethodChannel('nova/protected_player_$id'), null);
    }
  }

  /// Sends a native event from the most recently created player.
  void emit(Map<String, Object?> event) => _sinks[_ids.last]?.success(event);

  int get lastId => _ids.last;
}
