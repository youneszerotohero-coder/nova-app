import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/utils/screen_awake.dart';
import 'package:nova_mobile/core/widgets/hero_style.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/playback_models.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/learning/lesson_pdf_saver.dart';
import 'package:nova_mobile/features/learning/lesson_pdf_screen.dart';
import 'package:nova_mobile/features/learning/lesson_screen.dart';
import 'package:nova_mobile/features/learning/quiz_runner.dart';
import 'package:nova_mobile/features/player/lesson_player.dart';
import 'package:nova_mobile/features/player/playback_rules.dart';
import 'package:nova_mobile/features/shell/student_top_bar.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fake_native_player.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

/// A playback authorization in the backend's exact shape
/// (`PlaybackService::authorize`); [clearDelivery] is mode B (D-070),
/// [fairplay] the server's FairPlay URLs (D-088).
Map<String, Object?> _authorization({
  String mode = 'strict',
  bool fallback = false,
  bool clearDelivery = false,
  bool fairplay = false,
}) =>
    <String, Object?>{
      'mode': 'protected',
      'clear_delivery_available': clearDelivery,
      'manifests': <String, String>{
        'dash': 'https://cdn.test/v/manifest.mpd?token=abc',
        'hls': 'https://cdn.test/v/master.m3u8?token=abc',
      },
      'drm': <String, Object>{
        'token': 'ey.jwt',
        'license_urls': <String, String>{
          'widevine': 'https://drm.test/AcquireLicense',
          'playready': 'https://drm.test/AcquireLicense',
          if (fairplay) 'fairplay': 'https://fps.test/AcquireLicense',
        },
        if (fairplay) 'fairplay_certificate_url': 'https://nova.test/drm/fairplay.cer',
      },
      'protection': <String, Object?>{
        'mode': mode,
        'software_fallback': fallback,
        'max_height': fallback ? 480 : null,
        'support_url': null,
      },
      'duration_seconds': 1620.4,
      'resume_position_seconds': 312,
      'watch_again': false,
      'progress_session': 'p' * 64,
      'expires_at': '2026-09-24T12:00:00+00:00',
      'watermark': <String, String>{'name': 'Ines Benali', 'phone': '0555123456', 'session': 'K7Q2ZP4M'},
    };

/// The clear copy of a Lesson (`PlaybackService`, D-070).
Map<String, Object?> _clearAuthorization() => <String, Object?>{
      'mode': 'clear',
      'manifest_url': 'https://cdn.test/v/hls-clear/master.m3u8?token=abc',
      'mime_type': 'application/x-mpegurl',
      'support_url': null,
      'duration_seconds': 1620.4,
      'resume_position_seconds': 312,
      'watch_again': false,
      'progress_session': 'p' * 64,
      'expires_at': '2026-09-24T12:00:00+00:00',
      'watermark': <String, String>{'name': 'Ines Benali', 'phone': '0555123456', 'session': 'K7Q2ZP4M'},
    };

/// Mode A refuses the clear copy.
const FakeResponse _clearRefused = FakeResponse(403, <String, Object>{
  'error': <String, String>{
    'code': 'VIDEO_CLEAR_DELIVERY_DISABLED',
    'message': 'Clear delivery is disabled.',
  },
});

