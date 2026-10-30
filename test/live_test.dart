import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/nova_api.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/account_store.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/live_store.dart';
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/learning/lesson_screen.dart';
import 'package:nova_mobile/features/learning/live_room_screen.dart';
import 'package:nova_mobile/features/learning/live_speaker.dart';
import 'package:nova_mobile/features/learning/live_speaking_stage.dart';
import 'package:nova_mobile/features/player/playback_rules.dart';
import 'package:nova_mobile/features/shell/student_top_bar.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fake_native_player.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

/// `GET /lives/{id}` in the backend's shape (`LiveSessionResource` plus
/// `hand_status` / `muted` / `speaker`).
///
/// D-132: once its recording is ready, a finished Live carries the
/// [lessonId] it became in its Unit ([courseSlug]).
///
/// D-117: [audienceOpen] false is a prepared Live behind closed doors;
/// [openedAt] is when "Start the Live" opened them (also `started_at`);
/// [waitingRoom] says the room was open.
Map<String, Object?> _detail(
  String status, {
  String? mediaState,
  bool comments = true,
  String? hand,
  Map<String, String>? speaker,
  int? lessonId,
  String courseSlug = 'physics-mechanics',
  bool? audienceOpen,
  String? openedAt,
  bool waitingRoom = false,
  String serverTime = '2026-09-24T18:10:00+00:00',
}) =>
    <String, Object?>{
      'data': <String, Object?>{
        'id': 301,
        'course_id': 102,
        'title': 'Mechanics live',
        'course_title': 'Physics — Mechanics Masterclass',
        'teacher_name': 'Amel Khaldi',
        'attendees_count': 14,
        'scheduled_at': '2026-09-24T18:00:00+00:00',
        'started_at': status == 'live' && audienceOpen != false ? openedAt ?? '2026-09-24T18:01:00+00:00' : null,
        'server_time': serverTime,
        'status': status,
        'audience_open': ?audienceOpen,
        'audience_opened_at': openedAt,
        'waiting_room': waitingRoom
            ? <String, Object?>{'opened_at': '2026-09-24T17:45:00+00:00', 'ends_at': '2026-09-24T18:00:00+00:00'}
            : null,
        'media_state': mediaState,
        'comments_enabled': comments,
        'comment_max_length': 500,
        'course_slug': courseSlug,
        'lesson_id': lessonId,
      },
      'hand_status': hand,
      'muted': false,
      'speaker': speaker,
    };

/// `POST /lives/{id}/playback-policy`: mode A (`clearDelivery: false`),
/// mode B (`clearDelivery: true`) or mode C (`mode: 'clear'`).
Map<String, Object?> _policy({
  bool strict = true,
  String mode = 'protected',
  bool clearDelivery = false,
  bool fairplay = false,
  bool telemetry = false,
}) =>
    mode == 'clear'
        ? <String, Object?>{
            'data': <String, Object?>{
              'mode': 'clear',
              'clear_fallback_available': false,
              'delivery': 'clear',
              'telemetry': telemetry,
            },
          }
        : <String, Object?>{
            'data': <String, Object?>{
              'mode': mode,
              'challenge': 'c' * 64,
              'expires_at': 1790000000,
              'candidates': <Object>[
                if (fairplay) <String, Object?>{'drm': 'fairplay', 'key_system': 'com.apple.fps', 'robustness': null},
                <String, Object>{
                  'drm': 'playready',
                  'key_system': strict ? 'com.microsoft.playready.recommendation.3000' : 'com.microsoft.playready.recommendation',
                  'robustness': strict ? '3000' : '2000',
                },
                <String, Object>{
                  'drm': 'widevine',
                  'key_system': 'com.widevine.alpha',
                  'robustness': strict ? 'HW_SECURE_ALL' : 'SW_SECURE_DECODE',
                },
              ],
              'policy': <String, Object?>{
                'mode': strict ? 'strict' : 'compatible',
                'software_fallback': !strict,
                'max_height': strict ? null : 480,
              },
              'clear_fallback_available': false,
              'clear_delivery_available': clearDelivery,
              'telemetry': false,
            },
          };

/// The clear join (`mode: cdn`, D-070).
const FakeResponse _clearJoin = FakeResponse(200, <String, Object?>{
  'data': <String, Object?>{
    'mode': 'cdn',
    'delivery': 'clear',
    'manifest_url': 'https://live.test/protected-live/301/clear-abc/master.m3u8',
    'mime_type': 'application/x-mpegurl',
    'expires_at': 1790000240,
    'renew_after_seconds': 240,
    'url_protection': 'none',
  },
});

/// The protected join (DASH + Widevine entitlement).
const FakeResponse _drmJoin = FakeResponse(200, <String, Object?>{
  'data': <String, Object?>{
    'mode': 'protected',
    'manifests': <String, String>{'dash': 'https://live.test/301/manifest.mpd', 'hls': 'https://live.test/301/master.m3u8'},
    'drm': <String, Object>{
      'token': 'ey.live',
      'license_urls': <String, String>{'widevine': 'https://drm.test/AcquireLicense'},
    },
    'protection': <String, Object?>{'max_height': null},
    'expires_at': 1790000240,
    'renew_after_seconds': 240,
    'url_protection': 'none',
  },
});

