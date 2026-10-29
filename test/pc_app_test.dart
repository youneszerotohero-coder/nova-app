import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/nova_api.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/utils/app_lifecycle.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/live_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/playback_models.dart';
import 'package:nova_mobile/features/learning/lesson_screen.dart';
import 'package:nova_mobile/features/player/playback_rules.dart';
import 'package:nova_mobile/features/player/protected_video.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

/// The NOVA PC app (owner decision 2026-10-29): the phone app built for
/// Windows, PlayReady instead of Widevine, the player in a native window
/// behind a transparent hole (`windows/runner/protected_player.cpp`).

/// A Lesson playback as the backend answers the PC app
/// (`DrmPlaybackPolicy::windowsAppClientPolicy`).
Map<String, Object?> _pcAuthorization({bool hardware = true}) => <String, Object?>{
      'mode': 'protected',
      'clear_delivery_available': false,
      'manifests': <String, String>{
        'dash': 'https://cdn.test/v/manifest.mpd?token=abc',
        'hls': 'https://cdn.test/v/master.m3u8?token=abc',
      },
      'drm': <String, Object>{
        'token': 'ey.jwt',
        'license_urls': <String, String>{
          'widevine': 'https://wv.test/AcquireLicense',
          'playready': 'https://pr.test/AcquireLicense',
        },
      },
      'protection': <String, Object?>{
        'mode': 'compatible',
        'software_fallback': true,
        'max_height': null,
        'support_url': null,
        'playready_hardware': hardware,
      },
      'duration_seconds': 1620.4,
      'resume_position_seconds': 312,
      'watch_again': false,
      'progress_session': 'p' * 64,
      'expires_at': '2026-09-24T12:00:00+00:00',
      'watermark': <String, String>{'name': 'Ines Benali', 'phone': '0555123456', 'session': 'K7Q2ZP4M'},
    };

