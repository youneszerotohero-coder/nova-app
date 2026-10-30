import 'dart:math';

import 'package:flutter/foundation.dart';

/// Playback rules shared with the web player
/// (website-front `components/protected-video-player.tsx`), kept pure so
/// they are unit-tested without a device.

/// Decides when the playhead is reported to `PUT /lessons/{id}/progress`:
/// after 15 s of movement either way, and always on pause, end or exit.
class ProgressReporter {
  ProgressReporter({int initialSeconds = 0}) : _lastSaved = initialSeconds;

  static const int step = 15;

  int _lastSaved;
  int get lastSaved => _lastSaved;

  /// True when [seconds] has moved far enough to be worth saving.
  bool due(int seconds) => (seconds - _lastSaved).abs() >= step;

  void saved(int seconds) => _lastSaved = seconds;
}

/// The server's resume is the last second seen (D-134); the client also
/// refuses to resume inside the last few seconds, where playback would
/// end before it starts: `min(5, max(3, duration × 10 %))`.
int safeResumeSeconds(int resume, double duration) {
  if (duration <= 0 || resume <= 0) return 0;
  final double tail = min(5, max(3, duration * 0.1));
  return resume >= duration - tail ? 0 : resume;
}

/// Manifest and server durations must agree within 2 s, otherwise the
/// media is not the one that was authorized (web: `decode` failure).
bool durationMatches(double server, double manifest) =>
    manifest <= 0 || (server - manifest).abs() <= 2;

/// Where the watermark sits next, as fractions of the video box: top
/// 12–67 %, left or right side, 4–14 % in from that side.
class WatermarkSpot {
  const WatermarkSpot({required this.top, required this.inset, required this.right});

  final double top;
  final double inset;
  final bool right;
}

class WatermarkPlacer {
  WatermarkPlacer({Random? random}) : _random = random ?? Random();

  final Random _random;
  int _rotation = 0;

  /// Rotation counter shown after the session reference, base-36.
  String get rotationTag => _rotation.toRadixString(36).padLeft(2, '0').toUpperCase();

  WatermarkSpot next() {
    _rotation = (_rotation + 1) % (36 * 36);
    return WatermarkSpot(
      top: 0.12 + _random.nextDouble() * 0.55,
      inset: 0.04 + _random.nextDouble() * 0.10,
      right: _random.nextBool(),
    );
  }

  /// 10–18 s normally; 6–10 s under software DRM, which is easier to
  /// capture.
  Duration interval({required bool softwareFallback}) => softwareFallback
      ? Duration(milliseconds: 6000 + _random.nextInt(4000))
      : Duration(milliseconds: 10000 + _random.nextInt(8000));
}