/// The protected join with FairPlay enabled (D-088): HLS + FairPlay URLs.
const FakeResponse _fairPlayJoin = FakeResponse(200, <String, Object?>{
  'data': <String, Object?>{
    'mode': 'protected',
    'manifests': <String, String>{'dash': 'https://live.test/301/manifest.mpd', 'hls': 'https://live.test/301/master.m3u8'},
    'drm': <String, Object>{
      'token': 'ey.live',
      'license_urls': <String, String>{
        'widevine': 'https://drm.test/AcquireLicense',
        'fairplay': 'https://fps.test/AcquireLicense',
      },
      'fairplay_certificate_url': 'https://nova.test/drm/fairplay.cer',
    },
    'protection': <String, Object?>{'max_height': null},
    'expires_at': 1790000240,
    'renew_after_seconds': 240,
    'url_protection': 'none',
  },
});

FakeResponse _error(int status, String code) => FakeResponse(status, <String, Object>{
      'error': <String, String>{'code': code, 'message': code},
    });

void main() {
  group('Live rules (web parity)', () {
    test('not-ready retries back off 2 → 8 s with ±15 % jitter', () {
      final Random random = Random(3);
      for (int attempt = 0; attempt < 10; attempt++) {
        final double base = <int>[2, 3, 4, 5, 6, 8][attempt.clamp(0, 5)] * 1000.0;
        final int ms = notReadyDelay(attempt, random).inMilliseconds;
        expect(ms, inInclusiveRange((base * 0.85).floor(), (base * 1.15).ceil()));
      }
    });

    test('past 180 s "not ready" keeps waiting at 15 s instead of giving up', () {
      final Random random = Random(5);
      final int late = notReadyDelay(9, random, waited: const Duration(seconds: 181)).inMilliseconds;
      expect(late, inInclusiveRange(12750, 17250));
      // While the server says the media is preparing, the fast cadence stays.
      final int preparing =
          notReadyDelay(9, random, waited: const Duration(minutes: 9), mediaState: 'preparing').inMilliseconds;
      expect(preparing, inInclusiveRange(6800, 9200));
    });

    test('transient failures back off 1, 2, 4, 8 then 15 s (±20 %), forever', () {
      final Random random = Random(11);
      const List<int> base = <int>[1000, 2000, 4000, 8000, 15000, 15000, 15000];
      for (int attempt = 1; attempt <= base.length; attempt++) {
        final int ms = liveRetryDelay(attempt, random).inMilliseconds;
        expect(ms, inInclusiveRange((base[attempt - 1] * 0.8).floor(), (base[attempt - 1] * 1.2).ceil()));
      }
    });

    test('renewal failures retry after 15 s × n, capped at 60 s', () {
      expect(renewalRetryDelay(1).inSeconds, 15);
      expect(renewalRetryDelay(3).inSeconds, 45);
      expect(renewalRetryDelay(9).inSeconds, 60);
    });

    test('the Widevine candidate follows the device and the server policy', () {
      final LivePolicy strict = LivePolicy.fromJson(_policy()['data']! as Map<String, dynamic>);
      expect(strict.widevineFor(hardware: true)?.robustness, 'HW_SECURE_ALL');
      expect(strict.widevineFor(hardware: false), isNull);
      expect(strict.clearAvailable, isFalse);
      final LivePolicy compatible =
          LivePolicy.fromJson(_policy(strict: false)['data']! as Map<String, dynamic>);
      expect(compatible.widevineFor(hardware: false)?.robustness, 'SW_SECURE_DECODE');
      expect(compatible.maxHeight, 480);
    });

    test('delivery modes: B offers the clear stream, C is clear for everyone', () {
      final LivePolicy b = LivePolicy.fromJson(_policy(clearDelivery: true)['data']! as Map<String, dynamic>);
      expect(b.isClear, isFalse);
      expect(b.clearAvailable, isTrue);
      final LivePolicy c = LivePolicy.fromJson(_policy(mode: 'clear')['data']! as Map<String, dynamic>);
      expect(c.isClear, isTrue);
      expect(c.clearAvailable, isTrue);
    });

    test('renewal timing uses the relative server hint, within 15–240 s', () {
      LiveJoin join(Map<String, Object?> data) => LiveJoin.fromJson(<String, dynamic>{
            'manifests': <String, String>{'dash': 'https://cdn/live.mpd'},
            'drm': <String, Object>{
              'token': 't',
              'license_urls': <String, String>{'widevine': 'https://drm/lic'},
            },
            ...data,
          });
      expect(join(<String, Object?>{'renew_after_seconds': 90}).renewAfter.inSeconds, 90);
      expect(join(<String, Object?>{'renew_after_seconds': 900}).renewAfter.inSeconds, 240);
      expect(join(<String, Object?>{'renew_after_seconds': 2}).renewAfter.inSeconds, 15);
      expect(join(<String, Object?>{'url_protection': 'signed'}).signedUrls, isTrue);
      // D-172: a URL signed for the whole Live never forces a reload.
      expect(join(<String, Object?>{'url_protection': 'session'}).signedUrls, isFalse);
      expect(join(<String, Object?>{'url_protection': 'none'}).signedUrls, isFalse);
    });

    group('a Live player that does not play restarts by itself (2026-10-29 first-join bug)', () {
      const Duration second = Duration(seconds: 1);

      /// Feeds [watch] one tick per second from [from] for [seconds] ticks.
      void feed(
        LivePlaybackWatch watch,
        int from,
        int seconds, {
        bool expected = true,
        bool playing = false,
        Duration position = const Duration(seconds: 14),
        Duration Function(int tick)? buffered,
      }) {
        for (int tick = from; tick < from + seconds; tick++) {
          watch.observe(
            elapsed: second * (tick + 1),
            expected: expected,
            playing: playing,
            position: position,
            buffered: buffered?.call(tick) ?? position,
          );
        }
      }

      test('a first frame then nothing loaded: restarted after 10 s, not before', () {
        final LivePlaybackWatch watch = LivePlaybackWatch();
        feed(watch, 0, 9);
        expect(watch.stuck(restarts: 0), isFalse);
        feed(watch, 9, 1);
        expect(watch.stuck(restarts: 0), isTrue);
        expect(watch.played, isFalse);
      });

      test('the next restarts wait longer (15, 20, then 30 s) so a slow link gets its chance', () {
        expect(LivePlaybackWatch.startTimeout(0), const Duration(seconds: 10));
        expect(LivePlaybackWatch.startTimeout(1), const Duration(seconds: 15));
        expect(LivePlaybackWatch.startTimeout(2), const Duration(seconds: 20));
        expect(LivePlaybackWatch.startTimeout(9), const Duration(seconds: 30));
        final LivePlaybackWatch watch = LivePlaybackWatch();
        feed(watch, 0, 14);
        expect(watch.stuck(restarts: 1), isFalse);
        feed(watch, 14, 1);
        expect(watch.stuck(restarts: 1), isTrue);
      });

      test('media loading ahead is progress, up to three times the wait without playing', () {
        final LivePlaybackWatch watch = LivePlaybackWatch();
        // 0.6 s more media every second, nothing plays.
        feed(watch, 0, 29, buffered: (int tick) => const Duration(seconds: 14) + const Duration(milliseconds: 600) * tick);
        expect(watch.stuck(restarts: 0), isFalse);
        feed(watch, 29, 1, buffered: (int tick) => const Duration(seconds: 14) + const Duration(milliseconds: 600) * tick);
        expect(watch.stuck(restarts: 0), isTrue);
      });

      test('the Android live window sliding is not progress', () {
        final LivePlaybackWatch watch = LivePlaybackWatch();
        // Position and buffered end move back together every 2 s.
        for (int tick = 0; tick < 10; tick++) {
          final Duration slide = Duration(seconds: 2 * (tick ~/ 2));
          watch.observe(
            elapsed: second * (tick + 1),
            expected: true,
            playing: false,
            position: const Duration(seconds: 28) - slide,
            buffered: const Duration(seconds: 28) - slide,
          );
        }
        expect(watch.stuck(restarts: 0), isTrue);
      });

      test('once it played, a stall is restarted after 20 s without progress', () {
        final LivePlaybackWatch watch = LivePlaybackWatch();
        feed(watch, 0, 30, playing: true);
        expect(watch.stuck(restarts: 0), isFalse);
        feed(watch, 30, 19);
        expect(watch.played, isTrue);
        expect(watch.stuck(restarts: 0), isFalse);
        feed(watch, 49, 1);
        expect(watch.stuck(restarts: 0), isTrue);
      });

      test('paused by the Student, away from the screen or media not ready: never restarted', () {
        final LivePlaybackWatch watch = LivePlaybackWatch();
        feed(watch, 0, 120, expected: false);
        expect(watch.stuck(restarts: 0), isFalse);
        // Back to "should play": a full wait again.
        feed(watch, 120, 9);
        expect(watch.stuck(restarts: 0), isFalse);
        feed(watch, 129, 1);
        expect(watch.stuck(restarts: 0), isTrue);
      });

      test('ready_state follows the website (HTMLMediaElement)', () {
        expect(liveReadyState(phase: 'idle', firstFrame: false, playing: false), 0);
        expect(liveReadyState(phase: 'buffering', firstFrame: false, playing: false), 1);
        expect(liveReadyState(phase: 'buffering', firstFrame: true, playing: false), 2);
        expect(liveReadyState(phase: 'ready', firstFrame: true, playing: false), 3);
        expect(liveReadyState(phase: 'ready', firstFrame: true, playing: true), 4);
      });
    });

    test('the speaking stage shows the Professor only once a frame is on screen (D-073)', () {
      PresenterPicture picture({
        bool connected = true,
        bool professorPresent = true,
        bool cameraPublished = true,
        bool cameraMuted = false,
        bool subscribed = true,
        bool pausedByServer = false,
        bool frameShown = true,
      }) =>
          presenterPictureFor(
            connected: connected,
            professorPresent: professorPresent,
            cameraPublished: cameraPublished,
            cameraMuted: cameraMuted,
            subscribed: subscribed,
            pausedByServer: pausedByServer,
            frameShown: frameShown,
          );

      expect(picture(), PresenterPicture.showing);
      expect(picture(connected: false), PresenterPicture.connecting);
      expect(picture(professorPresent: false), PresenterPicture.connecting);
      expect(picture(subscribed: false), PresenterPicture.connecting);
      expect(picture(frameShown: false), PresenterPicture.connecting);
      expect(picture(cameraPublished: false), PresenterPicture.paused);
      expect(picture(cameraMuted: true), PresenterPicture.paused);
      expect(picture(pausedByServer: true), PresenterPicture.paused);
    });

    test('a frame counts as shown only when decoded after the renderer was attached', () {
      final PresenterFrameWatch frames = PresenterFrameWatch();
      // Frames decoded before the stage existed are not on screen.
      expect(frames.observe(120), isFalse);
      expect(frames.observe(120), isFalse);
      expect(frames.observe(121), isTrue);
      expect(frames.observe(121), isTrue);

      // Stats appear late: the first number is the baseline.
      final PresenterFrameWatch late = PresenterFrameWatch();
      expect(late.observe(null), isFalse);
      expect(late.observe(0), isFalse);
      expect(late.observe(1), isTrue);

      // A phone whose stats never answer is shown the picture, as before.
      final PresenterFrameWatch blind = PresenterFrameWatch();
      for (int i = 1; i < PresenterFrameWatch.blindLimit; i++) {
        expect(blind.observe(null), isFalse);
      }
      expect(blind.observe(null), isTrue);
    });

    group('D-117 closed doors and the D-128 reveal (web live-room.tsx)', () {
      LiveDetail detail(String status, {bool? audienceOpen, String? openedAt, bool waitingRoom = true}) =>
          LiveDetail.fromJson(_detail(status, audienceOpen: audienceOpen, openedAt: openedAt, waitingRoom: waitingRoom));
      final DateTime opened = DateTime.utc(2026, 9, 24, 18, 2);

      test('a prepared Live behind closed doors is a wait, not a broadcast', () {
        for (final String status in <String>['starting', 'live']) {
          final LiveDetail closed = detail(status, audienceOpen: false);
          expect(closed.doorsClosed, isTrue, reason: status);
          expect(closed.isWaiting, isTrue, reason: status);
          expect(closed.inWaitingRoom, isTrue, reason: status);
          expect(closed.showsBroadcast(waited: true, serverNow: opened), isFalse, reason: status);
          expect(closed.showsBroadcast(waited: false, serverNow: opened), isFalse, reason: status);
          expect(closed.classElapsed(opened), isNull, reason: status);
        }
        expect(detail('scheduled').isWaiting, isTrue);
        expect(detail('scheduled', waitingRoom: false).inWaitingRoom, isFalse);
      });

      test('a server without the field, or a Live without waiting room, has its doors open', () {
        final LiveDetail old = detail('live', waitingRoom: false);
        expect(old.audienceOpen, isTrue);
        expect(old.doorsClosed, isFalse);
        expect(old.isWaiting, isFalse);
        expect(old.showsBroadcast(waited: false, serverNow: opened), isTrue);
      });

      test('a Student who waited sees the Live 9 s after the doors opened, a late Student at once', () {
        final LiveDetail open = detail('live', audienceOpen: true, openedAt: '2026-09-24T18:02:00+00:00');
        expect(open.audienceOpenedAt!.isAtSameMomentAs(opened), isTrue);
        expect(open.doorsClosed, isFalse);
        expect(open.inWaitingRoom, isFalse);

        final DateTime early = opened.add(const Duration(seconds: 8, milliseconds: 900));
        expect(open.holdsReveal(waited: true, serverNow: early), isTrue);
        expect(open.showsBroadcast(waited: true, serverNow: early), isFalse);
        expect(open.showsBroadcast(waited: false, serverNow: early), isTrue);
        expect(open.showsBroadcast(waited: true, serverNow: opened.add(LiveDetail.revealDelay)), isTrue);
      });

      test('the class clock starts at 00:00 with the first picture (Student delay)', () {
        final LiveDetail open = detail('live', audienceOpen: true, openedAt: '2026-09-24T18:02:00+00:00');
        expect(open.classElapsed(opened.add(const Duration(seconds: 5))), Duration.zero);
        expect(open.classElapsed(opened.add(const Duration(seconds: 70))), const Duration(seconds: 61));
        expect(detail('starting', audienceOpen: true).classElapsed(opened), isNull);
      });
    });

    test('the clear join parses the cdn shape', () {
      final LiveJoin parsed = LiveJoin.fromJson((_clearJoin.body! as Map<String, dynamic>)['data'] as Map<String, dynamic>);
      expect(parsed.clear, isTrue);
      expect(parsed.manifestUrl, endsWith('master.m3u8'));
      expect(parsed.mimeType, 'application/x-mpegurl');
      expect(parsed.signedUrls, isFalse);
    });
  });

  group('Live room', () {
    setUpAll(loadNovaFonts);
    setUp(ClearDeliveryMemory.reset);
    const MethodChannel drm = MethodChannel('nova/drm');
    late FakeNativePlayers players;

    Future<FakeBackend> pumpRoom(
      WidgetTester tester,
      Map<String, FakeResponse> routes, {
      Map<String, List<FakeResponse>>? sequences,
      String? widevine = 'L1',
      bool withSession = false,
      bool pushed = false,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, (MethodCall call) async => widevine);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(drm, null));
      players = FakeNativePlayers()..install();
      addTearDown(players.uninstall);

      final FakeBackend backend = FakeBackend(routes, sequences: sequences);
      final NovaApi api = fakeApi(backend);
      final AppState app;
      if (withSession) {
        // A session backed by the fake API, for `PUT /onboarding`.
        app = AppState.seeded(
          session: SessionStore.seeded(
            HomeData.student,
            api: api,
            user: <String, Object?>{
              'id': 7,
              'role': 'student',
              'student': <String, Object?>{
                'id': 70,
                'first_name': '',
                'last_name': '',
                'level': <String, Object>{'id': 2, 'name_fr': '3AS'},
                'track': <String, Object>{'id': 5, 'name_fr': 'Sciences'},
                'wilaya': <String, Object>{'id': 16, 'name_fr': 'Alger'},
                'commune': <String, Object>{'id': 1601, 'name_fr': 'Alger Centre'},
              },
            },
          ),
          catalog: CatalogStore.seeded(courses: HomeData.popularCourses, offers: HomeData.featuredPacks, teachers: HomeData.teachers),
          learning: LearningStore.seeded(owned: const [], lives: HomeData.lives),
          commerce: CommerceStore.seeded(cart: const [], orders: const []),
          account: AccountStore.seeded(notifications: const [], ledger: const [], balance: 0),
          live: LiveStore(api),
        );
        AppState.instance = app;
      } else {
        app = installFixtureApp(live: LiveStore(api));
      }
      app.setLang(NovaLang.en);
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: NovaTheme.light,
            // [pushed]: opened from a page, as from the Lives tab.
            home: pushed
                ? Builder(
                    builder: (BuildContext context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => LiveRoomScreen(live: HomeData.lives.first),
                          )),
                          child: const Text('Open the room'),
                        ),
                      ),
                    ),
                  )
                : LiveRoomScreen(live: HomeData.lives.first),
          ),
        ),
      );
      if (pushed) {
        await tester.tap(find.text('Open the room'));
        await tester.pump();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      return backend;
    }

    /// Unmounts the room so its timers stop before the test ends.
    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    }

    Iterable<FakeRequest> joins(FakeBackend backend) =>
        backend.requests.where((FakeRequest r) => r.path == '/lives/301/join');

    /// Every telemetry event the player sent (the rest is flushed on leaving).
    List<Map<String, dynamic>> telemetry(FakeBackend backend) => <Map<String, dynamic>>[
          for (final FakeRequest r in backend.requests.where((FakeRequest r) => r.path == '/lives/301/playback-telemetry'))
            for (final Object? event in (r.data! as Map<String, Object?>)['events']! as List<Object?>)
              event! as Map<String, dynamic>,
        ];

    /// The clear Live of the apps (D-152) with telemetry on.
    Map<String, FakeResponse> clearLive() => <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy(mode: 'clear', telemetry: true)),
          'POST /lives/301/join': _clearJoin,
          'POST /lives/301/playback-telemetry': const FakeResponse(204),
        };

    /// One native `position` report: the playhead, and media loaded to [buffered].
    Map<String, Object?> position(int ms, {int? buffered}) => <String, Object?>{
          'event': 'position',
          'position': ms,
          'duration': 0,
          'buffered': buffered ?? ms,
          'liveOffset': 14000,
        };

    testWidgets('a scheduled live waits, and questions go privately to the team', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('scheduled')),
        'POST /lives/301/comments': const FakeResponse(201, <String, String>{'message': 'Message sent.'}),
      });

      expect(find.textContaining('starts'), findsOneWidget);
      expect(find.text('Raise hand to speak'), findsNothing); // only while live

      await tester.enterText(find.byType(TextField), 'Can you repeat the second law?');
      await tester.tap(find.bySemanticsLabel('Send question'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final FakeRequest ask = backend.requests.firstWhere((FakeRequest r) => r.path == '/lives/301/comments');
      expect(ask.data, <String, String>{'message': 'Can you repeat the second law?'});
      await leave(tester);
    });

    testWidgets('D-117: behind closed doors the Student waits, then sees the Live 9 s after the doors open', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'POST /lives/301/playback-policy': FakeResponse(200, _policy(mode: 'clear')),
          'POST /lives/301/join': _clearJoin,
        },
        sequences: <String, List<FakeResponse>>{
          'GET /lives/301': <FakeResponse>[
            // Prepared: the media runs, the doors are closed.
            FakeResponse(200, _detail('live', mediaState: 'ready', audienceOpen: false, waitingRoom: true)),
            // "Start the Live" 2 s ago: the picture of that moment is not here yet.
            FakeResponse(200, _detail('live', mediaState: 'ready', audienceOpen: true, openedAt: '2026-09-24T18:10:00+00:00',
                waitingRoom: true, serverTime: '2026-09-24T18:10:02+00:00')),
            // 12 s after the doors opened.
            FakeResponse(200, _detail('live', mediaState: 'ready', audienceOpen: true, openedAt: '2026-09-24T18:10:00+00:00',
                waitingRoom: true, serverTime: '2026-09-24T18:10:12+00:00')),
          ],
        },
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('starts'), findsOneWidget);
      expect(players.created, isEmpty);
      expect(backend.requests.where((FakeRequest r) => r.path == '/lives/301/playback-policy'), isEmpty);
      expect(find.textContaining('LIVE CLASS ·'), findsNothing);

      // The room keeps asking while the doors are closed (8 s without realtime).
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('The broadcast is starting'), findsOneWidget);
      expect(players.created, isEmpty);
      expect(joins(backend), isEmpty);

      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(milliseconds: 200));
      expect(joins(backend), hasLength(1));
      expect(players.created, hasLength(1));
      // 12 s after the doors opened, minus the 9 s the picture takes.
      expect(find.textContaining(RegExp(r'LIVE CLASS · 0:0[34]')), findsOneWidget);
      await leave(tester);
    });

    testWidgets('D-117: a Student arriving after the doors opened sees the Live at once', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready', audienceOpen: true,
            openedAt: '2026-09-24T18:10:00+00:00', waitingRoom: true, serverTime: '2026-09-24T18:10:02+00:00')),
        'POST /lives/301/playback-policy': FakeResponse(200, _policy(mode: 'clear')),
        'POST /lives/301/join': _clearJoin,
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(joins(backend), hasLength(1));
      expect(players.created, hasLength(1));
      await leave(tester);
    });

    testWidgets('mode A: a software-only phone is refused and never joins', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy()),
        },
        widevine: 'L3',
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('hardware protection'), findsOneWidget);
      expect(joins(backend), isEmpty);
      await leave(tester);
    });

    testWidgets('mode B: a software-only phone plays the clear stream with the watermark', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy(clearDelivery: true)),
          'POST /lives/301/join': _clearJoin,
        },
        widevine: 'L3',
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(joins(backend).single.data, <String, String>{'delivery': 'clear'});
      expect(players.created.single['clear'], isTrue);
      expect(players.created.single['manifest'], endsWith('master.m3u8'));
      expect(players.created.single['live'], isTrue);
      expect(find.text('Personal copy · identity watermark'), findsOneWidget);
      expect(find.textContaining(HomeData.student.phone), findsOneWidget);
      expect(ClearDeliveryMemory.live, isTrue);
      await leave(tester);
    });

    testWidgets('mode C: the clear stream is joined without a body', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
        'POST /lives/301/playback-policy': FakeResponse(200, _policy(mode: 'clear')),
        'POST /lives/301/join': _clearJoin,
      });
      await tester.pump(const Duration(milliseconds: 200));

      expect(joins(backend).single.data, isNull);
      expect(players.created.single['clear'], isTrue);
      await leave(tester);
    });

    testWidgets('a player that shows a first frame and never plays restarts itself (first-join bug)', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, clearLive());
      await tester.pump(const Duration(milliseconds: 200));
      expect(players.created, hasLength(1));

      // What the app telemetry showed in Lives 55–64: a first frame, then
      // nothing loaded ahead and nothing playing, until the Student left.
      players.emit(<String, Object?>{'event': 'state', 'state': 'buffering'});
      players.emit(<String, Object?>{'event': 'firstFrame'});
      for (int i = 0; i < 9; i++) {
        players.emit(position(14000));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(players.created, hasLength(1), reason: 'not before 10 s');

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(joins(backend), hasLength(2));
      expect(players.created, hasLength(2));
      expect(players.created.last['clear'], isTrue);

      // The fresh player plays, as after leaving and opening the Live again.
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump(const Duration(milliseconds: 100));
      await leave(tester);

      final List<Map<String, dynamic>> events = telemetry(backend);
      final Map<String, dynamic> error = events.singleWhere((Map<String, dynamic> e) => e['type'] == 'error');
      expect(error['error_category'], liveFailureCodes['first_frame_timeout']);
      expect(error['buffer_ahead_s'], 0);
      expect(error['edge_distance_s'], 14);
      expect(error['ready_state'], 2);
      final Map<String, dynamic> reload = events.singleWhere((Map<String, dynamic> e) => e['type'] == 'reload');
      expect(reload['error_code'], liveReloadHardRecover);
      expect(reload['attempt'], 1);
      final List<Map<String, dynamic>> ready = events.where((Map<String, dynamic> e) => e['type'] == 'ready').toList();
      expect(ready, hasLength(2));
      expect(ready.first.containsKey('error_code'), isFalse);
      expect(ready.last['error_code'], liveReloadHardRecover);
      final Map<String, dynamic> playing = events.singleWhere((Map<String, dynamic> e) => e['type'] == 'playing');
      expect(playing['error_code'], liveReloadHardRecover);
      expect(playing['first_frame_ms'], isA<num>());
      expect(playing['startup_ms'], isA<num>());
    });

    testWidgets('a player still loading on a slow link is left alone', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, clearLive());
      await tester.pump(const Duration(milliseconds: 200));
      players.emit(<String, Object?>{'event': 'state', 'state': 'buffering'});
      for (int i = 0; i < 25; i++) {
        players.emit(position(14000, buffered: 14000 + 600 * i));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(joins(backend), hasLength(1));
      expect(players.created, hasLength(1));
      await leave(tester);
    });

    testWidgets('a stall after playing is measured, then restarted after 20 s', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, clearLive());
      await tester.pump(const Duration(milliseconds: 200));
      players.emit(<String, Object?>{'event': 'firstFrame'});
      players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump(const Duration(seconds: 2));

      // A short stall that recovers by itself.
      players.emit(<String, Object?>{'event': 'playing', 'value': false});
      players.emit(<String, Object?>{'event': 'state', 'state': 'buffering'});
      await tester.pump(const Duration(seconds: 2));
      players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump(const Duration(seconds: 2));

      // A stall that does not.
      players.emit(<String, Object?>{'event': 'playing', 'value': false});
      players.emit(<String, Object?>{'event': 'state', 'state': 'buffering'});
      await tester.pump(const Duration(seconds: 15));
      expect(players.created, hasLength(1));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 200));
      expect(joins(backend), hasLength(2));
      expect(players.created, hasLength(2));
      await leave(tester);

      final List<Map<String, dynamic>> events = telemetry(backend);
      final List<Map<String, dynamic>> waiting = events.where((Map<String, dynamic> e) => e['type'] == 'waiting').toList();
      expect(waiting, hasLength(2));
      final List<Map<String, dynamic>> playing = events.where((Map<String, dynamic> e) => e['type'] == 'playing').toList();
      expect(playing.first.containsKey('first_frame_ms'), isTrue);
      expect(playing[1]['stall_count'], 1);
      expect(playing[1]['stall_ms'], isA<num>());
      final Map<String, dynamic> error = events.singleWhere((Map<String, dynamic> e) => e['type'] == 'error');
      expect(error['error_category'], liveFailureCodes['timeout']);
      expect(events.singleWhere((Map<String, dynamic> e) => e['type'] == 'reload')['error_code'], liveReloadHardRecover);
    });

    testWidgets('a Live the Student paused is neither a stall nor restarted', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, clearLive());
      await tester.pump(const Duration(milliseconds: 200));
      players.emit(<String, Object?>{'event': 'firstFrame'});
      players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
      players.emit(<String, Object?>{'event': 'playing', 'value': true});
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      expect(players.commands[players.lastId]!.map((MethodCall c) => c.method), contains('pause'));
      players.emit(<String, Object?>{'event': 'playing', 'value': false});
      await tester.pump(const Duration(seconds: 40));
      expect(joins(backend), hasLength(1));
      await leave(tester);
      expect(telemetry(backend).where((Map<String, dynamic> e) => e['type'] == 'waiting' || e['type'] == 'reload'), isEmpty);
    });

    testWidgets('mode B: a DRM decoder failure continues on the clear stream', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy(clearDelivery: true)),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lives/301/join': <FakeResponse>[_drmJoin, _clearJoin],
        },
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(players.created.single['clear'], isFalse);
      expect((joins(backend).first.data! as Map<String, Object?>)['robustness'], 'HW_SECURE_ALL');

      // Android secure decoder failure (the 3016 case on the web).
      players.emit(<String, Object?>{'event': 'error', 'category': 'decode', 'kind': 'decoder', 'code': 4003});
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(joins(backend).last.data, <String, String>{'delivery': 'clear'});
      expect(players.created.last['clear'], isTrue);
      expect(ClearDeliveryMemory.live, isTrue);
      await leave(tester);
    });

    testWidgets('a busy or failing server is retried without a dead end', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy()),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lives/301/join': <FakeResponse>[_error(503, 'HTTP_503'), _error(429, 'TOO_MANY_REQUESTS'), _drmJoin],
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Reconnecting to the live broadcast…'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(joins(backend).length, 3);
      expect(players.created.single['clear'], isFalse);
      await leave(tester);
    });

    testWidgets('media not ready yet shows "starting" and retries the join', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'preparing')),
        'POST /lives/301/playback-policy': FakeResponse(200, _policy()),
        'POST /lives/301/join': _error(409, 'LIVE_PROTECTED_MEDIA_NOT_READY'),
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('The broadcast is starting'), findsOneWidget);

      expect(joins(backend).first.data, <String, Object?>{
        'challenge': 'c' * 64,
        'key_system': 'com.widevine.alpha',
        'robustness': 'HW_SECURE_ALL',
      });

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(joins(backend).length, greaterThan(1));
      await leave(tester);
    });

    testWidgets('a Student without a name adds it, then joins (D-073)', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/join': _clearJoin,
          'PUT /onboarding': const FakeResponse(200, <String, Object?>{
            'data': <String, Object?>{
              'id': 7,
              'role': 'student',
              'phone': '0555123456',
              'student': <String, Object?>{'id': 70, 'first_name': 'Ines', 'last_name': 'Benali'},
            },
          }),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lives/301/playback-policy': <FakeResponse>[
            _error(422, 'PROFILE_NAME_REQUIRED'),
            FakeResponse(200, _policy(mode: 'clear')),
          ],
        },
        withSession: true,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Add your name to join the Live'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'First name'), 'Ines');
      await tester.enterText(find.widgetWithText(TextField, 'Last name'), 'Benali');
      await tester.tap(find.text('Continue to the Live'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final FakeRequest onboarding = backend.requests.firstWhere((FakeRequest r) => r.path == '/onboarding');
      expect(onboarding.data, <String, Object?>{
        'first_name': 'Ines',
        'last_name': 'Benali',
        'level_id': 2,
        'track_id': 5,
        'wilaya_id': 16,
        'commune_id': 1601,
      });
      expect(joins(backend), hasLength(1));
      expect(players.created.single['clear'], isTrue);
      await leave(tester);
    });

    testWidgets('the other Students see who is speaking', (tester) async {
      await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(
          200,
          _detail('live', mediaState: 'preparing', speaker: <String, String>{'first_name': 'Amina', 'last_name': 'Saadi'}),
        ),
        'POST /lives/301/playback-policy': FakeResponse(200, _policy()),
        'POST /lives/301/join': _error(409, 'LIVE_PROTECTED_MEDIA_NOT_READY'),
      });
      expect(find.text('\u{1F3A4} Amina Saadi is speaking'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('raising a hand queues it (retried while the Live is busy), lowering withdraws it', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'preparing')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy()),
          'POST /lives/301/join': _error(409, 'LIVE_PROTECTED_MEDIA_NOT_READY'),
          'DELETE /lives/301/raise-hand': const FakeResponse(204),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lives/301/raise-hand': <FakeResponse>[_error(409, 'LIVE_BUSY'), const FakeResponse(204)],
        },
      );

      await tester.tap(find.text('Raise hand to speak'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        backend.requests.where((FakeRequest r) => r.method == 'POST' && r.path == '/lives/301/raise-hand'),
        hasLength(2),
      );
      expect(find.text('Raise hand to speak'), findsNothing);

      await tester.tap(find.text('Your hand is in the queue'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.requests.any((FakeRequest r) => r.method == 'DELETE' && r.path == '/lives/301/raise-hand'), isTrue);
      expect(find.text('Raise hand to speak'), findsOneWidget);
      await leave(tester);
    });

    /// No Live replay endpoint exists any more (D-132).
    Iterable<String> replayRequests(FakeBackend backend) =>
        backend.requests.map((FakeRequest r) => r.path).where((String path) => path.contains('replay'));

    testWidgets('an ended live without a lesson says so and closes questions', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('ended')),
      });
      expect(find.text('This live class has ended.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Play'), findsNothing);
      expect(players.created, isEmpty);
      expect(replayRequests(backend), isEmpty);
      await leave(tester);
    });

    testWidgets('while its recording is processed, the room says the video will become a lesson', (tester) async {
      final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('processing_replay')),
      });
      expect(find.text('This live class has ended. Its video will soon be a lesson of your Unit.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Play'), findsNothing);
      expect(players.created, isEmpty);
      // Nothing to play here: no playback policy, no join, no replay.
      expect(backend.requests.map((FakeRequest r) => r.path), <String>['/lives/301']);
      await leave(tester);
    });

    testWidgets('an ended live that became a lesson closes the room and opens that Lesson in its Unit (D-132)', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('ended', lessonId: 1025)),
        },
        pushed: true,
      );
      await tester.pumpAndSettle();

      expect(find.byType(LiveRoomScreen), findsNothing);
      expect(find.byType(LessonScreen), findsOneWidget);
      expect(find.text('Live — energy exercises, BAC style'), findsOneWidget);
      expect(find.text('Recorded during the live class'), findsOneWidget);
      expect(find.text('Lesson 5 of 5'), findsOneWidget);
      // The Lesson plays like any other, on demand: nothing was requested.
      expect(find.text('Play'), findsOneWidget);
      expect(players.created, isEmpty);
      expect(backend.requests.map((FakeRequest r) => r.path), <String>['/lives/301']);

      // Back: the Unit's Lessons, then the page the room was opened from.
      await tester.tap(find.byType(BackPill));
      await tester.pumpAndSettle();
      expect(find.byType(LearnScreen), findsOneWidget);
      expect(find.text('Physics — Mechanics Masterclass'), findsOneWidget);
      await tester.tap(find.byType(BackPill));
      await tester.pumpAndSettle();
      expect(find.text('Open the room'), findsOneWidget);
      expect(replayRequests(backend), isEmpty);
      await leave(tester);
    });

    testWidgets('an ended live of a Unit the Student does not have stays on the ended message', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('ended', lessonId: 1025, courseSlug: 'math-lab')),
        },
        pushed: true,
      );
      await tester.pumpAndSettle();

      expect(find.byType(LiveRoomScreen), findsOneWidget);
      expect(find.byType(LessonScreen), findsNothing);
      expect(find.text('This live class has ended.'), findsOneWidget);
      expect(replayRequests(backend), isEmpty);
      await leave(tester);
    });

    testWidgets('D-077 mode B: an unreachable protected stream goes clear and is reported', (tester) async {
      final FakeBackend backend = await pumpRoom(
        tester,
        <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy(clearDelivery: true)),
          'POST /playback-diagnostics': const FakeResponse(204),
        },
        sequences: <String, List<FakeResponse>>{
          'POST /lives/301/join': <FakeResponse>[_drmJoin, _drmJoin, _drmJoin, _clearJoin],
        },
      );
      await tester.pump(const Duration(milliseconds: 200));
      // The protected manifest keeps failing (e.g. 404 on the CDN): two
      // quick reloads, then the clear stream instead of a retry loop.
      for (int i = 0; i < 3; i++) {
        players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2004});
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(joins(backend).last.data, <String, String>{'delivery': 'clear'});
      expect(players.created.last['clear'], isTrue);
      expect(find.textContaining('Protected'), findsNothing);
      // Concerns this Live's protected copy, not the device.
      expect(ClearDeliveryMemory.live, isFalse);
      final FakeRequest trace = backend.requests.lastWhere((FakeRequest r) => r.path == '/playback-diagnostics');
      expect(trace.data, containsPair('reason', 'media_unavailable'));
      expect(trace.data, containsPair('event', 'clear_fallback'));
      expect(trace.data, containsPair('content', 'live'));
      await leave(tester);
    });

    testWidgets('mode A: iPhone joins the Live with FairPlay (D-118)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy(fairplay: true)),
          'POST /lives/301/join': _fairPlayJoin,
        });
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(joins(backend).single.data, <String, Object?>{
          'challenge': 'c' * 64,
          'key_system': 'com.apple.fps',
          'robustness': null,
        });
        final Map<String, Object?> created = players.created.single;
        expect(created['clear'], isFalse);
        expect(created['manifest'], 'https://live.test/301/master.m3u8');
        expect(created['license'], 'https://fps.test/AcquireLicense');
        expect(created['certificate'], 'https://nova.test/drm/fairplay.cer');
        expect(created['token'], 'ey.live');
        await leave(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('mode A: iPhone is refused when the server offers no FairPlay', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
          'POST /lives/301/playback-policy': FakeResponse(200, _policy()),
        });
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('iPhone'), findsWidgets);
        expect(joins(backend), isEmpty);
        await leave(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Speaking stage (D-073)', () {
    setUpAll(loadNovaFonts);

    testWidgets('never a black screen: connecting, then the picture, or a paused notice', (tester) async {
      final AppState app = installFixtureApp();
      app.setLang(NovaLang.en);
      final _StageSpeaker speaker = _StageSpeaker();
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: NovaTheme.light,
            home: Scaffold(body: LiveSpeakingStage(liveId: 301, speaker: speaker, fullscreen: false)),
          ),
        ),
      );
      await tester.pump();

      // Accepted, the room connects: the stage says so instead of black.
      expect(find.text('Connecting to live conversation…'), findsOneWidget);
      expect(find.text('Video paused, audio continues'), findsNothing);
      expect(find.text('You are speaking'), findsOneWidget);

      // The Professor's first frame is on screen.
      speaker.show(PresenterPicture.showing);
      await tester.pump();
      expect(find.text('Connecting to live conversation…'), findsNothing);
      expect(find.text('Video paused, audio continues'), findsNothing);

      // The server paused the camera (downlink too weak): audio goes on.
      speaker.show(PresenterPicture.paused);
      await tester.pump();
      expect(find.text('Video paused, audio continues'), findsOneWidget);
      expect(find.text('Connecting to live conversation…'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// A speaker whose Professor picture the test sets; no LiveKit room.
class _StageSpeaker extends LiveSpeaker {
  _StageSpeaker() : super(onDropped: () {});

  PresenterPicture _picture = PresenterPicture.connecting;

  @override
  PresenterPicture get presenterPicture => _picture;

  void show(PresenterPicture picture) {
    _picture = picture;
    changes.value++;
  }
}