/// Scrolls the page until [finder] can be tapped, then lets the layout settle.
Future<void> _reveal(WidgetTester tester, Finder finder, double delta) async {
  await tester.scrollUntilVisible(finder, delta, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  group('Playback rules (web parity)', () {
    test('progress is saved after 15 s of movement either way', () {
      final ProgressReporter reporter = ProgressReporter(initialSeconds: 100);
      expect(reporter.due(114), isFalse);
      expect(reporter.due(115), isTrue);
      expect(reporter.due(85), isTrue);
      reporter.saved(115);
      expect(reporter.due(120), isFalse);
    });

    test('resume never lands in the last few seconds', () {
      expect(safeResumeSeconds(312, 1620), 312);
      expect(safeResumeSeconds(1616, 1620), 0); // inside the 5 s tail
      expect(safeResumeSeconds(28, 30), 0); // 3 s minimum tail
      expect(safeResumeSeconds(0, 1620), 0);
    });

    test('manifest duration must match the authorized one within 2 s', () {
      expect(durationMatches(1620.4, 1621.9), isTrue);
      expect(durationMatches(1620.4, 1600), isFalse);
      expect(durationMatches(1620.4, 0), isTrue); // not known yet
    });

    test('watermark stays inside the web ranges and rotates faster on software DRM', () {
      final WatermarkPlacer placer = WatermarkPlacer(random: Random(7));
      for (int i = 0; i < 200; i++) {
        final WatermarkSpot spot = placer.next();
        expect(spot.top, inInclusiveRange(0.12, 0.67));
        expect(spot.inset, inInclusiveRange(0.04, 0.14));
      }
      expect(placer.interval(softwareFallback: false).inSeconds, inInclusiveRange(10, 18));
      expect(placer.interval(softwareFallback: true).inSeconds, inInclusiveRange(6, 10));
      expect(placer.rotationTag, hasLength(2));
    });

    test('the authorization parses the backend shape', () {
      final PlaybackAuthorization auth = PlaybackAuthorization.fromJson(_authorization());
      expect(auth.strict, isTrue);
      expect(auth.widevineLicenseUrl, 'https://drm.test/AcquireLicense');
      expect(auth.drmToken, 'ey.jwt');
      expect(auth.maxHeight, isNull);
      expect(auth.watermarkSession, 'K7Q2ZP4M');
      expect(auth.durationSeconds, closeTo(1620.4, 0.01));
      expect(auth.clear, isFalse);
      expect(auth.clearDeliveryAvailable, isFalse);

      final PlaybackAuthorization clear = PlaybackAuthorization.fromJson(_clearAuthorization());
      expect(clear.clear, isTrue);
      expect(clear.manifestUrl, endsWith('master.m3u8?token=abc'));
      expect(clear.progressSession, hasLength(64));
      expect(clear.resumeSeconds, 312);
    });

    test('D-077: every protected failure falls back in mode B, except refused authorizations', () {
      expect(clearFallbackReason('capability', capability: true), 'no_drm');
      expect(clearFallbackReason('ios_blocked'), 'no_drm');
      expect(clearFallbackReason('license'), 'drm_error');
      expect(clearFallbackReason('output'), 'drm_error');
      expect(clearFallbackReason('decode'), 'drm_error');
      // A protected copy missing on the CDN (404) or unreachable.
      expect(clearFallbackReason('delivery'), 'media_unavailable');
      expect(clearFallbackReason('timeout'), 'media_unavailable');
      for (final String refused in <String>['access', 'session_expired', 'processing', 'clear_unavailable', 'rate']) {
        expect(clearFallbackReason(refused), isNull);
      }
      expect(isClearWording('drm_with_clear_fallback'), isTrue);
      expect(isClearWording('clear'), isTrue);
      expect(isClearWording('drm_only'), isFalse);
    });

    test('a picture that never starts although media is buffered counts as stuck', () {
      bool stuck(int seconds, {bool frame = false, int position = 0, int buffered = 5}) => ProtectedStartWatch.stuck(
            elapsed: Duration(seconds: seconds),
            firstFrame: frame,
            start: Duration.zero,
            position: Duration(seconds: position),
            buffered: Duration(seconds: buffered),
          );
      expect(stuck(9), isFalse); // too early
      expect(stuck(12), isTrue);
      expect(stuck(12, frame: true), isFalse);
      expect(stuck(12, position: 3), isFalse); // it plays
      expect(stuck(12, buffered: 1), isFalse); // network, not DRM
      expect(stuck(50), isFalse); // gave up
    });

    test('clear failures never speak of protection', () {
      expect(playerFailureKey('decode', clear: false), 'player.err.decode');
      expect(playerFailureKey('decode', clear: true), 'player.clearErr.decode');
      expect(playerFailureKey('license', clear: true), 'player.clearErr.delivery');
      expect(playerFailureKey('clear_unavailable', clear: true), 'player.err.clear_unavailable');
    });

    test('owner decision 2026-10-30: only network and timeout cuts of the media resume by themselves', () {
      bool android(String category, int code, {String kind = 'other'}) =>
          VideoAutoResume.qualifies(category: category, kind: kind, code: code, platform: TargetPlatform.android);
      // Media3: connection failed, timeout, bad HTTP status, unspecified I/O.
      expect(android('delivery', 2001), isTrue);
      expect(android('timeout', 2002), isTrue);
      expect(android('delivery', 2004), isTrue);
      expect(android('delivery', 2000), isTrue);
      // Never DRM, licence, decoder, a behind-live or unknown failure.
      expect(android('license', 6004, kind: 'drm'), isFalse);
      expect(android('expired', 6008, kind: 'drm'), isFalse);
      expect(android('decode', 4003, kind: 'decoder'), isFalse);
      expect(android('capability', 4001, kind: 'decoder'), isFalse);
      expect(android('output', 6006, kind: 'drm'), isFalse);
      expect(android('delivery', 1002), isFalse);
      expect(android('delivery', 2003), isFalse);
      expect(android('delivery', 0), isFalse);
      expect(VideoAutoResume.qualifies(category: null, kind: null, code: 2001, platform: TargetPlatform.android), isFalse);
      // iPhone: NSURLError network codes; a FairPlay licence that timed out stays a licence failure.
      bool ios(String category, int code, {String kind = 'other'}) =>
          VideoAutoResume.qualifies(category: category, kind: kind, code: code, platform: TargetPlatform.iOS);
      expect(ios('timeout', -1001), isTrue);
      expect(ios('delivery', -1009), isTrue);
      expect(ios('delivery', -1005), isTrue);
      expect(ios('timeout', -1001, kind: 'drm'), isFalse);
      expect(ios('delivery', -11800), isFalse);
      expect(ios('decode', -11821, kind: 'decoder'), isFalse);
      // PC app (Shaka): bad HTTP status, HTTP error, timeout.
      bool windows(String category, int code, {String kind = 'other'}) =>
          VideoAutoResume.qualifies(category: category, kind: kind, code: code, platform: TargetPlatform.windows);
      expect(windows('delivery', 1002), isTrue);
      expect(windows('timeout', 1003), isTrue);
      expect(windows('license', 6007, kind: 'drm'), isFalse);
    });

    test('owner decision 2026-10-30: three automatic resumes after 2, 5 and 10 s, then none', () {
      expect(VideoAutoResume.delay(0), const Duration(seconds: 2));
      expect(VideoAutoResume.delay(1), const Duration(seconds: 5));
      expect(VideoAutoResume.delay(2), const Duration(seconds: 10));
      expect(VideoAutoResume.delay(3), isNull);
      expect(VideoAutoResume.delay(-1), isNull);
    });

    test('D-165: paused videos say for how long, also on the clear copy', () {
      expect(playbackPausedCategory(<String, dynamic>{'until': '2026-10-29T23:00:00+00:00', 'reason': 'day'}), 'paused_day');
      expect(playbackPausedCategory(<String, dynamic>{'reason': 'hour'}), 'paused_hour');
      expect(playbackPausedCategory(null), 'paused_hour');
      expect(playerFailureKey('paused_day', clear: true), 'player.err.paused_day');
      expect(playerFailureKey('paused_hour', clear: false), 'player.err.paused_hour');
    });
  });

  group('Lesson player states', () {
    setUpAll(loadNovaFonts);
    setUp(ClearDeliveryMemory.reset);

    late FakeBackend backend;
    late FakeNativePlayers players;
    const MethodChannel drm = MethodChannel('nova/drm');

    /// The Lesson page (D-132) of the fixture's owned Unit: its first Lesson
    /// (`/lessons/0/…`) unless [index] picks another one.
    Future<void> pumpLesson(WidgetTester tester, {String? widevine, int index = 0}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, (MethodCall call) async => widevine);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, null));
      players = FakeNativePlayers()..install();
      addTearDown(players.uninstall);

      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      app.setLang(NovaLang.en);
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned);
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: NovaTheme.light,
            home: LessonScreen(course: ValueNotifier<Course>(course), index: index),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a software-only device is refused under the strict policy', (tester) async {
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
      });
      await pumpLesson(tester, widevine: 'L3');

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.textContaining('hardware protection'), findsOneWidget);
      expect(
        backend.requests.where((FakeRequest r) => r.path.endsWith('/playback')),
        hasLength(1),
      );
    });

    testWidgets('a lesson still being prepared says so and offers a retry', (tester) async {
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': const FakeResponse(409, <String, Object>{
          'error': <String, String>{
            'code': 'PROTECTED_VIDEO_NOT_READY',
            'message': 'Protected playback is not available for this Lesson.',
          },
        }),
      });
      await pumpLesson(tester, widevine: 'L1');

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.textContaining('still being prepared'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('D-134: a finished Lesson resumes at the last second seen, saved only once the picture is there', (tester) async {
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{..._authorization(), 'resume_position_seconds': 900, 'watch_again': true},
        }),
        'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}}),
      });
      await pumpLesson(tester, widevine: 'L1');
      List<int> saved() => <int>[
            for (final FakeRequest r in backend.requests.where((FakeRequest r) => r.path == '/lessons/0/progress'))
              (r.data! as Map<String, dynamic>)['position_seconds'] as int,
          ];

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // A Lesson watched before continues where the Student stopped.
      expect(players.created.single['startMs'], 900000);

      // Ready and paused before the picture reports the resume second:
      // saving 0 now would erase the Student's place.
      players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
      await tester.pump(const Duration(milliseconds: 50));
      expect(saved(), isEmpty);

      players.emit(<String, Object?>{'event': 'position', 'position': 905000, 'duration': 1620400, 'buffered': 930000, 'liveOffset': -1});
      await tester.pump(const Duration(milliseconds: 50));
      expect(saved(), <int>[905]);

      // Jumps forward and back are saved at once, wherever they land.
      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byIcon(Icons.replay_10_rounded));
      await tester.pump(const Duration(milliseconds: 50));
      expect(saved(), <int>[905, 915, 895]);
      expect(backend.requests.where((FakeRequest r) => r.path == '/lessons/0/progress').last.data,
          containsPair('playback_session', 'p' * 64));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('D-134: moving to another Lesson saves the second left under that Lesson and its session', (tester) async {
      const Map<String, Object?> row = <String, Object?>{
        'lesson_id': 1023, 'resume_position_seconds': 340, 'max_position_seconds': 340,
        'video_progress_percent': '20.98', 'completed': false,
      };
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/1023/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
        'PUT /lessons/1023/progress': const FakeResponse(200, <String, Object?>{'data': row}),
      });
      await pumpLesson(tester, widevine: 'L1', index: 2);

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(players.created.single['startMs'], 312000);
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
      players.emit(<String, Object?>{'event': 'position', 'position': 330000, 'duration': 1620400, 'buffered': 360000, 'liveOffset': -1});
      await tester.pump(const Duration(milliseconds: 50));
      // 15 s are not reached since the heartbeat: only leaving saves 345 s.
      players.emit(<String, Object?>{'event': 'position', 'position': 345000, 'duration': 1620400, 'buffered': 370000, 'liveOffset': -1});
      await tester.pump(const Duration(milliseconds: 50));

      await _reveal(tester, find.text('Next lesson'), 300);
      await tester.tap(find.text('Next lesson'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The heartbeat at 330 s, then the second left (345 s), both under
      // Lesson 1023 and its own session; nothing reaches the next Lesson.
      final List<FakeRequest> saves = backend.requests.where((FakeRequest r) => r.path.endsWith('/progress')).toList();
      expect(saves.map((FakeRequest r) => r.path), <String>['/lessons/1023/progress', '/lessons/1023/progress']);
      expect(saves.map((FakeRequest r) => (r.data! as Map<String, dynamic>)['position_seconds']), <int>[330, 345]);
      expect(find.text('Lesson 4 of 5'), findsOneWidget);
      expect(find.text('Check & play'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('D-137: the controls read left to right in Arabic and the bar follows the finger, seeking on release', (tester) async {
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
        'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}}),
      });
      await pumpLesson(tester, widevine: 'L1');
      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      AppScope.of(tester.element(find.byType(LessonScreen))).setLang(NovaLang.ar);
      await tester.pump(const Duration(milliseconds: 100));
      players.emit(<String, Object?>{'event': 'position', 'position': 312000, 'duration': 1620400, 'buffered': 330000, 'liveOffset': -1});
      await tester.pump(const Duration(milliseconds: 50));

      // Media controls are never mirrored: the clock and the bar run left to right.
      final Finder slider = find.byType(Slider);
      expect(Directionality.of(tester.element(slider)), TextDirection.ltr);
      expect(find.text('5:12 / 27:00'), findsOneWidget);

      // The thumb follows the finger; the picture seeks once, on release.
      final Rect bar = tester.getRect(slider);
      final TestGesture drag = await tester.startGesture(Offset(bar.left + bar.width * 0.2, bar.center.dy));
      await drag.moveTo(Offset(bar.left + bar.width * 0.5, bar.center.dy));
      await tester.pump();
      expect(tester.widget<Slider>(slider).value, greaterThan(312000));
      expect((players.commands[players.lastId] ?? <MethodCall>[]).where((MethodCall c) => c.method == 'seekTo'), isEmpty);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect((players.commands[players.lastId] ?? <MethodCall>[]).where((MethodCall c) => c.method == 'seekTo'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('mode A: iPhone plays the FairPlay HLS stream (D-118)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        backend = FakeBackend(<String, FakeResponse>{
          'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization(fairplay: true)}),
        });
        await pumpLesson(tester);

        await tester.tap(find.text('Play'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // The protected stream is asked for, never the clear copy.
        expect(backend.requests.where((FakeRequest r) => r.path.endsWith('/playback')).single.data, isNull);
        final Map<String, Object?> created = players.created.single;
        expect(created['clear'], isFalse);
        expect(created['manifest'], 'https://cdn.test/v/master.m3u8?token=abc');
        expect(created['license'], 'https://fps.test/AcquireLicense');
        expect(created['certificate'], 'https://nova.test/drm/fairplay.cer');
        expect(created['token'], 'ey.jwt');
        expect(created['startMs'], 312000);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('fullscreen keeps the one native player: no second sound on iPhone', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        backend = FakeBackend(<String, FakeResponse>{
          'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization(fairplay: true)}),
        });
        await pumpLesson(tester);
        await tester.tap(find.text('Play'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(players.created, hasLength(1));

        await tester.tap(find.byIcon(Icons.fullscreen_rounded));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(players.created, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('mode A: iPhone stays blocked while the server offers no FairPlay', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        backend = FakeBackend(<String, FakeResponse>{
          'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
        });
        await pumpLesson(tester);

        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();

        expect(find.textContaining('can’t play on iPhone yet'), findsOneWidget);
        expect(players.created, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('modes B/C: iPhone plays the clear copy under the watermark (D-070)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        backend = FakeBackend(<String, FakeResponse>{
          'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _clearAuthorization()}),
        });
        await pumpLesson(tester);

        await tester.tap(find.text('Play'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(players.created.single['clear'], isTrue);
        expect(players.created.single['manifest'], 'https://cdn.test/v/hls-clear/master.m3u8?token=abc');
        expect(players.created.single['startMs'], 312000);
        expect(find.text('Personal copy · identity watermark'), findsOneWidget);
        expect(find.textContaining('Ines Benali'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('mode B: an L3 phone falls back to the clear copy and remembers it', (tester) async {
      backend = FakeBackend(
        <String, FakeResponse>{},
        sequences: <String, List<FakeResponse>>{
          'POST /lessons/0/playback': <FakeResponse>[
            FakeResponse(200, <String, Object?>{'data': _authorization(clearDelivery: true)}),
            FakeResponse(200, <String, Object?>{'data': _clearAuthorization()}),
          ],
        },
      );
      await pumpLesson(tester, widevine: 'L3');

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final List<FakeRequest> calls =
          backend.requests.where((FakeRequest r) => r.path.endsWith('/playback')).toList();
      expect(calls.map((FakeRequest r) => r.data), <Object?>[
        null,
        <String, String>{'delivery': 'clear'},
      ]);
      expect(players.created.single['clear'], isTrue);
      expect(ClearDeliveryMemory.video, 'no_drm');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a clear copy still being prepared says so and retries by itself', (tester) async {
      ClearDeliveryMemory.video = 'no_drm';
      backend = FakeBackend(
        <String, FakeResponse>{},
        sequences: <String, List<FakeResponse>>{
          'POST /lessons/0/playback': <FakeResponse>[
            const FakeResponse(409, <String, Object>{
              'error': <String, String>{'code': 'VIDEO_CLEAR_COPY_UNAVAILABLE', 'message': 'Not ready.'},
            }),
            FakeResponse(200, <String, Object?>{'data': _clearAuthorization()}),
          ],
        },
      );
      await pumpLesson(tester, widevine: 'L1');

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.textContaining('being prepared for your phone'), findsOneWidget);

      await tester.pump(const Duration(seconds: 20));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.requests.where((FakeRequest r) => r.path.endsWith('/playback')), hasLength(2));
      expect(players.created.single['clear'], isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('mode B: a DRM failure while playing continues on the clear copy', (tester) async {
      backend = FakeBackend(
        <String, FakeResponse>{'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}})},
        sequences: <String, List<FakeResponse>>{
          'POST /lessons/0/playback': <FakeResponse>[
            FakeResponse(200, <String, Object?>{'data': _authorization(clearDelivery: true)}),
            FakeResponse(200, <String, Object?>{'data': _clearAuthorization()}),
          ],
        },
      );
      await pumpLesson(tester, widevine: 'L1');

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(players.created.single['clear'], isFalse);

      players.emit(<String, Object?>{'event': 'position', 'position': 400000, 'duration': 1620400, 'buffered': 410000, 'liveOffset': -1});
      players.emit(<String, Object?>{'event': 'error', 'category': 'license', 'kind': 'drm', 'code': 6004});
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(players.created, hasLength(2));
      expect(players.created.last['clear'], isTrue);
      // The Student continues where the protected picture stopped.
      expect(players.created.last['startMs'], 400000);
      expect(ClearDeliveryMemory.video, 'drm_error');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('D-077 mode B: a protected copy missing on the CDN plays the clear copy, not an error', (tester) async {
      backend = FakeBackend(
        <String, FakeResponse>{
          'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}}),
          'POST /playback-diagnostics': const FakeResponse(204),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lessons/0/playback': <FakeResponse>[
            FakeResponse(200, <String, Object?>{'data': _authorization(clearDelivery: true)}),
            FakeResponse(200, <String, Object?>{'data': _clearAuthorization()}),
          ],
        },
      );
      await pumpLesson(tester, widevine: 'L1');

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // The protected DASH manifest answers 404 (Media3 bad HTTP status).
      players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2004});
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(players.created.last['clear'], isTrue);
      expect(find.textContaining('Protected'), findsNothing);
      // A missing protected copy concerns this video, not the device.
      expect(ClearDeliveryMemory.video, isNull);
      final FakeRequest trace = backend.requests.lastWhere((FakeRequest r) => r.path == '/playback-diagnostics');
      expect(trace.data, containsPair('reason', 'media_unavailable'));
      expect(trace.data, containsPair('content', 'lesson'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a remembered fallback the Admin switched off goes back to DRM', (tester) async {
      ClearDeliveryMemory.video = 'drm_error';
      backend = FakeBackend(
        <String, FakeResponse>{},
        sequences: <String, List<FakeResponse>>{
          'POST /lessons/0/playback': <FakeResponse>[
            _clearRefused,
            FakeResponse(200, <String, Object?>{'data': _authorization()}),
          ],
        },
      );
      await pumpLesson(tester, widevine: 'L1');

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        backend.requests.where((FakeRequest r) => r.path.endsWith('/playback')).map((FakeRequest r) => r.data),
        <Object?>[<String, String>{'delivery': 'clear'}, null],
      );
      expect(players.created.single['clear'], isFalse);
      expect(ClearDeliveryMemory.video, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Automatic resume after a network cut (owner decision 2026-10-30)', () {
    setUpAll(loadNovaFonts);
    setUp(ClearDeliveryMemory.reset);

    late FakeBackend backend;
    late FakeNativePlayers players;
    const MethodChannel drm = MethodChannel('nova/drm');

    Future<void> pumpLesson(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, (MethodCall call) async => 'L1');
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, null));
      players = FakeNativePlayers()..install();
      addTearDown(players.uninstall);
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
    }

    Future<void> frames(WidgetTester tester) async {
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void position(int ms) => players.emit(<String, Object?>{
          'event': 'position', 'position': ms, 'duration': 1620400, 'buffered': ms + 20000, 'liveOffset': -1,
        });

    List<Map<String, dynamic>> traces(String event) => <Map<String, dynamic>>[
          for (final FakeRequest r in backend.requests.where((FakeRequest r) => r.path == '/playback-diagnostics'))
            if ((r.data! as Map<String, dynamic>)['event'] == event) r.data! as Map<String, dynamic>,
        ];

    int authorizations() => backend.requests.where((FakeRequest r) => r.path == '/lessons/0/playback').length;

    testWidgets('a cut resumes at the same second with a new playback session before any progress is saved', (tester) async {
      backend = FakeBackend(
        <String, FakeResponse>{
          'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}}),
          'POST /playback-diagnostics': const FakeResponse(204),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lessons/0/playback': <FakeResponse>[
            FakeResponse(200, <String, Object?>{'data': _authorization()}),
            FakeResponse(200, <String, Object?>{'data': <String, Object?>{..._authorization(), 'progress_session': 'q' * 64}}),
          ],
        },
      );
      await pumpLesson(tester);

      await tester.tap(find.text('Play'));
      await frames(tester);
      expect(players.created.single['startMs'], 312000);
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      position(400000);
      await frames(tester);

      // Media3 2001: the network dropped while the Student watched.
      players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2001});
      await frames(tester);
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(authorizations(), 1);
      final Map<String, dynamic> scheduled = traces('auto_resume').single;
      expect(scheduled, containsPair('reason', 'scheduled'));
      expect(scheduled, containsPair('code', 2001));
      expect(scheduled, containsPair('attempt', 1));
      expect(scheduled, containsPair('waited_ms', 2000));

      await tester.pump(const Duration(seconds: 2));
      await frames(tester);
      // A fresh authorization, and the picture continues at the second it stopped.
      expect(authorizations(), 2);
      expect(players.created, hasLength(2));
      expect(players.created.last['startMs'], 400000);
      expect(find.text('Reconnecting…'), findsOneWidget);

      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      position(401000);
      await frames(tester);
      expect(find.text('Reconnecting…'), findsNothing);
      expect(traces('auto_resume').last, containsPair('reason', 'resumed'));
      position(416000);
      await frames(tester);

      // Progress saved after the cut belongs to the new playback session,
      // requested only after the new authorization.
      final int secondAuthorization = backend.requests.lastIndexWhere((FakeRequest r) => r.path == '/lessons/0/playback');
      final List<FakeRequest> saves = backend.requests.where((FakeRequest r) => r.path == '/lessons/0/progress').toList();
      expect(saves.map((FakeRequest r) => (r.data! as Map<String, dynamic>)['position_seconds']), <int>[400, 416]);
      expect(saves.first.data, containsPair('playback_session', 'p' * 64));
      expect(saves.last.data, containsPair('playback_session', 'q' * 64));
      expect(backend.requests.indexOf(saves.last), greaterThan(secondAuthorization));
      expect(traces('error_shown'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('after three failed automatic resumes the usual error screen shows; a retry starts afresh', (tester) async {
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
        'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}}),
        'POST /playback-diagnostics': const FakeResponse(204),
      });
      await pumpLesson(tester);

      await tester.tap(find.text('Play'));
      await frames(tester);
      for (final int wait in <int>[2, 5, 10]) {
        final int before = authorizations();
        players.emit(<String, Object?>{'event': 'error', 'category': 'timeout', 'kind': 'other', 'code': 2002});
        await frames(tester);
        expect(find.text('Reconnecting…'), findsOneWidget);
        await tester.pump(Duration(seconds: wait) - const Duration(milliseconds: 300));
        expect(authorizations(), before);
        await tester.pump(const Duration(milliseconds: 300));
        await frames(tester);
        expect(authorizations(), before + 1);
      }
      expect(authorizations(), 4);
      expect(players.created, hasLength(4));
      expect(players.created.last['startMs'], 312000);

      players.emit(<String, Object?>{'event': 'error', 'category': 'timeout', 'kind': 'other', 'code': 2002});
      await frames(tester);
      expect(find.text('Reconnecting…'), findsNothing);
      expect(find.text('The connection is too slow. Check your internet and retry.'), findsOneWidget);
      expect(traces('auto_resume').map((Map<String, dynamic> t) => '${t['reason']} ${t['attempt']}'),
          <String>['scheduled 1', 'scheduled 2', 'scheduled 3', 'exhausted 3']);
      expect(traces('error_shown').single, containsPair('category', 'timeout'));

      // Nothing more by itself; the Student's retry gets three fresh attempts.
      await tester.pump(const Duration(seconds: 30));
      expect(authorizations(), 4);
      await tester.tap(find.text('Try again'));
      await frames(tester);
      expect(authorizations(), 5);
      players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2001});
      await frames(tester);
      expect(find.text('Reconnecting…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a licence or decoder failure shows its error at once, as before', (tester) async {
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
        'POST /playback-diagnostics': const FakeResponse(204),
      });
      await pumpLesson(tester);

      await tester.tap(find.text('Play'));
      await frames(tester);
      players.emit(<String, Object?>{'event': 'error', 'category': 'decode', 'kind': 'decoder', 'code': 4003});
      await frames(tester);
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Reconnecting…'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(authorizations(), 1);
      expect(traces('auto_resume'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('no network at the new authorization counts as the next attempt', (tester) async {
      backend = FakeBackend(
        <String, FakeResponse>{
          'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}}),
          'POST /playback-diagnostics': const FakeResponse(204),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lessons/0/playback': <FakeResponse>[
            FakeResponse(200, <String, Object?>{'data': _authorization()}),
            const FakeResponse(0),
            FakeResponse(200, <String, Object?>{'data': _authorization()}),
          ],
        },
      );
      await pumpLesson(tester);

      await tester.tap(find.text('Play'));
      await frames(tester);
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      position(500000);
      await frames(tester);
      players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2001});
      await frames(tester);
      await tester.pump(const Duration(seconds: 2));
      await frames(tester);
      expect(authorizations(), 2);
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(players.created, hasLength(1));

      await tester.pump(const Duration(seconds: 5));
      await frames(tester);
      expect(authorizations(), 3);
      expect(players.created, hasLength(2));
      expect(players.created.last['startMs'], 500000);
      expect(traces('auto_resume').map((Map<String, dynamic> t) => '${t['reason']} ${t['phase']} ${t['attempt']}'),
          <String>['scheduled streaming 1', 'scheduled authorizing 2']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Lesson from a Live (D-132)', () {
    setUpAll(loadNovaFonts);
    setUp(ClearDeliveryMemory.reset);

    testWidgets('a past Live plays as a Lesson: its own /lessons playback, neutral until mode A is known', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      const MethodChannel drm = MethodChannel('nova/drm');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, (MethodCall call) async => 'L1');
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, null));
      final FakeNativePlayers players = FakeNativePlayers()..install();
      addTearDown(players.uninstall);
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/1025/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned);

      Future<void> open() async {
        await tester.pumpWidget(AppScope(
          state: app,
          child: MaterialApp(
            theme: NovaTheme.light,
            home: LessonScreen(course: ValueNotifier<Course>(course), index: 4),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text('Live — energy exercises, BAC style'), findsOneWidget);
      expect(find.text('Recorded during the live class'), findsOneWidget);
      expect(find.text('Lesson 5 of 5'), findsOneWidget);
      // Mode unknown: nothing speaks of protection (D-077).
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Protected lesson'), findsNothing);

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // The Lesson's own authorization, never a Live replay endpoint.
      expect(backend.requests.map((FakeRequest r) => r.path), contains('/lessons/1025/playback'));
      expect(backend.requests.where((FakeRequest r) => r.path.startsWith('/lives')), isEmpty);
      expect(players.created.single['manifest'], 'https://cdn.test/v/manifest.mpd?token=abc');
      // The server answered mode A: the next visit may speak of protection.
      expect(ClearDeliveryMemory.videoMode, 'drm_only');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await open();
      expect(find.text('Check & play'), findsOneWidget);
      expect(find.text('Protected lesson'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Unit and Lesson pages (D-132)', () {
    setUpAll(loadNovaFonts);

    testWidgets('the Unit lists its Lessons; a row opens one page with the video, the PDF and the quiz', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /lessons/1023/pdf-access': const FakeResponse(403, <String, Object>{
          'error': <String, String>{'code': 'FORBIDDEN', 'message': 'This action is unauthorized.'},
        }),
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned);
      await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(theme: NovaTheme.light, home: LearnScreen(course: course)),
      ));
      await tester.pumpAndSettle();

      // The Unit: its progress, where to continue, then every Lesson.
      expect(find.text('2 of 5 done'), findsOneWidget);
      expect(find.text('Continue: Energy: the safest points'), findsOneWidget);
      expect(find.text('Unit Lessons'), findsOneWidget);
      for (final Lesson lesson in course.lessons) {
        await _reveal(tester, find.text(lesson.title), 200);
        expect(find.text(lesson.title), findsOneWidget);
      }
      // The past Live is one of the Lessons, marked as such.
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Continue here'), findsOneWidget);
      expect(find.byType(LessonPlayer), findsNothing);

      await _reveal(tester, find.text('Energy: the safest points'), -200);
      await tester.tap(find.text('Energy: the safest points'));
      await tester.pumpAndSettle();

      // One page: 1. video, 2. PDF, 3. quiz, with the steps still to do.
      expect(find.byType(LessonScreen), findsOneWidget);
      expect(find.text('Lesson 3 of 5'), findsOneWidget);
      expect(find.byType(LessonPlayer), findsOneWidget);
      expect(find.text('Watch the video'), findsOneWidget);
      expect(find.text('You watched 55%. The video counts as watched at 90%.'), findsOneWidget);
      expect(find.text('To do'), findsNWidgets(3));
      await _reveal(tester, find.text('Retake'), 200);
      expect(find.text('Read the PDF'), findsOneWidget);
      expect(find.text('Take the quiz'), findsOneWidget);
      // Two attempts already, best 60 % under the 70 % pass mark.
      expect(find.text('Best score: 60%'), findsOneWidget);
      expect(find.text('Quiz passed, bravo!'), findsNothing);

      // The PDF opens in-app, through its signed access; a refusal is explained.
      await tester.ensureVisible(find.text('Open the PDF'));
      await tester.tap(find.text('Open the PDF'));
      // The refusal's empty state turns its orbit (as the website's): frames, not settle.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LessonPdfScreen), findsOneWidget);
      expect(backend.requests.map((FakeRequest r) => r.path), contains('/lessons/1023/pdf-access'));
      expect(find.text('PDF unavailable'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Back on the Lesson: the PDF step is ticked.
      expect(find.byType(LessonPdfScreen), findsNothing);
      expect(find.text('Opened. You can open it again at any time.'), findsOneWidget);
      await _reveal(tester, find.text('Lesson 3 of 5'), -300);
      expect(find.text('To do'), findsNWidgets(2));

      // Next: a Lesson without PDF whose quiz is optional.
      await _reveal(tester, find.text('Next lesson'), 300);
      await tester.tap(find.text('Next lesson'));
      await tester.pumpAndSettle();
      expect(find.text('Lesson 4 of 5'), findsOneWidget);
      expect(find.text('Momentum & collisions'), findsOneWidget);
      await _reveal(tester, find.text('Start the quiz'), 300);
      expect(find.text('No PDF for this lesson for now.'), findsOneWidget);
      expect(find.text('Take it whenever you want, even before the video.'), findsOneWidget);

      // The last Lesson is the past Live; its last button returns to the Unit.
      await _reveal(tester, find.text('Next lesson'), 300);
      await tester.tap(find.text('Next lesson'));
      await tester.pumpAndSettle();
      expect(find.text('Lesson 5 of 5'), findsOneWidget);
      expect(find.text('Recorded during the live class'), findsOneWidget);
      await _reveal(tester, find.text('All the lessons'), 300);
      expect(find.text('Next lesson'), findsNothing);
      await tester.tap(find.text('All the lessons'));
      await tester.pumpAndSettle();
      expect(find.byType(LessonScreen), findsNothing);
      expect(find.byType(LearnScreen), findsOneWidget);
      // Nothing was played or reported on the way.
      expect(backend.requests.where((FakeRequest r) => r.path.endsWith('/playback') || r.path.endsWith('/progress')), isEmpty);
    });

    test('a Lesson reads its PDF count; a server before D-142 means one PDF', () {
      final Lesson three = Lesson.fromJson(<String, dynamic>{'id': 1, 'title': 'A', 'has_pdf': true, 'pdf_count': 3});
      expect(three.pdfCount, 3);
      expect(Lesson.fromJson(<String, dynamic>{'id': 2, 'title': 'B', 'has_pdf': true}).pdfCount, 1);
      expect(Lesson.fromJson(<String, dynamic>{'id': 3, 'title': 'C', 'has_pdf': false}).pdfCount, 0);
      expect(three.withProgress(<String, dynamic>{'has_pdf': true, 'pdf_count': 2}).pdfCount, 2);
      expect(three.withProgress(<String, dynamic>{'has_pdf': true}).pdfCount, 3);
      expect(three.withProgress(<String, dynamic>{'has_pdf': false}).pdfCount, 0);
    });

    testWidgets('a Lesson shows one card per PDF in the Admin\'s order; each opens its own access (D-142)', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /lessons/1023': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{
            'id': 1023,
            'has_pdf': true,
            'pdfs': <Object>[
              <String, Object>{'id': 71, 'title': 'Energy — the summary', 'position': 1},
              <String, Object>{'id': 72, 'title': 'Energy — solved BAC exercises', 'position': 2},
            ],
          },
        }),
        'GET /lessons/1023/pdfs/72/access': const FakeResponse(403, <String, Object>{
          'error': <String, String>{'code': 'FORBIDDEN', 'message': 'This action is unauthorized.'},
        }),
        'GET /lessons/1023/pdfs/71/access': const FakeResponse(403, <String, Object>{
          'error': <String, String>{'code': 'FORBIDDEN', 'message': 'This action is unauthorized.'},
        }),
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned);
      final int index = course.lessons.indexWhere((Lesson l) => l.id == 1023);
      await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(theme: NovaTheme.light, home: LessonScreen(course: ValueNotifier<Course>(course), index: index)),
      ));
      await tester.pumpAndSettle();

      // Both PDFs, in order, under the plural title.
      await _reveal(tester, find.text('Energy — solved BAC exercises'), 200);
      expect(find.text('Read the PDFs'), findsOneWidget);
      expect(find.text('Read the PDF'), findsNothing);
      expect(tester.getTopLeft(find.text('Energy — the summary')).dy, lessThan(tester.getTopLeft(find.text('Energy — solved BAC exercises')).dy));
      expect(find.text('Open the PDF'), findsNWidgets(2));
      // A view-only Lesson (no downloads_remaining): nothing to download.
      expect(find.text('Download the PDF'), findsNothing);

      Future<void> openAndClose(int card) async {
        await tester.tap(find.text('Open the PDF').at(card));
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(LessonPdfScreen), findsOneWidget);
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }

      // The second card opens the second PDF through its own access; the step waits for the first.
      await openAndClose(1);
      expect(backend.requests.map((FakeRequest r) => r.path), contains('/lessons/1023/pdfs/72/access'));
      expect(backend.requests.map((FakeRequest r) => r.path), isNot(contains('/lessons/1023/pdf-access')));
      expect(find.text('Opened. You can open it again at any time.'), findsOneWidget);
      await _reveal(tester, find.text('Lesson 3 of 5'), -300);
      expect(find.text('To do'), findsNWidgets(3));

      // Every PDF opened: the PDF step is ticked.
      await _reveal(tester, find.text('Energy — the summary'), 200);
      await openAndClose(0);
      expect(backend.requests.map((FakeRequest r) => r.path), contains('/lessons/1023/pdfs/71/access'));
      expect(find.text('Opened. You can open it again at any time.'), findsNWidgets(2));
      await _reveal(tester, find.text('Lesson 3 of 5'), -300);
      expect(find.text('To do'), findsNWidgets(2));
    });

    testWidgets('a downloadable PDF gives the stamped copy to the share sheet and counts down (owner decision 2026-10-29)', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final _FakePdfSaver saver = _FakePdfSaver();
      final LessonPdfSaver Function() realSaver = LessonPdfSaver.factory;
      LessonPdfSaver.factory = () => saver;
      addTearDown(() => LessonPdfSaver.factory = realSaver);
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /lessons/1023': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{
            'id': 1023,
            'has_pdf': true,
            'allow_pdf_download': true,
            'pdf_download_limit': 5,
            'pdfs': <Object>[
              <String, Object>{'id': 71, 'title': 'Energy — the summary', 'position': 1, 'downloads_remaining': 2},
              <String, Object>{'id': 72, 'title': 'Energy — solved BAC exercises', 'position': 2, 'downloads_remaining': 0},
            ],
          },
        }),
      }, sequences: <String, List<FakeResponse>>{
        'POST /lessons/1023/pdfs/71/download': <FakeResponse>[
          FakeResponse(200, Uint8List.fromList('%PDF-1.4 stamped'.codeUnits), <String, List<String>>{
            'content-type': <String>['application/pdf'],
            'content-disposition': <String>["attachment; filename=\"Energy - Energy the summary.pdf\"; filename*=utf-8''Energy%20-%20Energy%20%E2%80%94%20the%20summary.pdf"],
            'x-nova-downloads-remaining': <String>['1'],
          }),
          const FakeResponse(409, <String, Object>{
            'error': <String, String>{'code': 'PDF_DOWNLOAD_LIMIT_REACHED', 'message': 'You have already downloaded this PDF 5 times, the maximum.'},
          }),
        ],
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned);
      final int index = course.lessons.indexWhere((Lesson l) => l.id == 1023);
      await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(theme: NovaTheme.light, home: LessonScreen(course: ValueNotifier<Course>(course), index: index)),
      ));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('You used the 5 downloads of this PDF.'), 200);

      // Each card: open, download, and what is left; the second has none left.
      expect(find.text('Open the PDF'), findsNWidgets(2));
      expect(find.text('Download the PDF'), findsNWidgets(2));
      expect(find.text('2 of 5 downloads left. Each copy carries your name and phone number.'), findsOneWidget);
      NovaButton download(int card) => tester.widget<NovaButton>(find.widgetWithText(NovaButton, 'Download the PDF').at(card));
      expect(download(1).onTap, isNull);
      expect(download(0).onTap, isNotNull);

      // A POST with the CSRF token; the copy goes to the share sheet under the server's name.
      await tester.tap(find.text('Download the PDF').first);
      await tester.pumpAndSettle();
      final FakeRequest sent = backend.requests.lastWhere((FakeRequest r) => r.path == '/lessons/1023/pdfs/71/download');
      expect(sent.method, 'POST');
      expect(sent.headers['X-XSRF-TOKEN'], Uri.decodeComponent(FakeBackend.xsrfCookieValue));
      expect(saver.saved, <String>['Energy - Energy — the summary.pdf']);
      expect(String.fromCharCodes(saver.bytes.single), '%PDF-1.4 stamped');
      expect(find.text('1 of 5 downloads left. Each copy carries your name and phone number.'), findsOneWidget);

      // The limit reached elsewhere: the server's refusal is explained and the button turns off.
      await tester.tap(find.text('Download the PDF').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('You have used all the downloads of this PDF.'), findsOneWidget);
      expect(find.text('You used the 5 downloads of this PDF.'), findsNWidgets(2));
      expect(download(0).onTap, isNull);
      expect(saver.saved, hasLength(1));
      await tester.pump(const Duration(seconds: 3));
    });

    test('a downloaded PDF is named from the server, safe for the phone', () {
      expect(LearningStore.pdfFileName("attachment; filename=\"a.pdf\"; filename*=utf-8''Le%C3%A7on%20-%20R%C3%A9sum%C3%A9.pdf", 'x'), 'Leçon - Résumé.pdf');
      expect(LearningStore.pdfFileName('attachment; filename="Limits - Summary.pdf"', 'x'), 'Limits - Summary.pdf');
      expect(LearningStore.pdfFileName(null, 'Maths: 1/2 - "Résumé"'), 'Maths 1 2 - Résumé.pdf');
      expect(LearningStore.pdfFileName("attachment; filename*=utf-8''%2F%2F.pdf", ''), 'NOVA.pdf');
      final LessonPdf pdf = LessonPdf.fromJson(<String, dynamic>{'id': 1, 'title': 'A', 'position': 1, 'downloads_remaining': 3});
      expect(pdf.downloadable, isTrue);
      expect(pdf.withDownloadsRemaining(2).downloadsRemaining, 2);
      expect(LessonPdf.fromJson(<String, dynamic>{'id': 1, 'title': 'A', 'position': 1, 'downloads_remaining': null}).downloadable, isFalse);
    });

    testWidgets('a quiz attempt is started, submitted and graded by the server, then the Unit follows', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /lessons/41/quiz': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{
            'id': 9,
            'required': true,
            'passing_score_percent': 70,
            'max_attempts': 3,
            'cooldown_enabled': true,
            'cooldown_minutes': 1440,
            'questions': <Object>[
              <String, Object?>{
                'id': 51,
                'type': 'single_choice',
                'prompt': 'Which law links force and acceleration?',
                'order_index': 1,
                'points': 1,
                'options': <Object>[
                  <String, Object>{'id': 501, 'label': 'Newton’s second law', 'order_index': 1},
                  <String, Object>{'id': 502, 'label': 'Ohm’s law', 'order_index': 2},
                ],
              },
            ],
          },
          'attempts': <String, Object?>{
            'attempts_submitted': 0,
            'remaining_attempts': 3,
            'best_score_percent': null,
            'passed': false,
            'open_attempt_id': null,
            'retry_at': null,
          },
        }),
        'POST /quizzes/9/attempts': const FakeResponse(201, <String, Object?>{
          'data': <String, Object?>{'id': 77, 'quiz_id': 9, 'attempt_number': 1},
        }),
        'POST /quiz-attempts/77/submit': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{
            'id': 77,
            'score_percent': '100.00',
            'passed': true,
            'answers': <Object>[
              <String, Object?>{'question_id': 51, 'selected_option_ids': <int>[501], 'is_correct': true},
            ],
          },
          'best_score_percent': '100.00',
          'attempts': <String, Object?>{
            'attempts_submitted': 1,
            'remaining_attempts': 2,
            'best_score_percent': '100.00',
            'passed': true,
            'open_attempt_id': null,
            'retry_at': null,
          },
        }),
        // The server completes the Lesson once its required quiz is passed.
        'GET /courses/102/progress': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{
            'course_id': 102,
            'progress_percent': '50.00',
            'lessons': <Object>[
              <String, Object?>{
                'lesson_id': 41,
                'video_progress_percent': '95.00',
                'resume_position_seconds': 0,
                'unlocked': true,
                'has_quiz': true,
                'quiz_required': true,
                'completed': true,
              },
            ],
          },
        }),
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      // A lesson watched past 90 % whose required quiz is still to pass.
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned).copyWith(
        lessons: <Lesson>[
          const Lesson(id: 41, title: 'Newton', minutes: 30, watched: 95, hasQuiz: true, quizRequired: true, apiCompleted: false),
          const Lesson(id: 42, title: 'Energy', minutes: 20, watched: 0),
        ],
      );

      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(theme: NovaTheme.light, home: LearnScreen(course: course)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 done'), findsOneWidget);

      await tester.tap(find.text('Newton'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Start the quiz'), 300);
      expect(find.text('Pass it to complete the lesson.'), findsOneWidget);
      await tester.tap(find.text('Start the quiz'));
      await tester.pumpAndSettle();

      expect(find.text('Which law links force and acceleration?'), findsOneWidget);
      await tester.tap(find.text('Newton’s second law'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Graded by the server: never scored on the device.
      expect(find.text('Quiz passed'), findsOneWidget);
      expect(
        backend.requests.where((FakeRequest r) => r.method == 'POST').map((FakeRequest r) => r.path),
        <String>['/quizzes/9/attempts', '/quiz-attempts/77/submit'],
      );
      final FakeRequest submit =
          backend.requests.firstWhere((FakeRequest r) => r.path == '/quiz-attempts/77/submit');
      expect(submit.data, <String, Object>{
        'answers': <Map<String, Object>>[
          <String, Object>{'question_id': 51, 'option_ids': <int>[501]},
        ],
      });
      // A pass reloads the Unit's progress from the server.
      expect(backend.requests.map((FakeRequest r) => r.path), contains('/courses/102/progress'));

      // Behind the sheet the Lesson's steps already show the video and quiz done.
      expect(find.text('Done'), findsNWidgets(3));
      await tester.tap(find.descendant(of: find.byType(QuizRunnerSheet), matching: find.text('Done')));
      await tester.pumpAndSettle();
      expect(find.byType(QuizRunnerSheet), findsNothing);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('Quiz passed, bravo!'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);

      // The Unit page shares the Course: the Lesson now counts as done.
      await _reveal(tester, find.byType(BackPill), -300);
      await tester.tap(find.byType(BackPill));
      await tester.pumpAndSettle();
      expect(find.byType(LessonScreen), findsNothing);
      expect(find.text('1 of 2 done'), findsOneWidget);
    });
  });

  group('Screen stays on while a video plays (D-133)', () {
    setUpAll(loadNovaFonts);
    setUp(ClearDeliveryMemory.reset);

    late List<bool> keepOn;
    const MethodChannel screen = MethodChannel('nova/screen');

    setUp(() {
      keepOn = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        screen,
        (MethodCall call) async {
          if (call.method == 'keepOn') keepOn.add(call.arguments as bool);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(screen, null);
    });

    testWidgets('holders are counted: on with the first, off after the last', (tester) async {
      final Object lesson = Object();
      final Object stage = Object();
      expect(ScreenAwake.held, isFalse);

      ScreenAwake.hold(lesson);
      ScreenAwake.hold(lesson); // Same holder: once.
      ScreenAwake.hold(stage);
      await tester.pump();
      expect(keepOn, <bool>[true]);
      expect(ScreenAwake.held, isTrue);

      ScreenAwake.release(lesson);
      await tester.pump();
      expect(keepOn, <bool>[true]); // The stage still holds it.

      ScreenAwake.release(stage);
      ScreenAwake.release(stage); // Unknown holder: nothing.
      await tester.pump();
      expect(keepOn, <bool>[true, false]);
      expect(ScreenAwake.held, isFalse);
    });

    testWidgets('a Lesson keeps the screen on while it plays, not after pause, end or leaving', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      const MethodChannel drm = MethodChannel('nova/drm');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, (MethodCall call) async => 'L1');
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, null));
      final FakeNativePlayers players = FakeNativePlayers()..install();
      addTearDown(players.uninstall);
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
        'PUT /lessons/0/progress': const FakeResponse(200, <String, Object?>{'data': <String, Object?>{}}),
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned);
      await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(theme: NovaTheme.light, home: LessonScreen(course: ValueNotifier<Course>(course), index: 0)),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(players.created, hasLength(1));
      expect(keepOn, isEmpty); // Authorized, not moving yet.

      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump();
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump();
      expect(keepOn, <bool>[true]);

      players.emit(<String, Object?>{'event': 'playing', 'value': false});
      await tester.pump();
      expect(keepOn, <bool>[true, false]);

      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump();
      players.emit(<String, Object?>{'event': 'state', 'state': 'ended'});
      await tester.pump();
      expect(keepOn, <bool>[true, false, true, false]);

      // Leaving the Lesson while it plays lets the phone sleep again.
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(keepOn, <bool>[true, false, true, false, true, false]);
      expect(ScreenAwake.held, isFalse);
    });
  });
}

/// Records what would be saved and shared (owner decision 2026-10-29).
class _FakePdfSaver implements LessonPdfSaver {
  final List<String> saved = <String>[];
  final List<List<int>> bytes = <List<int>>[];

  @override
  Future<void> save(String fileName, List<int> data, {Rect? origin}) async {
    saved.add(fileName);
    bytes.add(data);
  }
}
