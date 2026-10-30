import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/security/capture_shield.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/features/learning/live_speaker.dart';
import 'package:nova_mobile/features/messages/chat_audio.dart';

import 'fixtures/fixture_app.dart';

/// The iPhone's `nova/capture` event channel (`CaptureGuard`), mocked.
class _CaptureChannel {
  static const EventChannel _channel = EventChannel('nova/capture');

  MockStreamHandlerEventSink? _sink;
  int listens = 0;

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockStreamHandler(
      _channel,
      MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink events) {
        listens++;
        _sink = events;
      }),
    );
  }

  void remove() => _messenger.setMockStreamHandler(_channel, null);

  /// Sends what `CaptureGuard` sends; the caller lets it arrive.
  void send(Map<String, Object?> event) {
    final MockStreamHandlerEventSink? sink = _sink;
    if (sink == null) fail('nova/capture is not listened to');
    sink.success(event);
  }
}

/// Voice notes without audioplayers: records what the player asks.
class _FakeVoiceEngine implements VoiceEngine {
  final List<String> calls = <String>[];
  final StreamController<Duration> _position = StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration = StreamController<Duration>.broadcast();
  final StreamController<void> _completed = StreamController<void>.broadcast();

  @override
  Future<void> play(String source, {required bool local, required double rate}) async => calls.add('play $source');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  Future<void> setRate(double rate) async => calls.add('rate $rate');

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<void> get completed => _completed.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final CaptureMonitor monitor = CaptureMonitor.instance;
  late _CaptureChannel channel;

  /// The monitor started on an iPhone, listening to the mocked channel.
  Future<void> startOnIPhone() async {
    await monitor.debugReset();
    channel = _CaptureChannel()..install();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    monitor.start();
    await pumpEventQueue();
  }