String clockLabel(Duration value) {
  final int total = value.inSeconds.clamp(0, 1 << 30);
  final int h = total ~/ 3600;
  final int m = (total % 3600) ~/ 60;
  final String s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Wait before retrying a Live whose media is not ready yet (409
/// `LIVE_PROTECTED_MEDIA_NOT_READY`): 2, 3, 4, 5, 6 then 8 s, each ±15 %
/// so a classroom does not retry in lockstep (web live player). Past
/// 180 s without the server reporting the media as preparing or
/// recovering, the Student keeps waiting at 15 s instead of facing a
/// dead end (D-071).
Duration notReadyDelay(
  int attempt,
  Random random, {
  Duration waited = Duration.zero,
  String? mediaState,
}) {
  const List<int> steps = <int>[2, 3, 4, 5, 6, 8];
  final bool preparing = mediaState == 'preparing' || mediaState == 'recovering';
  final int seconds = !preparing && waited >= liveNotReadyBudget
      ? liveRetryCeiling.inSeconds
      : steps[attempt.clamp(0, steps.length - 1)];
  final double jitter = 0.85 + random.nextDouble() * 0.30;
  return Duration(milliseconds: (seconds * 1000 * jitter).round());
}

const Duration liveNotReadyBudget = Duration(seconds: 180);

/// The longest wait between two retries of a Live (D-071).
const Duration liveRetryCeiling = Duration(seconds: 15);

/// Transient Live failures (server busy, throttled, 5xx, network,
/// delivery) are retried forever: 1, 2, 4, 8 then 15 s, each ×0.8–1.2
/// (web `retryLater`), so an incident is not answered by a request storm.
Duration liveRetryDelay(int attempt, Random random) {
  final int exponent = (attempt - 1).clamp(0, 4);
  final int ms = min(liveRetryCeiling.inMilliseconds, 1000 * (1 << exponent));
  return Duration(milliseconds: (ms * (0.8 + random.nextDouble() * 0.4)).round());
}

/// D-070 mode B memory for this app session (web `rememberClearDelivery`
/// and `liveClearPreferred`): once DRM could not play on this device,
/// later videos and Lives go straight to the clear copy instead of failing
/// again on every screen. An app restart tries DRM again.
class ClearDeliveryMemory {
  ClearDeliveryMemory._();

  /// Why videos (Lessons, Replays) use the clear copy:
  /// `no_drm` or `drm_error`; null = DRM first. A protected copy that
  /// could not be fetched (`media_unavailable`) concerns one video and is
  /// never remembered.
  static String? video;

  /// Lives start on the clear stream.
  static bool live = false;

  /// The Admin's Videos switch as last learnt from the server
  /// (`drm_only`, `drm_with_clear_fallback`, `clear`); null = unknown.
  static String? videoMode;

  /// Player texts may speak of protection only in a known mode A (D-077).
  static bool get videoNeutral => videoMode != 'drm_only';

  static void reset() {
    video = null;
    live = false;
    videoMode = null;
  }
}

/// Modes B and C: nothing the Student reads speaks of protection (D-077).
bool isClearWording(String? mode) => mode == 'drm_with_clear_fallback' || mode == 'clear';

/// Failures that are not the protected playback's own: the clear copy
/// would stop the same way, so they are shown as they are.
const Set<String> noClearFallback = <String>{
  'access',
  'session_expired',
  'processing',
  'clear_unavailable',
  'rate',
};

/// D-077 (amends D-070): in mode B every failure of the protected attempt
/// switches to the clear copy — `no_drm` when the device has no usable
/// DRM, `media_unavailable` when the protected media could not be fetched
/// (network, timeout, e.g. missing on the CDN), `drm_error` for anything
/// else (licence, output/HDCP, decoder, unclassified, a picture that never
/// starts). Only a refused authorization is shown (web `clearFallbackReason`).
String? clearFallbackReason(String category, {bool capability = false}) {
  if (noClearFallback.contains(category)) return null;
  if (capability || const <String>{'ios_blocked', 'security'}.contains(category)) return 'no_drm';
  if (category == 'timeout' || category == 'delivery') return 'media_unavailable';
  return 'drm_error';
}

/// Owner decision 2026-10-30: a Lesson (or a past Live, D-132) cut by a
/// transient network failure resumes by itself at the same second, with a
/// fresh authorization (a new playback session before any progress is
/// saved, freshly signed media URLs): up to three attempts after 2, 5 and
/// 10 s under a "Reconnecting…" notice, then the usual error screen.
///
/// Only network and timeout failures of the media download qualify, read
/// from the native player's own code:
/// * Android (Media3): 2000 `IO_UNSPECIFIED`, 2001
///   `IO_NETWORK_CONNECTION_FAILED`, 2002 `IO_NETWORK_CONNECTION_TIMEOUT`,
///   2004 `IO_BAD_HTTP_STATUS` (a CDN 5xx, or a signed URL that expired);
/// * iPhone (AVFoundation, `NSURLErrorDomain`): -1001 timed out, -1003
///   host not found, -1004 cannot connect, -1005 connection lost, -1006
///   DNS failure, -1009 offline, -1011 bad server response;
/// * PC app (Shaka): 1001 `BAD_HTTP_STATUS`, 1002 `HTTP_ERROR`, 1003
///   `TIMEOUT`.
/// Never a DRM or licence failure (`kind` `drm`, even a licence request
/// that timed out), a decoder, capability or output failure, an expired
/// session or a withdrawn access: those keep today's handling. A failed
/// re-authorization counts as a further attempt only when the request
/// never reached the server (no network).
class VideoAutoResume {
  VideoAutoResume._();

  static const List<Duration> delays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// After this much playback past the second it resumed at, a later cut
  /// gets three fresh attempts.
  static const Duration recovered = Duration(seconds: 30);

  static const Set<int> androidCodes = <int>{2000, 2001, 2002, 2004};
  static const Set<int> iosCodes = <int>{-1001, -1003, -1004, -1005, -1006, -1009, -1011};
  static const Set<int> windowsCodes = <int>{1001, 1002, 1003};

  /// The wait before automatic attempt [done] + 1, or null once the three
  /// attempts are spent.
  static Duration? delay(int done) => done >= 0 && done < delays.length ? delays[done] : null;

  /// True when the native player's failure ([category], [kind] and [code]
  /// as the native player reported them) is a transient network failure.
  static bool qualifies({
    required String? category,
    required String? kind,
    required int code,
    TargetPlatform? platform,
  }) {
    if (category != 'delivery' && category != 'timeout') return false;
    if (kind == 'drm' || kind == 'decoder') return false;
    final Set<int> codes = switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android => androidCodes,
      TargetPlatform.iOS => iosCodes,
      TargetPlatform.windows => windowsCodes,
      _ => const <int>{},
    };
    return codes.contains(code);
  }
}

/// Watches a protected picture that never starts although media is
/// buffered (secure decoder or output path stuck), which D-077 treats as a
/// DRM failure: 12 s without a frame or progress while ≥ 2 s are buffered;
/// gives up after 45 s (web `watchProtectedStart`).
class ProtectedStartWatch {
  static const Duration timeout = Duration(seconds: 12);
  static const Duration giveUp = Duration(seconds: 45);
  static const Duration minBuffered = Duration(seconds: 2);

  /// True when the playback should leave DRM.
  static bool stuck({
    required Duration elapsed,
    required bool firstFrame,
    required Duration start,
    required Duration position,
    required Duration buffered,
  }) =>
      elapsed >= timeout &&
      elapsed <= giveUp &&
      !firstFrame &&
      position - start <= const Duration(milliseconds: 500) &&
      buffered - position >= minBuffered;
}

/// A Live player that never starts, or stops for good, although the server
/// says its media is ready. The native players report hard errors only: a
/// player stuck loading (Media3 `STATE_BUFFERING`, AVPlayer
/// `waitingToPlayAtSpecifiedRate`) waits forever, which Students fixed by
/// leaving and opening the Live again. Progress is a playing picture or
/// media loaded ahead of the playhead (a playhead that only jumps is a
/// seek, not playback). The player is restarted with a fresh authorization
/// (web 8 s first-frame watchdog) when, before it first plays, nothing
/// progressed for [startTimeout] (10 s, then 15, 20 and 30 s for the next
/// restarts, so a slow link still gets its chance) or it loaded without
/// playing for three times as long; once it played, after [stallTimeout]
/// without progress. Times come from the caller's ticks, so the rule is the
/// same on a phone and under fake timers.
class LivePlaybackWatch {
  static const List<int> _startSeconds = <int>[10, 15, 20, 30];
  static const Duration stallTimeout = Duration(seconds: 20);

  /// Below this, more media ahead is jitter, not loading.
  static const Duration _loaded = Duration(milliseconds: 500);

  static Duration startTimeout(int restarts) =>
      Duration(seconds: _startSeconds[restarts.clamp(0, _startSeconds.length - 1)]);

  Duration _now = Duration.zero;
  Duration _lastProgress = Duration.zero;
  Duration _expectedSince = Duration.zero;
  Duration? _ahead;

  /// This player has played (a moving picture, not only a first frame).
  bool played = false;

  /// One observation per tick. [expected]: the player is meant to play
  /// (not paused by the Student, the app leaving the screen or a capture,
  /// and the server reports its media ready); otherwise the clocks restart.
  void observe({
    required Duration elapsed,
    required bool expected,
    required bool playing,
    required Duration position,
    required Duration buffered,
  }) {
    _now = elapsed;
    // Media ahead of the playhead, not the buffered end: on Android both
    // move back when the live window slides.
    final Duration ahead = buffered - position;
    final bool loaded = _ahead != null && ahead - _ahead! >= _loaded;
    if (playing) played = true;
    if (!expected) _expectedSince = elapsed;
    if (!expected || playing || loaded) _lastProgress = elapsed;
    _ahead = ahead;
  }

  /// Time without progress so far.
  Duration get idle => _now - _lastProgress;

  /// True when the player should be restarted; [restarts] counts the
  /// watchdog restarts since the Live last played.
  bool stuck({required int restarts}) {
    if (played) return idle >= stallTimeout;
    final Duration timeout = startTimeout(restarts);
    return idle >= timeout || _now - _expectedSince >= timeout * 3;
  }
}

/// The native player's state as an HTMLMediaElement `readyState`
/// (telemetry `ready_state`, as the website reports it): 0 nothing loaded,
/// 1 loading without a picture, 2 a picture but not enough to play, 3 ready
/// but not playing, 4 playing.
int liveReadyState({required String phase, required bool firstFrame, required bool playing}) {
  if (playing) return 4;
  return switch (phase) {
    'ready' => 3,
    'buffering' => firstFrame ? 2 : 1,
    _ => 0,
  };
}

/// Android follows the Live 12 s behind its edge (D-065) and catches up by
/// itself at up to 1.08×; the iPhone follows it 6 s behind at exactly 1.0×
/// (2026-10-30). Past this distance a Live has drifted: the broadcast kept
/// during a speaking turn, or an iPhone that fell behind after stalls.
const Duration liveReturnDriftLimit = Duration(seconds: 20);

/// At most one drift seek per this period: the seek takes a moment to show
/// in the reported distance, and a Live never jumps repeatedly.
const Duration liveDriftSeekEvery = Duration(seconds: 30);

/// iPhone (2026-10-30, picture not fluid): a playing Live more than
/// [liveReturnDriftLimit] behind its edge goes back to it with one seek, a
/// rare event, instead of AVPlayer's automatic catch-up. [sinceLastSeek] is
/// null before the first one.
bool liveDriftNeedsSeek({
  required bool playing,
  required Duration? liveOffset,
  Duration? sinceLastSeek,
}) =>
    playing &&
    liveOffset != null &&
    liveOffset > liveReturnDriftLimit &&
    (sinceLastSeek == null || sinceLastSeek >= liveDriftSeekEvery);

/// When a speaking turn ends (owner decision 2026-10-30), the kept
/// broadcast is shown again where it is, unless it drifted: not playing
/// (paused for a weak downlink, stalled), an unknown distance from the
/// edge, or more than [liveReturnDriftLimit] behind it. Then it goes back
/// to the live edge first.
bool liveReturnNeedsEdge({required bool playing, required Duration? liveOffset}) =>
    !playing || liveOffset == null || liveOffset > liveReturnDriftLimit;

/// Renewal failures retry after 15 s × failures, at most 60 s.
Duration renewalRetryDelay(int failures) =>
    Duration(seconds: (15 * failures).clamp(15, 60));

/// The live watermark's eight fixed stops, cycled every 12 s
/// (web `live-watermark.tsx`): corners at 10 % and 72 %, sides at 27 %,
/// centre at 42 % and 58 %.
const List<WatermarkSpot> liveWatermarkSpots = <WatermarkSpot>[
  WatermarkSpot(top: 0.10, inset: 0.05, right: false),
  WatermarkSpot(top: 0.10, inset: 0.05, right: true),
  WatermarkSpot(top: 0.72, inset: 0.05, right: true),
  WatermarkSpot(top: 0.72, inset: 0.05, right: false),
  WatermarkSpot(top: 0.27, inset: 0.05, right: false),
  WatermarkSpot(top: 0.27, inset: 0.05, right: true),
  WatermarkSpot(top: 0.42, inset: 0.30, right: false),
  WatermarkSpot(top: 0.58, inset: 0.30, right: true),
];
