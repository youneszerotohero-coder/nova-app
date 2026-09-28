import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/playback_models.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/player/lesson_player.dart';
import 'package:nova_mobile/features/player/playback_rules.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fake_native_player.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

/// A playback authorization in the backend's exact shape
/// (`PlaybackService::authorize`); [clearDelivery] is mode B (D-070).
Map<String, Object?> _authorization({String mode = 'strict', bool fallback = false, bool clearDelivery = false}) =>
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
        },
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
  });

  group('Lesson player states', () {
    setUpAll(loadNovaFonts);
    setUp(ClearDeliveryMemory.reset);

    late FakeBackend backend;
    late FakeNativePlayers players;
    const MethodChannel drm = MethodChannel('nova/drm');

    Future<void> pumpLearn(WidgetTester tester, {String? widevine}) async {
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
          child: MaterialApp(theme: NovaTheme.light, home: LearnScreen(course: course)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a software-only device is refused under the strict policy', (tester) async {
      backend = FakeBackend(<String, FakeResponse>{
        'POST /lessons/0/playback': FakeResponse(200, <String, Object?>{'data': _authorization()}),
      });
      await pumpLearn(tester, widevine: 'L3');

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
      await pumpLearn(tester, widevine: 'L1');

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.textContaining('still being prepared'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('mode A: iPhone stays blocked until FairPlay (D-055)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        backend = FakeBackend(<String, FakeResponse>{
          'POST /lessons/0/playback': _clearRefused,
        });
        await pumpLearn(tester);

        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();

        expect(find.textContaining('can’t play on iPhone yet'), findsOneWidget);
        // The one request asked for the clear copy, which mode A refuses.
        expect(
          backend.requests.where((FakeRequest r) => r.path.endsWith('/playback')).single.data,
          <String, String>{'delivery': 'clear'},
        );
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
        await pumpLearn(tester);

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
      await pumpLearn(tester, widevine: 'L3');

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
      await pumpLearn(tester, widevine: 'L1');

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
      await pumpLearn(tester, widevine: 'L1');

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
      await pumpLearn(tester, widevine: 'L1');

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
      await pumpLearn(tester, widevine: 'L1');

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

  group('Quizzes', () {
    setUpAll(loadNovaFonts);

    testWidgets('an attempt is started, submitted and graded by the server', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /lessons/0/quiz': const FakeResponse(200, <String, Object?>{
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
        'GET /courses/102/progress': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{'course_id': 102, 'progress_percent': '75.00', 'lessons': <Object>[]},
        }),
      });
      final AppState app = installFixtureApp(learning: LearningStore(fakeApi(backend)));
      // A lesson watched past 90 % so its quiz opens.
      final Course course = HomeData.popularCourses.firstWhere((Course c) => c.owned).copyWith(
        lessons: <Lesson>[
          const Lesson(title: 'Newton', minutes: 30, watched: 95, hasQuiz: true, quizRequired: true, apiCompleted: false),
        ],
      );

      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(theme: NovaTheme.light, home: LearnScreen(course: course)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quizzes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Required to unlock the next lesson'));
      await tester.pumpAndSettle();

      expect(find.text('Which law links force and acceleration?'), findsOneWidget);
      await tester.tap(find.text('Newton’s second law'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Quiz passed'), findsOneWidget);
      final FakeRequest submit =
          backend.requests.firstWhere((FakeRequest r) => r.path == '/quiz-attempts/77/submit');
      expect(submit.data, <String, Object>{
        'answers': <Map<String, Object>>[
          <String, Object>{'question_id': 51, 'option_ids': <int>[501]},
        ],
      });
    });
  });
}