  Future<void> stop() async {
    await monitor.debugReset();
    channel.remove();
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> send(Map<String, Object?> event) async {
    channel.send(event);
    await pumpEventQueue();
  }

  group('CaptureMonitor', () {
    setUp(startOnIPhone);
    tearDown(stop);

    test('follows recording and mirroring, screenshots and the secure layer', () async {
      expect(channel.listens, 1);
      expect(monitor.captured, isFalse);
      expect(monitor.secureLayer, isNull);

      int screenshots = 0;
      final StreamSubscription<void> subscription = monitor.screenshots.listen((_) => screenshots++);
      addTearDown(subscription.cancel);

      await send(<String, Object?>{'secure': true});
      expect(monitor.secureLayer, isTrue);
      await send(<String, Object?>{'captured': true});
      expect(monitor.captured, isTrue);
      await send(<String, Object?>{'screenshot': true});
      expect(screenshots, 1);
      await send(<String, Object?>{'captured': false});
      expect(monitor.captured, isFalse);
    });

    test('records the fallback when the secure layer is unavailable', () async {
      await send(<String, Object?>{'secure': false, 'reason': 'no secure text canvas on iOS 27.0'});
      expect(monitor.secureLayer, isFalse);
    });

    test('Android never listens: FLAG_SECURE covers it natively', () async {
      await monitor.debugReset();
      final _CaptureChannel android = _CaptureChannel()..install();
      addTearDown(android.remove);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      monitor.start();
      await pumpEventQueue();
      expect(android.listens, 0);
      expect(monitor.captured, isFalse);
    });
  });

  group('voice notes during a screen capture', () {
    final ChatVoicePlayer player = ChatVoicePlayer.instance;
    final VoiceEngine Function() realEngine = ChatVoicePlayer.engineFactory;
    late _FakeVoiceEngine engine;

    setUp(() async {
      await startOnIPhone();
      engine = _FakeVoiceEngine();
      ChatVoicePlayer.engineFactory = () => engine;
      player.reset();
    });

    tearDown(() async {
      player.reset();
      ChatVoicePlayer.engineFactory = realEngine;
      await stop();
    });

    Future<void> play(String key) => player.start(key, source: () async => 'https://media.test/$key.m4a', local: false);

    test('a playing note pauses while the screen is recorded and resumes after', () async {
      await play('m1');
      expect(player.stateOf('m1'), VoiceState.playing);

      await send(<String, Object?>{'captured': true});
      expect(engine.calls, <String>['play https://media.test/m1.m4a', 'pause']);
      expect(player.stateOf('m1'), VoiceState.paused);

      await send(<String, Object?>{'captured': false});
      expect(engine.calls.last, 'resume');
      expect(player.stateOf('m1'), VoiceState.playing);
    });

    test('a note the Student paused stays paused when the capture ends', () async {
      await play('m1');
      await player.toggle('m1', source: () async => 'unused', local: false);
      expect(player.stateOf('m1'), VoiceState.paused);

      await send(<String, Object?>{'captured': true});
      await send(<String, Object?>{'captured': false});
      expect(engine.calls, <String>['play https://media.test/m1.m4a', 'pause']);
      expect(player.stateOf('m1'), VoiceState.paused);
    });

    test('a note still loading when the capture starts is paused as soon as it plays', () async {
      final Completer<String> url = Completer<String>();
      final Future<void> starting = player.start('m2', source: () => url.future, local: false);
      await pumpEventQueue();
      expect(player.stateOf('m2'), VoiceState.loading);

      await send(<String, Object?>{'captured': true});
      url.complete('https://media.test/m2.m4a');
      await starting;
      expect(engine.calls, <String>['play https://media.test/m2.m4a', 'pause']);
      expect(player.stateOf('m2'), VoiceState.paused);

      await send(<String, Object?>{'captured': false});
      expect(engine.calls.last, 'resume');
      expect(player.stateOf('m2'), VoiceState.playing);
    });

    test('tapping play during the capture keeps it silent until the capture ends', () async {
      await play('m1');
      await send(<String, Object?>{'captured': true});
      await player.toggle('m1', source: () async => 'unused', local: false);
      expect(engine.calls, <String>['play https://media.test/m1.m4a', 'pause']);
      expect(player.stateOf('m1'), VoiceState.paused);

      await send(<String, Object?>{'captured': false});
      expect(engine.calls.last, 'resume');
    });

    test('a note stopped during the capture does not come back', () async {
      await play('m1');
      await send(<String, Object?>{'captured': true});
      await player.stop();
      await send(<String, Object?>{'captured': false});
      expect(engine.calls, <String>['play https://media.test/m1.m4a', 'pause', 'stop']);
      expect(player.current, isNull);
    });
  });

  group('Live speaking stage during a screen capture', () {
    setUp(startOnIPhone);
    tearDown(stop);

    test('the class is silenced while the screen is recorded, heard again after', () async {
      final List<bool> silenced = <bool>[];
      final LiveSpeaker speaker = LiveSpeaker(onDropped: () {}, silenceRemoteAudio: (bool silent) async => silenced.add(silent));
      expect(silenced, isEmpty);
      expect(speaker.remoteAudioSilenced, isFalse);

      await send(<String, Object?>{'captured': true});
      expect(silenced, <bool>[true]);
      expect(speaker.remoteAudioSilenced, isTrue);

      await send(<String, Object?>{'captured': false});
      expect(silenced, <bool>[true, false]);
      expect(speaker.remoteAudioSilenced, isFalse);

      // Back in the broadcast: the speaker no longer follows the capture.
      debugDefaultTargetPlatformOverride = null;
      await speaker.close();
      await send(<String, Object?>{'captured': true});
      expect(silenced, <bool>[true, false]);
    });

    test('accepted while the screen is already recorded: starts silenced', () async {
      await send(<String, Object?>{'captured': true});
      final List<bool> silenced = <bool>[];
      final LiveSpeaker speaker = LiveSpeaker(onDropped: () {}, silenceRemoteAudio: (bool silent) async => silenced.add(silent));
      expect(silenced, <bool>[true]);
      expect(speaker.remoteAudioSilenced, isTrue);
      debugDefaultTargetPlatformOverride = null;
      await speaker.close();
    });
  });

  testWidgets('the screenshot warning and the recording blur stay as the second layer', (WidgetTester tester) async {
    // Cancelling the channel is a real platform message: outside the fake clock.
    await tester.runAsync(monitor.debugReset);
    final _CaptureChannel shieldChannel = _CaptureChannel()..install();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final AppState app = installFixtureApp();
      await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
          theme: NovaTheme.light,
          builder: (BuildContext context, Widget? child) => CaptureShield(child: child!),
          home: const Scaffold(body: Text('lesson')),
        ),
      ));
      await tester.pump();
      expect(shieldChannel.listens, 1);

      shieldChannel.send(<String, Object?>{'screenshot': true});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Screenshots of NOVA content are not allowed.'), findsOneWidget);

      shieldChannel.send(<String, Object?>{'captured': true});
      await tester.pump();
      expect(find.textContaining('Screen recording or mirroring is on'), findsOneWidget);

      shieldChannel.send(<String, Object?>{'captured': false});
      await tester.pump();
      expect(find.textContaining('Screen recording or mirroring is on'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    } finally {
      await tester.runAsync(monitor.debugReset);
      shieldChannel.remove();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
