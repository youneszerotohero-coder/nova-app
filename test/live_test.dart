import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show DisconnectReason;
import 'package:nova_mobile/core/api/nova_api.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/account_store.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/live_store.dart';
import 'package:nova_mobile/data/models.dart' show LiveSession;
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/learning/lesson_screen.dart';
import 'package:nova_mobile/features/learning/live_comment_reply.dart';
import 'package:nova_mobile/features/learning/live_pinned_comment.dart';
import 'package:nova_mobile/features/learning/live_room_screen.dart';
import 'package:nova_mobile/features/learning/live_speaker.dart';
import 'package:nova_mobile/features/learning/live_speaking_stage.dart';
import 'package:nova_mobile/features/learning/live_waiting_room.dart';
import 'package:nova_mobile/features/player/live_player.dart';
import 'package:nova_mobile/features/player/playback_rules.dart';
import 'package:nova_mobile/features/player/protected_video.dart';
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
  Map<String, Object?>? pinned,
  List<Map<String, Object?>>? replies,
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
        'pinned_comment': pinned,
      },
      'hand_status': hand,
      'muted': false,
      'speaker': speaker,
      'comment_replies': ?replies,
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
  group('D-186 pinned comment parsing', () {
    test('the Live detail carries the pinned comment text only, null when removed or empty', () {
      final LiveDetail pinned = LiveDetail.fromJson(_detail('live', pinned: <String, Object?>{
        'id': 55,
        'message': '  Read chapter 4  ',
        'created_at': '2026-09-24T18:05:00+00:00',
      }));
      expect(pinned.pinnedComment?.id, 55);
      expect(pinned.pinnedComment?.message, 'Read chapter 4');
      expect(LiveDetail.fromJson(_detail('live')).pinnedComment, isNull);
      expect(LivePinnedComment.fromJson(<String, dynamic>{'id': 3, 'message': '   '}), isNull);
      // The realtime payload of `LivePinnedCommentChanged`.
      final Map<String, dynamic> event = <String, dynamic>{'live_id': 301, 'pinned_comment': <String, dynamic>{'id': 9, 'message': 'Exercise 3'}};
      expect(LivePinnedComment.fromJson(event['pinned_comment'] as Map<String, dynamic>)?.message, 'Exercise 3');
      expect(LivePinnedComment.fromJson(null), isNull);
    });

    test('D-207: a Live of several Units shows every Unit and knows its Lesson in each', () {
      final Map<String, Object?> data = <String, Object?>{
        ...(_detail('ended', lessonId: 10)['data']! as Map<String, Object?>),
        'courses': <Map<String, Object?>>[
          <String, Object?>{'id': 102, 'title': 'Maths SE', 'slug': 'maths-se'},
          <String, Object?>{'id': 103, 'title': 'Maths MT', 'slug': 'maths-mt'},
        ],
        'lessons': <Map<String, Object?>>[
          <String, Object?>{'course_id': 102, 'course_slug': 'maths-se', 'lesson_id': 10},
          <String, Object?>{'course_id': 103, 'course_slug': 'maths-mt', 'lesson_id': 11},
        ],
      };
      final LiveSession live = LiveSession.fromJson(data);
      expect(live.course, 'Maths SE · Maths MT');
      expect(live.replayLessons, <String, int>{'maths-se': 10, 'maths-mt': 11});
      // Older servers: the one Course and no Lesson map.
      final LiveSession older = LiveSession.fromJson(_detail('ended', lessonId: 10)['data']! as Map<String, Object?>);
      expect(older.course, 'Physics — Mechanics Masterclass');
      expect(older.replayLessons, isEmpty);
    });

    test('D-204: the Admin answers to this Student come with the question they answer', () {
      final LiveDetail detail = LiveDetail.fromJson(_detail('live', replies: <Map<String, Object?>>[
        <String, Object?>{'id': 7, 'comment_id': 70, 'comment_message': ' Is chapter 4 in? ', 'message': ' Yes ', 'created_at': '2026-09-24T18:06:00+00:00'},
        <String, Object?>{'id': 6, 'comment_id': 69, 'comment_message': 'Hello', 'message': '   ', 'created_at': '2026-09-24T18:05:00+00:00'},
      ]));
      expect(detail.commentReplies.map((LiveCommentReply reply) => reply.id), <int>[7]);
      expect(detail.commentReplies.single.question, 'Is chapter 4 in?');
      expect(detail.commentReplies.single.message, 'Yes');
      // Older servers send nothing.
      expect(LiveDetail.fromJson(_detail('live')).commentReplies, isEmpty);
    });
  });

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

      test('D-212: PlayReady on the PC waits 20 s, then 25 and 30 s, as its software starts took 12–19 s', () {
        expect(LivePlaybackWatch.startTimeout(0, slowDrm: true), const Duration(seconds: 20));
        expect(LivePlaybackWatch.startTimeout(1, slowDrm: true), const Duration(seconds: 25));
        expect(LivePlaybackWatch.startTimeout(9, slowDrm: true), const Duration(seconds: 30));
        final LivePlaybackWatch watch = LivePlaybackWatch();
        feed(watch, 0, 19);
        expect(watch.stuck(restarts: 0, slowDrm: true), isFalse);
        expect(watch.stuck(restarts: 0), isTrue, reason: 'the phones keep 10 s');
        feed(watch, 19, 1);
        expect(watch.stuck(restarts: 0, slowDrm: true), isTrue);
        expect(watch.waited, const Duration(seconds: 20));
      });

      test('D-212: hardware PlayReady without a picture after 6 s asks for software, once', () {
        bool due({bool hardware = true, bool asked = false, bool firstFrame = false, int seconds = 6}) =>
            PcHardwareStart.fallbackDue(hardware: hardware, asked: asked, firstFrame: firstFrame, waited: Duration(seconds: seconds));
        expect(due(seconds: 5), isFalse);
        expect(due(), isTrue);
        expect(due(asked: true), isFalse);
        expect(due(firstFrame: true), isFalse);
        expect(due(hardware: false, seconds: 30), isFalse, reason: 'software and clear streams are left to the watch');
      });

      test('ready_state follows the website (HTMLMediaElement)', () {
        expect(liveReadyState(phase: 'idle', firstFrame: false, playing: false), 0);
        expect(liveReadyState(phase: 'buffering', firstFrame: false, playing: false), 1);
        expect(liveReadyState(phase: 'buffering', firstFrame: true, playing: false), 2);
        expect(liveReadyState(phase: 'ready', firstFrame: true, playing: false), 3);
        expect(liveReadyState(phase: 'ready', firstFrame: true, playing: true), 4);
      });
    });

    test('after a speaking turn the kept broadcast returns to the live edge only if it drifted (owner, 2026-10-30)', () {
      // Playing about 12–14 s behind the edge, as the native players follow it.
      expect(liveReturnNeedsEdge(playing: true, liveOffset: const Duration(seconds: 14)), isFalse);
      expect(liveReturnNeedsEdge(playing: true, liveOffset: liveReturnDriftLimit), isFalse);
      // Drifted, paused for a weak downlink or stalled, or an unknown distance.
      expect(liveReturnNeedsEdge(playing: true, liveOffset: const Duration(seconds: 21)), isTrue);
      expect(liveReturnNeedsEdge(playing: false, liveOffset: const Duration(seconds: 12)), isTrue);
      expect(liveReturnNeedsEdge(playing: true, liveOffset: null), isTrue);
    });

    test('iPhone: a Live more than 20 s behind goes back to the edge with one seek, never repeatedly (2026-10-30)', () {
      // 6 s behind, or up to the limit after stalls: left alone, no catch-up.
      expect(liveDriftNeedsSeek(playing: true, liveOffset: const Duration(seconds: 6)), isFalse);
      expect(liveDriftNeedsSeek(playing: true, liveOffset: liveReturnDriftLimit), isFalse);
      expect(liveDriftNeedsSeek(playing: true, liveOffset: const Duration(seconds: 21)), isTrue);
      // Not playing (stall, pause) or an unknown distance: the watchdog's business.
      expect(liveDriftNeedsSeek(playing: false, liveOffset: const Duration(seconds: 40)), isFalse);
      expect(liveDriftNeedsSeek(playing: true, liveOffset: null), isFalse);
      // At most one seek per 30 s.
      expect(
        liveDriftNeedsSeek(playing: true, liveOffset: const Duration(seconds: 25), sinceLastSeek: const Duration(seconds: 29)),
        isFalse,
      );
      expect(
        liveDriftNeedsSeek(playing: true, liveOffset: const Duration(seconds: 25), sinceLastSeek: liveDriftSeekEvery),
        isTrue,
      );
    });

    group('D-192 sound only, faster start, adaptive latency (2026-10-31)', () {
      Duration at(int seconds) => Duration(seconds: seconds);

      test('the first estimate lands on 480p, or follows the link measured in this app session', () {
        AbrStartMemory.reset();
        addTearDown(AbrStartMemory.reset);
        expect(AbrStartMemory.startBps(), 2200000);
        // Media3 picks within 70 %: clear HLS 480p peak 1.33 fits, 720p 2.47 does not; DASH video 480p ≤ 1.2, 720p ≥ 1.8.
        expect(AbrStartMemory.startBps() * 0.7, greaterThanOrEqualTo(1330000));
        expect(AbrStartMemory.startBps() * 0.7, lessThan(1800000));
        AbrStartMemory.remember(null);
        AbrStartMemory.remember(0);
        expect(AbrStartMemory.startBps(), 2200000);
        AbrStartMemory.remember(5000000);
        expect(AbrStartMemory.startBps(), 4000000);
        AbrStartMemory.remember(300000);
        expect(AbrStartMemory.startBps(), AbrStartMemory.minBps);
        AbrStartMemory.remember(50000000);
        expect(AbrStartMemory.startBps(), AbrStartMemory.maxBps);
      });

      test('sound only after 20 s below 350 kbit/s, never on one sample, an unmeasured estimate or a pause', () {
        final LiveAudioOnly rule = LiveAudioOnly();
        expect(rule.observe(now: at(0), bandwidthBps: 300000, playing: true), isNull);
        expect(rule.observe(now: at(5), bandwidthBps: null, playing: true), isNull);
        expect(rule.observe(now: at(6), bandwidthBps: 300000, playing: false), isNull);
        expect(rule.observe(now: at(10), bandwidthBps: 300000, playing: true), isNull);
        expect(rule.observe(now: at(19), bandwidthBps: 900000, playing: true), isNull);
        expect(rule.observe(now: at(21), bandwidthBps: 300000, playing: true), isNull);
        expect(rule.observe(now: at(30), bandwidthBps: 300000, playing: true), isNull);
        expect(rule.observe(now: at(41), bandwidthBps: 300000, playing: true), AudioOnlyDecision.enter);
        expect(rule.on, isTrue);
        expect(rule.reason, 'bandwidth');
      });

      test('sound only after 2 stalls within 60 s on the lowest rung; back at a calm 20 s check from 700 kbit/s', () {
        final LiveAudioOnly rule = LiveAudioOnly();
        const Duration stall = Duration(milliseconds: 900);
        expect(rule.stall(now: at(0), duration: stall, lowestRung: false), isNull);
        expect(rule.stall(now: at(1), duration: const Duration(milliseconds: 400), lowestRung: true), isNull);
        expect(rule.stall(now: at(2), duration: stall, lowestRung: true), isNull);
        expect(rule.stall(now: at(63), duration: stall, lowestRung: true), isNull);
        expect(rule.stall(now: at(70), duration: stall, lowestRung: true), AudioOnlyDecision.enter);
        expect(rule.reason, 'stalls');
        expect(rule.observe(now: at(80), bandwidthBps: 2000000, playing: true), isNull);
        rule.stall(now: at(85), duration: stall, lowestRung: false);
        expect(rule.observe(now: at(90), bandwidthBps: 2000000, playing: true), isNull, reason: 'a stall since the last check');
        expect(rule.observe(now: at(110), bandwidthBps: 650000, playing: true), isNull);
        expect(rule.observe(now: at(130), bandwidthBps: 700000, playing: true), AudioOnlyDecision.leave);
        // Back to the sound only within 5 minutes: the hold doubles.
        rule.stall(now: at(140), duration: stall, lowestRung: true);
        expect(rule.stall(now: at(141), duration: stall, lowestRung: true), AudioOnlyDecision.enter);
        expect(rule.hold, const Duration(seconds: 40));
        expect(rule.observe(now: at(175), bandwidthBps: 3000000, playing: true), isNull);
        expect(rule.observe(now: at(181), bandwidthBps: 3000000, playing: true), AudioOnlyDecision.leave);
        expect(rule.entries, 2);
      });

      test('the lowest rung of a ladder only', () {
        expect(onLowestRung(<int>[1080, 720, 480, 360, 240], 240), isTrue);
        expect(onLowestRung(<int>[1080, 720, 480, 360, 240], 360), isFalse);
        expect(onLowestRung(<int>[1080], 1080), isFalse);
        expect(onLowestRung(<int>[720, 480], null), isFalse);
      });

      test('7 s behind the edge after 60 s healthy, back to 12 s on a stall, the next try later and later', () {
        final LiveLatencyTarget rule = LiveLatencyTarget();
        LiveLatencyMode healthy(int seconds) => rule.observe(
            now: at(seconds), playing: true, bufferAhead: const Duration(seconds: 8), liveOffset: const Duration(seconds: 12));
        expect(rule.target, const Duration(seconds: 12));
        expect(healthy(0), LiveLatencyMode.normal);
        expect(rule.observe(now: at(30), playing: true, bufferAhead: const Duration(seconds: 2), liveOffset: const Duration(seconds: 12)),
            LiveLatencyMode.normal);
        expect(healthy(31), LiveLatencyMode.normal);
        expect(healthy(90), LiveLatencyMode.normal);
        expect(healthy(91), LiveLatencyMode.low);
        expect(rule.target, const Duration(seconds: 7));
        expect(rule.stall(now: at(100), duration: const Duration(milliseconds: 300)), LiveLatencyMode.low);
        expect(rule.stall(now: at(100), duration: const Duration(seconds: 1)), LiveLatencyMode.normal);
        // The next try waits 2 minutes, then 4.
        for (int t = 102; t < 220; t += 2) {
          expect(healthy(t), LiveLatencyMode.normal, reason: 'at $t s');
        }
        expect(healthy(220), LiveLatencyMode.low);
        rule.stall(now: at(222), duration: const Duration(seconds: 1));
        expect(rule.failures, 2);
        expect(healthy(224), LiveLatencyMode.normal);
        expect(healthy(461), LiveLatencyMode.normal);
        expect(healthy(462), LiveLatencyMode.low);
        // Ten minutes close forget the failures; a fresh native player counts as a stall.
        expect(rule.observe(now: at(1062), playing: true, bufferAhead: const Duration(seconds: 5), liveOffset: const Duration(seconds: 7)),
            LiveLatencyMode.low);
        expect(rule.failures, 0);
        expect(rule.stall(now: at(1063), duration: const Duration(days: 1)), LiveLatencyMode.normal);
        expect(rule.failures, 1);
      });
    });

    group('D-190 recovery in place, no endless decoder retries (Live 69, 2026-10-31)', () {
      const Duration s0 = Duration.zero;
      LiveFailureAction decide(LiveRecovery recovery, String category, String kind, int code, Duration now,
              {TargetPlatform platform = TargetPlatform.android}) =>
          recovery.decide(category: category, kind: kind, code: code, now: now, platform: platform);

      test('Android 1002 behind the live window jumps to the live edge in place', () {
        final LiveRecovery recovery = LiveRecovery();
        expect(decide(recovery, 'behind_live', 'other', 1002, s0), LiveFailureAction.edgeJump);
        expect(recovery.edgeJumps, 1);
      });

      test('two failed edge jumps within 60 s: the next one is today\'s full reload', () {
        final LiveRecovery recovery = LiveRecovery();
        expect(decide(recovery, 'behind_live', 'other', 1002, s0), LiveFailureAction.edgeJump);
        expect(decide(recovery, 'behind_live', 'other', 1002, const Duration(seconds: 20)), LiveFailureAction.edgeJump);
        expect(decide(recovery, 'behind_live', 'other', 1002, const Duration(seconds: 59)), LiveFailureAction.usual);
        // The full reload's new player gets its own edge jumps.
        expect(decide(recovery, 'behind_live', 'other', 1002, const Duration(seconds: 90)), LiveFailureAction.edgeJump);
      });

      test('edge jumps spread over more than 60 s never reload', () {
        final LiveRecovery recovery = LiveRecovery();
        for (int minute = 0; minute < 5; minute++) {
          expect(decide(recovery, 'behind_live', 'other', 1002, Duration(seconds: 35 * minute)), LiveFailureAction.edgeJump);
        }
      });

      test('only Media3 1002 behind_live counts: iPhone, the PC app and other codes are unchanged', () {
        final LiveRecovery recovery = LiveRecovery();
        expect(decide(recovery, 'behind_live', 'other', 1002, s0, platform: TargetPlatform.iOS), LiveFailureAction.usual);
        expect(decide(recovery, 'behind_live', 'other', 1002, s0, platform: TargetPlatform.windows), LiveFailureAction.usual);
        expect(decide(recovery, 'delivery', 'other', 1002, s0), LiveFailureAction.usual);
        expect(decide(recovery, 'behind_live', 'other', 2001, s0), LiveFailureAction.usual);
        expect(recovery.edgeJumps, 0);
      });

      test('decoder codes: three automatic attempts, then the error state and no more retries', () {
        final LiveRecovery recovery = LiveRecovery();
        expect(decide(recovery, 'capability', 'decoder', 4001, s0), LiveFailureAction.decoderRetry);
        expect(decide(recovery, 'decode', 'decoder', 4003, const Duration(seconds: 5)), LiveFailureAction.decoderRetry);
        expect(decide(recovery, 'capability', 'decoder', 4001, const Duration(seconds: 10)), LiveFailureAction.decoderRetry);
        expect(decide(recovery, 'capability', 'decoder', 4001, const Duration(seconds: 15)), LiveFailureAction.decoderGiveUp);
        expect(decide(recovery, 'capability', 'decoder', 4001, const Duration(seconds: 20)), LiveFailureAction.decoderGiveUp);
        // "Try again" by the Student: one attempt, the next failure shows the error again.
        recovery.retriedByStudent();
        expect(decide(recovery, 'capability', 'decoder', 4001, const Duration(seconds: 30)), LiveFailureAction.decoderGiveUp);
      });

      test('two minutes of continuous playback give a later decoder failure fresh attempts', () {
        final LiveRecovery recovery = LiveRecovery();
        for (int i = 0; i < 3; i++) {
          decide(recovery, 'decode', 'decoder', 4003, Duration(seconds: i));
        }
        recovery.observe(playing: true, now: const Duration(seconds: 10));
        recovery.observe(playing: true, now: const Duration(seconds: 100));
        recovery.observe(playing: false, now: const Duration(seconds: 101)); // a stall restarts the count
        recovery.observe(playing: true, now: const Duration(seconds: 102));
        recovery.observe(playing: true, now: const Duration(seconds: 200));
        expect(recovery.decoderFailures, 3);
        recovery.observe(playing: true, now: const Duration(seconds: 222));
        expect(recovery.decoderFailures, 0);
        expect(decide(recovery, 'decode', 'decoder', 4003, const Duration(seconds: 230)), LiveFailureAction.decoderRetry);
      });

      test('only decoder codes: iPhone AVError decoder codes count, the PC app and other kinds do not', () {
        final LiveRecovery recovery = LiveRecovery();
        expect(decide(recovery, 'decode', 'decoder', -11821, s0, platform: TargetPlatform.iOS), LiveFailureAction.decoderRetry);
        expect(decide(recovery, 'decode', 'decoder', 3016, s0, platform: TargetPlatform.windows), LiveFailureAction.usual);
        expect(decide(recovery, 'decode', 'other', 4003, s0), LiveFailureAction.usual);
        expect(decide(recovery, 'license', 'drm', 6004, s0), LiveFailureAction.usual);
        expect(decide(recovery, 'decode', 'decoder', 3001, s0), LiveFailureAction.usual);
        expect(recovery.decoderFailures, 1);
      });

      test('network failures keep today\'s handling and touch no counter', () {
        final LiveRecovery recovery = LiveRecovery();
        for (final int code in <int>[2000, 2001, 2002, 2004]) {
          expect(
            decide(recovery, code == 2002 ? 'timeout' : 'delivery', 'other', code, s0),
            LiveFailureAction.usual,
          );
        }
        expect(recovery.edgeJumps, 0);
        expect(recovery.decoderFailures, 0);
      });

      test('the first decoder retry asks for one rendition lower', () {
        expect(lowerDecodeHeight(<int>[1080, 720, 480]), 720);
        expect(lowerDecodeHeight(<int>[480, 1080, 720]), 720);
        expect(lowerDecodeHeight(<int>[1080, 720, 480], current: 720), 480);
        expect(lowerDecodeHeight(<int>[1080, 720, 480], current: 480), 480);
        expect(lowerDecodeHeight(<int>[480]), isNull);
        expect(lowerDecodeHeight(const <int>[]), isNull);
      });
    });

    test('a speaking turn LiveKit ended is never reconnected (Live 66, 2026-10-30)', () {
      expect(speakerTurnEndedBy(DisconnectReason.participantRemoved), isTrue);
      expect(speakerTurnEndedBy(DisconnectReason.roomDeleted), isTrue);
      for (final DisconnectReason reason in <DisconnectReason>[
        DisconnectReason.participantRemoved,
        DisconnectReason.roomDeleted,
        DisconnectReason.duplicateIdentity,
        DisconnectReason.clientInitiated,
      ]) {
        expect(speakerReconnectsAfter(reason), isFalse, reason: '$reason');
      }
      // A lost connection gets its one reconnect.
      for (final DisconnectReason? reason in <DisconnectReason?>[
        null,
        DisconnectReason.unknown,
        DisconnectReason.signalClose,
        DisconnectReason.disconnected,
        DisconnectReason.signalingConnectionFailure,
        DisconnectReason.reconnectAttemptsExceeded,
        DisconnectReason.joinFailure,
      ]) {
        expect(speakerTurnEndedBy(reason), isFalse, reason: '$reason');
        expect(speakerReconnectsAfter(reason), isTrue, reason: '$reason');
      }
    });

    group('LiveSpeaker disconnections (Live 66: a removed Student reconnected)', () {
      const SpeakerGrant grant = SpeakerGrant(url: 'wss://livekit.test', token: 'lk');

      testWidgets('removed by the team: no reconnect, the turn is reported over', (tester) async {
        int dropped = 0;
        final _LinkSpeaker speaker = _LinkSpeaker(() => dropped++);
        int changes = 0;
        speaker.changes.addListener(() => changes++);
        await speaker.connect(grant);
        expect(speaker.opens, 1);

        await speaker.disconnected(DisconnectReason.participantRemoved);
        await tester.pump(const Duration(seconds: 2));
        expect(speaker.opens, 1, reason: 'no new LiveKit session with the turn grant');
        expect(speaker.removed, isTrue);
        expect(changes, 1);
        expect(dropped, 0);
        await speaker.close();
      });

      testWidgets('a lost connection gets one reconnect after 750 ms', (tester) async {
        int dropped = 0;
        final _LinkSpeaker speaker = _LinkSpeaker(() => dropped++);
        await speaker.connect(grant);
        unawaited(speaker.disconnected(DisconnectReason.signalClose));
        await tester.pump(const Duration(milliseconds: 700));
        expect(speaker.opens, 1);
        await tester.pump(const Duration(milliseconds: 100));
        expect(speaker.opens, 2);
        expect(speaker.removed, isFalse);
        expect(dropped, 0);

        // A second loss: given up, the room lowers the hand.
        await speaker.disconnected(DisconnectReason.signalClose);
        expect(speaker.opens, 2);
        expect(dropped, 1);
        await speaker.close();
      });

      testWidgets('closed during the reconnect wait (the turn ended): never reconnected', (tester) async {
        int dropped = 0;
        final _LinkSpeaker speaker = _LinkSpeaker(() => dropped++);
        await speaker.connect(grant);
        unawaited(speaker.disconnected(DisconnectReason.signalClose));
        await tester.pump(const Duration(milliseconds: 300));
        await speaker.close();
        await tester.pump(const Duration(seconds: 2));
        expect(speaker.opens, 1);
        expect(dropped, 0);
      });

      testWidgets('the same Student joining elsewhere ends this conversation without a reconnect', (tester) async {
        int dropped = 0;
        final _LinkSpeaker speaker = _LinkSpeaker(() => dropped++);
        await speaker.connect(grant);
        await speaker.disconnected(DisconnectReason.duplicateIdentity);
        await tester.pump(const Duration(seconds: 2));
        expect(speaker.opens, 1);
        expect(dropped, 1);
        await speaker.close();
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
      LiveSpeaker? speaker,
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
                            builder: (_) => LiveRoomScreen(
                              live: HomeData.lives.first,
                              speakerFactory: speaker == null ? null : (_) => speaker,
                            ),
                          )),
                          child: const Text('Open the room'),
                        ),
                      ),
                    ),
                  )
                : LiveRoomScreen(
                    live: HomeData.lives.first,
                    speakerFactory: speaker == null ? null : (_) => speaker,
                  ),
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

    testWidgets('D-110: the waiting room counts down on the server clock, speaks and tells the Admin', (tester) async {
      // Owner report 2026-11-17: the apps only said when the Live starts.
      final FakeBackend backend = await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('scheduled', waitingRoom: true, serverTime: '2026-09-24T17:50:00+00:00')),
        'POST /lives/301/waiting-room/presence': FakeResponse(204, null),
      });
      Iterable<FakeRequest> beats() => backend.requests.where((FakeRequest r) => r.path == '/lives/301/waiting-room/presence');

      // Ten minutes before the end the Admin set, whatever this phone's clock says.
      expect(find.text('The live starts in'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(beats(), hasLength(1));
      expect(players.created, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Welcome to NOVA, your distance-learning platform!'), findsOneWidget);
      await tester.tap(find.text('Mute'));
      await tester.pump();
      expect(find.text('Turn sound on'), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      expect(beats(), hasLength(2));
      await leave(tester);
    });

    test('D-110: the waiting room shows mm:ss rounded up and the caption of each sentence', () {
      expect(waitingCountdown(const Duration(minutes: 9, seconds: 59, milliseconds: 1)), '10:00');
      expect(waitingCountdown(const Duration(seconds: 5)), '00:05');
      expect(waitingCaptionAt(0.5), -1);
      expect(waitingCaptionAt(1), 0);
      expect(waitingCaptionAt(24 + 6), 1);
      expect(waitingCaptionAt(21), -1);
      final LiveSession live = LiveSession.fromJson(_detail('scheduled', waitingRoom: true)['data']! as Map<String, Object?>);
      expect(live.waitingRoomEndsAt, DateTime.parse('2026-09-24T18:00:00+00:00').toLocal());
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

    testWidgets('D-186: the comment pinned by the Admin is at the top of the Live chat, without its author', (tester) async {
      await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready', pinned: <String, Object?>{
          'id': 55,
          'message': 'Read chapter 4 before Sunday',
          'created_at': '2026-09-24T18:05:00+00:00',
        })),
        'POST /lives/301/playback-policy': FakeResponse(200, _policy(mode: 'clear')),
        'POST /lives/301/join': _clearJoin,
      });
      await tester.pump(const Duration(milliseconds: 200));

      final Finder banner = find.byType(LivePinnedCommentBanner);
      expect(banner, findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('Pinned by the teaching team')), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('Read chapter 4 before Sunday')), findsOneWidget);
      // Above the question field, in the chat area.
      expect(tester.getTopLeft(banner).dy, lessThan(tester.getTopLeft(find.byType(TextField)).dy));
      await leave(tester);
    });

    testWidgets('D-204: the Admin answer is over the picture with the question until the Student hides it', (tester) async {
      await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready', replies: <Map<String, Object?>>[
          <String, Object?>{'id': 7, 'comment_id': 70, 'comment_message': 'Is chapter 4 in the exam?', 'message': 'Yes, all of it.', 'created_at': '2026-09-24T18:06:00+00:00'},
        ])),
        'POST /lives/301/playback-policy': FakeResponse(200, _policy(mode: 'clear')),
        'POST /lives/301/join': _clearJoin,
      });
      await tester.pump(const Duration(milliseconds: 200));

      final Finder card = find.byType(LiveCommentReplyCard);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Answer from the teaching team')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Your question: Is chapter 4 in the exam?')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Yes, all of it.')), findsOneWidget);
      // Over the picture, above the question field.
      expect(tester.getTopLeft(card).dy, lessThan(tester.getTopLeft(find.byType(TextField)).dy));

      await tester.tap(find.descendant(of: card, matching: find.byIcon(Icons.close_rounded)));
      await tester.pump();
      expect(find.byType(LiveCommentReplyCard), findsNothing);
      await leave(tester);
    });

    testWidgets('D-186: no banner while nothing is pinned', (tester) async {
      await pumpRoom(tester, <String, FakeResponse>{
        'GET /lives/301': FakeResponse(200, _detail('live', mediaState: 'ready')),
        'POST /lives/301/playback-policy': FakeResponse(200, _policy(mode: 'clear')),
        'POST /lives/301/join': _clearJoin,
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(LivePinnedCommentBanner), findsNothing);
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

    group('iPhone picture not fluid (Live 66, 2026-10-30)', () {
      /// A playing Live [offsetMs] behind its edge.
      Map<String, Object?> at(int ms, int offsetMs) => <String, Object?>{
            'event': 'position',
            'position': ms,
            'duration': 0,
            'buffered': ms + 4000,
            'liveOffset': offsetMs,
          };

      Future<FakeBackend> playing(WidgetTester tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        players.emit(<String, Object?>{'event': 'firstFrame'});
        players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
        players.emit(<String, Object?>{'event': 'playing', 'value': true});
        // The controls hide after 3 s.
        await tester.pump(const Duration(seconds: 4));
        return backend;
      }

      List<String> sent() => <String>[for (final MethodCall c in players.commands[players.lastId] ?? <MethodCall>[]) c.method];

      testWidgets('position reports and the watermark move never rebuild the native picture', (tester) async {
        await playing(tester);
        final ProtectedVideoView picture = tester.widget<ProtectedVideoView>(find.byType(ProtectedVideoView));

        for (int i = 0; i < 15; i++) {
          players.emit(at(30000 + 1000 * i, 6000));
          await tester.pump(const Duration(seconds: 1));
        }
        // The room's 1 s clock rebuilt the header and the watermark moved
        // (every 12 s) meanwhile: the picture's widget stayed the same.
        expect(identical(tester.widget<ProtectedVideoView>(find.byType(ProtectedVideoView)), picture), isTrue);

        // What the overlays show still follows the player.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        players.emit(<String, Object?>{'event': 'playing', 'value': false});
        players.emit(<String, Object?>{'event': 'state', 'state': 'buffering'});
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        players.emit(<String, Object?>{'event': 'tracks', 'heights': <int>[1080, 720]});
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
        expect(identical(tester.widget<ProtectedVideoView>(find.byType(ProtectedVideoView)), picture), isTrue);
        await leave(tester);
      });

      testWidgets('iPhone: one seek back to the edge past 20 s behind, never a repeated jump', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final FakeBackend backend = await playing(tester);
          expect(players.created.single['live'], isTrue);
          for (int i = 0; i < 5; i++) {
            players.emit(at(30000 + 1000 * i, 6000));
            await tester.pump(const Duration(seconds: 1));
          }
          expect(sent(), isNot(contains('seekToLiveEdge')), reason: '6 s behind: left alone');

          // Fell behind after stalls; the seek takes a while to show.
          for (int i = 0; i < 20; i++) {
            players.emit(at(40000 + 1000 * i, 25000));
            await tester.pump(const Duration(seconds: 1));
          }
          expect(sent().where((String m) => m == 'seekToLiveEdge'), hasLength(1));
          expect(sent(), isNot(contains('setSpeed')), reason: 'no speed change, exactly 1.0×');

          // Back near the edge: nothing more.
          for (int i = 0; i < 40; i++) {
            players.emit(at(70000 + 1000 * i, 6000));
            await tester.pump(const Duration(seconds: 1));
          }
          expect(sent().where((String m) => m == 'seekToLiveEdge'), hasLength(1));
          expect(joins(backend), hasLength(1));
          await leave(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('Android keeps its own catch-up: no seek from Flutter', (tester) async {
        await playing(tester);
        for (int i = 0; i < 10; i++) {
          players.emit(at(30000 + 1000 * i, 25000));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(sent(), isNot(contains('seekToLiveEdge')));
        await leave(tester);
      });

      testWidgets('watchdog with one position a second, half a second out of step: loading is progress', (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 700));
        players.emit(<String, Object?>{'event': 'state', 'state': 'buffering'});
        for (int i = 0; i < 25; i++) {
          players.emit(position(14000, buffered: 14000 + 600 * i));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(joins(backend), hasLength(1));

        // Then nothing more arrives: restarted, as before.
        for (int i = 0; i < 12; i++) {
          players.emit(position(14000, buffered: 14000 + 600 * 24));
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pump(const Duration(milliseconds: 200));
        expect(joins(backend), hasLength(2));
        await leave(tester);
      });
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

    group('D-190 (Live 69, 2026-10-31)', () {
      List<String> sent(int id) => <String>[for (final MethodCall c in players.commands[id] ?? const <MethodCall>[]) c.method];

      Future<void> play(WidgetTester tester) async {
        players.emit(<String, Object?>{'event': 'firstFrame'});
        players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
        players.emit(<String, Object?>{'event': 'playing', 'value': true});
        await tester.pump(const Duration(seconds: 1));
      }

      Future<void> behindLiveWindow(WidgetTester tester) async {
        players.emit(<String, Object?>{'event': 'error', 'category': 'behind_live', 'kind': 'other', 'code': 1002});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      testWidgets('1002 behind the live window: back to the live edge in the same player, no new join', (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        await play(tester);
        final int id = players.lastId;

        await behindLiveWindow(tester);
        expect(sent(id), contains('recoverAtLiveEdge'));
        expect(sent(id), isNot(contains('release')));
        expect(joins(backend), hasLength(1), reason: 'no new authorization');
        expect(players.created, hasLength(1), reason: 'no new player');
        expect(find.text('Reconnecting to the live broadcast…'), findsNothing);

        // The recovered player plays on; a later failure is seen again.
        await play(tester);
        await tester.pump(const Duration(seconds: 70));
        await behindLiveWindow(tester);
        expect(sent(id).where((String m) => m == 'recoverAtLiveEdge'), hasLength(2));
        expect(joins(backend), hasLength(1));
        await leave(tester);

        final List<Map<String, dynamic>> jumps =
            telemetry(backend).where((Map<String, dynamic> e) => e['type'] == 'edge_jump').toList();
        expect(jumps, hasLength(2));
        expect(jumps.first['error_code'], 1002);
        expect(jumps.first['attempt'], 1);
        expect(jumps.first['delivery_mode'], 1);
        expect(telemetry(backend).where((Map<String, dynamic> e) => e['type'] == 'reload'), isEmpty);
      });

      testWidgets('two failed edge jumps within 60 s: the third failure gets the full reload', (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        await play(tester);
        final int id = players.lastId;

        await behindLiveWindow(tester);
        await tester.pump(const Duration(seconds: 5));
        await behindLiveWindow(tester);
        await tester.pump(const Duration(seconds: 5));
        expect(sent(id).where((String m) => m == 'recoverAtLiveEdge'), hasLength(2));
        expect(joins(backend), hasLength(1));

        await behindLiveWindow(tester);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 200));
        expect(sent(id).where((String m) => m == 'recoverAtLiveEdge'), hasLength(2));
        expect(joins(backend), hasLength(2));
        expect(players.created, hasLength(2));
        await leave(tester);

        final Map<String, dynamic> reload =
            telemetry(backend).singleWhere((Map<String, dynamic> e) => e['type'] == 'reload');
        expect(reload['error_code'], liveReloadRetryLater);
        expect(reload['error_data_code'], 1002);
      });

      testWidgets('a decoder that keeps failing: three attempts (the first a rendition lower), then the error screen',
          (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        players.emit(<String, Object?>{'event': 'tracks', 'heights': <int>[1080, 720, 480]});
        await tester.pump(const Duration(milliseconds: 100));
        expect(players.created.single['maxHeight'], isNull);

        Future<void> decoderFails() async {
          players.emit(<String, Object?>{'event': 'error', 'category': 'capability', 'kind': 'decoder', 'code': 4001});
          await tester.pump();
          await tester.pump(const Duration(seconds: 6));
          await tester.pump(const Duration(milliseconds: 200));
        }

        await decoderFails();
        expect(joins(backend), hasLength(2));
        expect(players.created[1]['maxHeight'], 720);
        await decoderFails();
        await decoderFails();
        expect(joins(backend), hasLength(4));
        expect(players.created, hasLength(4));

        await decoderFails();
        expect(find.text('This phone cannot decode this video. Try another device, or update the NOVA app.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 60));
        expect(joins(backend), hasLength(4), reason: 'no further automatic retry');
        expect(players.created, hasLength(4));

        final FakeRequest shown = backend.requests.singleWhere((FakeRequest r) => r.path == '/playback-diagnostics');
        expect((shown.data! as Map<String, Object?>)['event'], 'error_shown');
        expect((shown.data! as Map<String, Object?>)['category'], 'decoder');
        expect((shown.data! as Map<String, Object?>)['code'], 4001);
        await leave(tester);

        final List<Map<String, dynamic>> final14 = telemetry(backend)
            .where((Map<String, dynamic> e) => e['type'] == 'error' && e['error_category'] == liveFailureCodes['decoder'])
            .toList();
        expect(final14, hasLength(1));
        expect(final14.single['attempt'], 4);
        expect(final14.single['error_data_code'], 4001);
      });

      testWidgets('network failures are retried as before', (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        await play(tester);
        final int id = players.lastId;
        players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2001});
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 200));
        expect(sent(id), isNot(contains('recoverAtLiveEdge')));
        expect(joins(backend), hasLength(2));
        await leave(tester);
        expect(telemetry(backend).singleWhere((Map<String, dynamic> e) => e['type'] == 'reload')['error_code'],
            liveReloadRetryLater);
      });

      testWidgets('D-195: the Media3 cause of an error goes with it, and only when known', (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        await play(tester);
        players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2000, 'cause': 1});
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 200));
        players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'other', 'code': 2001});
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await leave(tester);
        final List<Map<String, dynamic>> errors =
            telemetry(backend).where((Map<String, dynamic> e) => e['type'] == 'error').toList();
        expect(errors.first['error_data_code'], 2000);
        expect(errors.first['error_cause'], 1);
        expect(errors.last['error_data_code'], 2001);
        expect(errors.last.containsKey('error_cause'), isFalse);
      });
    });

    group('D-192 (2026-10-31)', () {
      List<MethodCall> calls(int id, String method) =>
          <MethodCall>[for (final MethodCall c in players.commands[id] ?? const <MethodCall>[]) if (c.method == method) c];

      Future<void> play(WidgetTester tester) async {
        players.emit(<String, Object?>{'event': 'firstFrame'});
        players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
        players.emit(<String, Object?>{'event': 'playing', 'value': true});
        await tester.pump(const Duration(seconds: 1));
      }

      /// One second of playback as Media3 reports it.
      Future<void> second(WidgetTester tester, int t, {int? bandwidth, int bufferAheadMs = 8000, int height = 480}) async {
        players.emit(<String, Object?>{
          'event': 'position', 'position': t * 1000, 'duration': 0, 'buffered': t * 1000 + bufferAheadMs, 'liveOffset': 12000,
          'bandwidth': bandwidth ?? -1, 'height': height,
        });
        await tester.pump(const Duration(seconds: 1));
      }

      testWidgets('a conservative first estimate goes to the native player and to telemetry', (tester) async {
        AbrStartMemory.reset();
        addTearDown(AbrStartMemory.reset);
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        expect(players.created.single['startBps'], 2200000);
        expect(players.created.single.containsKey('audioOnly'), isFalse);
        await leave(tester);
        expect(telemetry(backend).firstWhere((Map<String, dynamic> e) => e['type'] == 'ready')['startup_bps'], 2200000);
      });

      testWidgets('below 350 kbit/s for 20 s: the sound only in the same player with the banner, then the picture again', (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        await play(tester);
        final int id = players.lastId;
        for (int t = 1; t <= 24; t++) {
          await second(tester, t, bandwidth: 250000, height: 240);
        }
        expect(calls(id, 'setAudioOnly').map((MethodCall c) => c.arguments), <Object?>[<String, Object?>{'on': true}]);
        expect(find.text('Weak connection: sound only'), findsOneWidget);
        expect(joins(backend), hasLength(1), reason: 'no new authorization');
        expect(players.created, hasLength(1), reason: 'no new player');

        for (int t = 25; t <= 48; t++) {
          await second(tester, t, bandwidth: 900000, height: 0);
        }
        expect(calls(id, 'setAudioOnly').map((MethodCall c) => c.arguments),
            <Object?>[<String, Object?>{'on': true}, <String, Object?>{'on': false}]);
        expect(find.text('Weak connection: sound only'), findsNothing);
        await leave(tester);
        final List<Map<String, dynamic>> events = telemetry(backend);
        final Map<String, dynamic> on = events.firstWhere((Map<String, dynamic> e) => e['type'] == 'audio_only_on');
        expect(<Object?>[on['audio_only'], on['bandwidth_bps'], on['attempt'], on['height']], <Object?>[1, 250000, 1, 240]);
        expect(events.firstWhere((Map<String, dynamic> e) => e['type'] == 'audio_only_off')['audio_only'], 0);
      });

      testWidgets('a healthy Live goes 7 s behind the edge, back to 12 s after a stall', (tester) async {
        final FakeBackend backend = await pumpRoom(tester, clearLive());
        await tester.pump(const Duration(milliseconds: 200));
        await play(tester);
        final int id = players.lastId;
        for (int t = 1; t <= 58; t++) {
          await second(tester, t, bandwidth: 4000000);
        }
        expect(calls(id, 'setLiveTargetOffset'), isEmpty);
        for (int t = 59; t <= 64; t++) {
          await second(tester, t, bandwidth: 4000000);
        }
        expect(calls(id, 'setLiveTargetOffset').map((MethodCall c) => c.arguments), <Object?>[<String, Object?>{'ms': 7000}]);
        expect(calls(id, 'seekToLiveEdge'), isEmpty, reason: 'a playback-rate catch-up, never a seek');

        players.emit(<String, Object?>{'event': 'state', 'state': 'buffering'});
        players.emit(<String, Object?>{'event': 'playing', 'value': false});
        await tester.pump(const Duration(seconds: 1));
        players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
        players.emit(<String, Object?>{'event': 'playing', 'value': true});
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls(id, 'setLiveTargetOffset').map((MethodCall c) => c.arguments),
            <Object?>[<String, Object?>{'ms': 7000}, <String, Object?>{'ms': -1}]);
        await leave(tester);
        final List<num> targets = <num>[
          for (final Map<String, dynamic> e in telemetry(backend))
            if (e['type'] == 'latency_target') e['target_latency_s'] as num,
        ];
        expect(targets, <num>[7, 12]);
      });
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

    group('speaking turn: the broadcast is kept muted under the stage (owner decision 2026-10-30)', () {
      /// The clear Live of the apps, with the speaker grant and hand routes.
      Map<String, FakeResponse> speakingLive() => <String, FakeResponse>{
            ...clearLive(),
            'POST /lives/301/speaker': const FakeResponse(200, <String, Object?>{
              'data': <String, String>{'url': 'wss://livekit.test', 'token': 'lk'},
            }),
            'DELETE /lives/301/raise-hand': const FakeResponse(204),
          };

      /// The broadcast plays, then the teaching team accepts the hand
      /// (seen at the next 8 s poll: no realtime in tests).
      Future<FakeBackend> speak(WidgetTester tester, _RoomSpeaker speaker) async {
        final FakeBackend backend = await pumpRoom(tester, speakingLive(), speaker: speaker);
        await tester.pump(const Duration(milliseconds: 200));
        players.emit(<String, Object?>{'event': 'firstFrame'});
        players.emit(<String, Object?>{'event': 'state', 'state': 'ready'});
        players.emit(<String, Object?>{'event': 'playing', 'value': true});
        players.emit(position(30000));
        await tester.pump(const Duration(milliseconds: 100));
        backend.routes['GET /lives/301'] = FakeResponse(200, _detail('live', mediaState: 'ready', hand: 'accepted'));
        await tester.pump(const Duration(seconds: 8));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('You are speaking'), findsOneWidget);
        return backend;
      }

      /// The teaching team removes the speaking Student (owner test, Live 65).
      Future<void> endTurn(WidgetTester tester, FakeBackend backend) async {
        backend.routes['GET /lives/301'] = FakeResponse(200, _detail('live', mediaState: 'ready'));
        await tester.pump(const Duration(seconds: 8));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('You are speaking'), findsNothing);
      }

      List<MethodCall> sent(int id) => players.commands[id] ?? <MethodCall>[];
      List<Object?> volumes(int id) => <Object?>[
            for (final MethodCall c in sent(id))
              if (c.method == 'setVolume') (c.arguments as Map<Object?, Object?>)['volume'],
          ];

      testWidgets('speaking mutes the broadcast without releasing it; its end shows it again without a new join',
          (tester) async {
        final _RoomSpeaker speaker = _RoomSpeaker();
        final FakeBackend backend = await speak(tester, speaker);
        final int id = players.lastId;

        // Muted and hidden under the stage, not disposed: LiveKit is the only voice.
        expect(find.byType(LivePlayer), findsOneWidget);
        expect(volumes(id), <Object?>[0.0]);
        expect(sent(id).map((MethodCall c) => c.method), isNot(contains('release')));

        // A long turn: nothing joins, nothing restarts.
        await tester.pump(const Duration(seconds: 40));
        expect(joins(backend), hasLength(1));
        expect(players.created, hasLength(1));

        // The conversation closes before the broadcast is heard again.
        List<Object?>? volumesAtClose;
        speaker.onClose = () => volumesAtClose = volumes(id);
        await endTurn(tester, backend);
        expect(volumesAtClose, <Object?>[0.0]);
        expect(joins(backend), hasLength(1), reason: 'no new join');
        expect(players.created, hasLength(1), reason: 'the same native player');
        expect(volumes(id), <Object?>[0.0, 1.0]);
        final List<String> methods = sent(id).map((MethodCall c) => c.method).toList();
        expect(methods.last, 'play');
        // 14 s behind the edge: shown where it is, no seek.
        expect(methods, isNot(contains('seekToLiveEdge')));
        expect(methods, isNot(contains('release')));
        await leave(tester);
      });

      testWidgets('a broadcast that fails during the turn is released, and the end starts a fresh one', (tester) async {
        final _RoomSpeaker speaker = _RoomSpeaker();
        final FakeBackend backend = await speak(tester, speaker);
        final int id = players.lastId;

        players.emit(<String, Object?>{'event': 'error', 'category': 'delivery', 'kind': 'network', 'code': 2001});
        await tester.pump(const Duration(seconds: 30));
        expect(sent(id).map((MethodCall c) => c.method), contains('release'));
        expect(joins(backend), hasLength(1), reason: 'no join while the Student speaks');
        expect(players.created, hasLength(1));
        expect(find.text('You are speaking'), findsOneWidget);

        await endTurn(tester, backend);
        expect(joins(backend), hasLength(2));
        expect(players.created, hasLength(2));
        await leave(tester);
      });

      testWidgets('the app going to the background during the turn releases the broadcast; the end starts a fresh one',
          (tester) async {
        final _RoomSpeaker speaker = _RoomSpeaker();
        final FakeBackend backend = await speak(tester, speaker);
        final int id = players.lastId;

        // Only valid transitions: to the background, then back.
        for (final AppLifecycleState state in <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump(const Duration(milliseconds: 100));
        expect(sent(id).map((MethodCall c) => c.method), contains('release'));
        for (final AppLifecycleState state in <AppLifecycleState>[
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump(const Duration(milliseconds: 100));
        expect(joins(backend), hasLength(1));

        await endTurn(tester, backend);
        expect(joins(backend), hasLength(2));
        expect(players.created, hasLength(2));
        await leave(tester);
      });

      testWidgets('removed by the team in LiveKit: the stage closes, no reconnect, no new grant (Live 66)', (tester) async {
        final _RoomSpeaker speaker = _RoomSpeaker();
        final FakeBackend backend = await speak(tester, speaker);
        final int id = players.lastId;
        bool closed = false;
        speaker.onClose = () => closed = true;

        // The team removed the Student: the server ended the hand, and
        // LiveKit says "participant removed" before any realtime event.
        backend.routes['GET /lives/301'] = FakeResponse(200, _detail('live', mediaState: 'ready'));
        await speaker.disconnected(DisconnectReason.participantRemoved);
        await tester.pump(const Duration(milliseconds: 100));
        expect(closed, isTrue);
        expect(find.text('You are speaking'), findsNothing);
        expect(volumes(id), <Object?>[0.0, 1.0], reason: 'the broadcast is heard again');

        await tester.pump(const Duration(seconds: 10));
        Iterable<FakeRequest> calls(String method, String path) =>
            backend.requests.where((FakeRequest r) => r.method == method && r.path == path);
        expect(calls('POST', '/lives/301/speaker'), hasLength(1), reason: 'no new speaker grant');
        expect(calls('DELETE', '/lives/301/raise-hand'), isEmpty, reason: 'the team already ended the turn');
        expect(find.text('You are speaking'), findsNothing);
        await leave(tester);
      });

      testWidgets('a turn that ends while the conversation connects is closed and never shown (Live 66)', (tester) async {
        final _RoomSpeaker speaker = _RoomSpeaker()..connection = Completer<void>();
        bool closed = false;
        speaker.onClose = () => closed = true;
        final FakeBackend backend = await pumpRoom(tester, speakingLive(), speaker: speaker);
        await tester.pump(const Duration(milliseconds: 200));
        backend.routes['GET /lives/301'] = FakeResponse(200, _detail('live', mediaState: 'ready', hand: 'accepted'));
        await tester.pump(const Duration(seconds: 8));
        await tester.pump(const Duration(milliseconds: 100));
        expect(closed, isFalse);

        // The team ends the turn before LiveKit connected.
        backend.routes['GET /lives/301'] = FakeResponse(200, _detail('live', mediaState: 'ready'));
        await tester.pump(const Duration(seconds: 8));
        await tester.pump(const Duration(milliseconds: 100));
        expect(closed, isTrue);

        speaker.connection!.complete();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('You are speaking'), findsNothing);
        expect(backend.requests.where((FakeRequest r) => r.method == 'POST' && r.path == '/lives/301/speaker'), hasLength(1));
        await leave(tester);
      });

      testWidgets('a weak downlink pauses the hidden broadcast; the end brings it back at the live edge', (tester) async {
        final _RoomSpeaker speaker = _RoomSpeaker();
        final FakeBackend backend = await speak(tester, speaker);
        final int id = players.lastId;

        speaker.setDownlinkWeak(true);
        await tester.pump(const Duration(milliseconds: 100));
        expect(sent(id).map((MethodCall c) => c.method), contains('pause'));
        // Paused on purpose: not a stall, not restarted; paused for the whole turn.
        speaker.setDownlinkWeak(false);
        await tester.pump(const Duration(seconds: 40));
        expect(sent(id).where((MethodCall c) => c.method == 'play'), isEmpty);
        expect(joins(backend), hasLength(1));
        expect(players.created, hasLength(1));

        await endTurn(tester, backend);
        expect(joins(backend), hasLength(1));
        final List<String> methods = sent(id).map((MethodCall c) => c.method).toList();
        expect(methods.sublist(methods.length - 3), <String>['setVolume', 'seekToLiveEdge', 'play']);
        expect(volumes(id).last, 1.0);
        await leave(tester);
      });
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

/// A speaker whose LiveKit connections are counted, not made: the real
/// disconnection rules run.
class _LinkSpeaker extends LiveSpeaker {
  _LinkSpeaker(VoidCallback onDropped) : super(onDropped: onDropped);

  int opens = 0;

  @override
  Future<void> open(SpeakerGrant grant) async => opens++;
}

/// The accepted Student's speaker in the room tests: no LiveKit room; the
/// test says when the server paused the Professor's camera.
class _RoomSpeaker extends LiveSpeaker {
  _RoomSpeaker() : super(onDropped: () {});

  bool _weak = false;

  /// Called when the room closes the conversation.
  VoidCallback? onClose;

  /// Set: the connection completes only when the test says so.
  Completer<void>? connection;

  @override
  Future<void> connect(SpeakerGrant grant) async => connection?.future;

  @override
  Future<void> close() {
    onClose?.call();
    return super.close();
  }

  @override
  bool get downlinkWeak => _weak;

  void setDownlinkWeak(bool weak) {
    _weak = weak;
    changes.value++;
  }
}