/// Stands in for `protected_player.cpp`: `nova/protected_player` create,
/// each player's commands, and its events sent as JSON text.
class _WindowsPlayers {
  final List<Map<String, Object?>> created = <Map<String, Object?>>[];
  final List<MethodCall> commands = <MethodCall>[];
  MockStreamHandlerEventSink? _sink;
  int _next = 1;

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(const MethodChannel('nova/protected_player'), (MethodCall call) async {
      if (call.method != 'create') return null;
      final int id = _next++;
      created.add(<String, Object?>{
        for (final MapEntry<Object?, Object?> entry in (call.arguments as Map<Object?, Object?>).entries)
          '${entry.key}': entry.value,
      });
      _messenger.setMockMethodCallHandler(MethodChannel('nova/protected_player_$id'), (MethodCall command) async {
        commands.add(command);
        return null;
      });
      _messenger.setMockStreamHandler(
        EventChannel('nova/protected_player_$id/events'),
        MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink sink) {
          _sink = sink;
        }),
      );
      return id;
    });
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(const MethodChannel('nova/protected_player'), null);
    for (int id = 1; id < _next; id++) {
      _messenger.setMockMethodCallHandler(MethodChannel('nova/protected_player_$id'), null);
      _messenger.setMockStreamHandler(EventChannel('nova/protected_player_$id/events'), null);
    }
  }

  void emit(Map<String, Object?> event) => _sink?.success(jsonEncode(event));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PC app platform', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the PC app tells the server it is the PC app', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(NovaApi.clientName, 'app-windows');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(NovaApi.clientName, 'app-android');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(NovaApi.clientName, 'app-ios');
    });

    test('a video pauses when the PC window is minimized, not when another window has the focus', () {
      expect(leftScreen(AppLifecycleState.inactive, platform: TargetPlatform.windows), isFalse);
      expect(leftScreen(AppLifecycleState.hidden, platform: TargetPlatform.windows), isTrue);
      expect(leftScreen(AppLifecycleState.resumed, platform: TargetPlatform.windows), isFalse);
      // Phones are unchanged: any state but resumed.
      expect(leftScreen(AppLifecycleState.inactive, platform: TargetPlatform.android), isTrue);
      expect(leftScreen(AppLifecycleState.resumed, platform: TargetPlatform.iOS), isFalse);
    });

    test('the PlayReady level maps like Android\'s Widevine level', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      const MethodChannel drm = MethodChannel('nova/drm');
      final TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(drm, null));
      for (final (String? level, DrmSupport support) in <(String?, DrmSupport)>[
        ('SL3000', DrmSupport.hardware),
        ('SL2000', DrmSupport.software),
        (null, DrmSupport.none),
      ]) {
        messenger.setMockMethodCallHandler(drm, (MethodCall call) async {
          expect(call.method, 'playreadyLevel');
          return level;
        });
        expect(await detectDrmSupport(), support);
      }
    });

    test('the authorization carries the PlayReady licence and the hardware switch', () {
      final PlaybackAuthorization pc = PlaybackAuthorization.fromJson(_pcAuthorization(hardware: false));
      expect(pc.playreadyLicenseUrl, 'https://pr.test/AcquireLicense');
      expect(pc.playreadyHardware, isFalse);
      expect(pc.strict, isFalse);
      expect(pc.softwareFallback, isTrue);
      expect(pc.maxHeight, isNull);
      // A server before the PC app: hardware is allowed by default.
      final Map<String, Object?> old = _pcAuthorization()..['protection'] = <String, Object?>{'mode': 'strict'};
      expect(PlaybackAuthorization.fromJson(old).playreadyHardware, isTrue);
    });

    test('a Live offers the PC app hardware PlayReady first, software otherwise', () {
      final LivePolicy policy = LivePolicy.fromJson(<String, dynamic>{
        'mode': 'protected',
        'challenge': 'c' * 64,
        'candidates': <Object>[
          <String, Object?>{'drm': 'playready', 'key_system': 'com.microsoft.playready.recommendation.3000', 'robustness': '3000'},
          <String, Object?>{'drm': 'playready', 'key_system': 'com.microsoft.playready.recommendation', 'robustness': '2000'},
        ],
        'policy': <String, Object?>{'mode': 'compatible', 'software_fallback': true},
      });
      expect(policy.playreadyFor(hardware: true)?.robustness, '3000');
      expect(policy.playreadyFor(hardware: false)?.robustness, '2000');
      expect(policy.widevineFor(hardware: true), isNull);

      // The website's strict policy: hardware only.
      final LivePolicy strict = LivePolicy.fromJson(<String, dynamic>{
        'mode': 'protected',
        'candidates': <Object>[
          <String, Object?>{'drm': 'playready', 'key_system': 'com.microsoft.playready.recommendation.3000', 'robustness': '3000'},
        ],
      });
      expect(strict.playreadyFor(hardware: false), isNull);
      expect(strict.playreadyFor(hardware: true)?.keySystem, 'com.microsoft.playready.recommendation.3000');
    });
  });

  group('PC app Lesson player', () {
    setUpAll(loadNovaFonts);
    setUp(ClearDeliveryMemory.reset);

    late _WindowsPlayers players;

    Future<FakeBackend> pumpLesson(WidgetTester tester, {required String level, bool hardware = true}) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.reset);
      const MethodChannel drm = MethodChannel('nova/drm');
      final TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(drm, (MethodCall call) async => level);
      addTearDown(() => messenger.setMockMethodCallHandler(drm, null));
      players = _WindowsPlayers()..install();
      addTearDown(players.uninstall);

      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _pcAuthorization(hardware: hardware)}),
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      app.setLang(NovaLang.en);
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned);
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: NovaTheme.light,
            home: LessonScreen(course: ValueNotifier<Course>(course), index: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    /// Runs [body] as the PC app; the override is reset inside the test, as
    /// the framework checks it before tear-downs.
    Future<void> asPcApp(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('software PlayReady plays the protected DASH stream, never the clear copy', (tester) => asPcApp(() async {
      final FakeBackend backend = await pumpLesson(tester, level: 'SL2000');

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(backend.requests.where((FakeRequest r) => r.path.endsWith('/playback')).single.data, isNull);
      final Map<String, Object?> created = players.created.single;
      expect(created['clear'], isFalse);
      expect(created['manifest'], 'https://cdn.test/v/manifest.mpd?token=abc');
      expect(created['license'], 'https://pr.test/AcquireLicense');
      expect(created['token'], 'ey.jwt');
      expect(created['keySystem'], playReadyKeySystem);
      expect(created['robustness'], '2000');
      expect(created['startMs'], 312000);
      expect(created['maxHeight'], isNull);

      // The hole tells the native window where it is, in physical pixels.
      final MethodCall place = players.commands.firstWhere((MethodCall c) => c.method == 'setRect');
      final Map<Object?, Object?> rect = place.arguments as Map<Object?, Object?>;
      expect(rect['visible'], isTrue);
      expect((rect['width']! as num) > 0 && (rect['height']! as num) > 0, isTrue);

      // The page's events arrive as JSON text.
      players.emit(<String, Object?>{'event': 'tracks', 'heights': <int>[1080, 720, 480]});
      players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
      players.emit(<String, Object?>{'event': 'firstFrame'});
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('hardware protection'), findsNothing);
      await leave(tester);
    }));

    testWidgets('hardware PlayReady SL3000 is used when the PC has it and the server allows it', (tester) => asPcApp(() async {
      await pumpLesson(tester, level: 'SL3000');
      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(players.created.single['keySystem'], playReadyHardwareKeySystem);
      expect(players.created.single['robustness'], '3000');
      await leave(tester);
    }));

    testWidgets('the server switch keeps an SL3000 PC on software PlayReady', (tester) => asPcApp(() async {
      await pumpLesson(tester, level: 'SL3000', hardware: false);
      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(players.created.single['keySystem'], playReadyKeySystem);
      expect(players.created.single['robustness'], '2000');
      await leave(tester);
    }));
  });
}
