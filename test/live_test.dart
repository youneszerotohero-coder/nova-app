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
import 'package:nova_mobile/features/learning/live_room_screen.dart';
import 'package:nova_mobile/features/player/playback_rules.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fake_native_player.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

/// `GET /lives/{id}` in the backend's shape (`LiveSessionResource` plus
/// `hand_status` / `muted` / `speaker`).
Map<String, Object?> _detail(
  String status, {
  String? mediaState,
  bool replay = false,
  bool comments = true,
  String? hand,
  Map<String, String>? speaker,
  String? replayDelivery,
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
        'started_at': status == 'live' ? '2026-09-24T18:01:00+00:00' : null,
        'server_time': '2026-09-24T18:10:00+00:00',
        'status': status,
        'media_state': mediaState,
        'comments_enabled': comments,
        'comment_max_length': 500,
        'replay_available': replay,
        'replay_delivery': ?replayDelivery,
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
}) =>
    mode == 'clear'
        ? <String, Object?>{
            'data': <String, Object?>{
              'mode': 'clear',
              'clear_fallback_available': false,
              'delivery': 'clear',
              'telemetry': false,
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
            home: LiveRoomScreen(live: HomeData.lives.first),
          ),
        ),
      );
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

    testWidgets('an ended live without replay says so and closes questions', (tester) async {
      await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('ended')),
      });
      expect(find.text('This live class has ended.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await leave(tester);
    });

    testWidgets('an ended live with a replay offers it, neutral while the mode is unknown', (tester) async {
      await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('ended', replay: true)),
      });
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Protected lesson'), findsNothing);
      await leave(tester);
    });

    testWidgets('D-077: the replay speaks of protection only in mode A', (tester) async {
      await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('ended', replay: true, replayDelivery: 'drm_only')),
      });
      expect(find.text('Check & play'), findsOneWidget);
      expect(find.text('Protected lesson'), findsOneWidget);
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

    testWidgets('mode C: iPhone plays the clear replay the server returns (D-070)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
          'GET /lives/301': FakeResponse(200, _detail('ended', replay: true)),
          'GET /lives/301/replay/playback': const FakeResponse(200, <String, Object?>{
            'data': <String, Object?>{
              'mode': 'clear',
              'manifest_url': 'https://vod.test/video/9/hls-clear/master.m3u8?token=t',
              'mime_type': 'application/x-mpegurl',
              'support_url': null,
              'expires_at': 1790000000,
              'duration_seconds': 3600,
              'watermark': <String, String>{'name': 'Ines Benali', 'phone': '0555123456'},
            },
          }),
        });
        await tester.tap(find.text('Play'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final FakeRequest replay =
            backend.requests.firstWhere((FakeRequest r) => r.path == '/lives/301/replay/playback');
        // FairPlay is tried first: no clear request from the app.
        expect(replay.query, isNot(contains('delivery=clear')));
        expect(players.created.single['clear'], isTrue);
        expect(find.text('Personal copy · identity watermark'), findsOneWidget);
        await leave(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
