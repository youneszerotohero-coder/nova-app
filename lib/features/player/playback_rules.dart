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

/// What a failing Live player does next (D-190, Live 69 study).
enum LiveFailureAction {
  /// Back to the live edge in place: same player, same source and DRM
  /// session, no new authorization or playback session.
  edgeJump,

  /// A decoder failure with automatic attempts left: today's handling
  /// (clear stream in mode B, a fresh player on the clear stream).
  decoderRetry,

  /// A decoder failure past its automatic attempts: the error screen.
  decoderGiveUp,

  /// Anything else, network failures included: today's handling.
  usual,
}

/// D-190 (Live 69, 2026-10-31: 26 % of app Students hit Media3 1002
/// `ERROR_CODE_BEHIND_LIVE_WINDOW` after a network stall, each answered by a
/// full reload; two phones looped 282 times on 4001
/// `ERROR_CODE_DECODER_INIT_FAILED`).
///
/// * Behind the live window (Android Media3 1002 only: AVPlayer and Shaka
///   have no such fatal error): jump back to the live edge in place; only
///   when that in-place recovery failed twice within [edgeWindow] does the
///   next one get today's full reload.
/// * Decoder failures (only the codes in [androidDecoderCodes] /
///   [iosDecoderCodes]): at most [decoderAttempts] automatic attempts, the
///   first one a rendition lower ([lowerDecodeHeight]); the next failure
///   shows the error screen, without further automatic retries. After
///   [decoderRecovered] of continuous playback, a later decoder failure gets
///   fresh attempts.
/// * Network failures and everything else: unchanged.
///
/// Times are the caller's clock (the time since the player opened), so the
/// rule is the same on a phone and under fake timers.
class LiveRecovery {
  static const Duration edgeWindow = Duration(seconds: 60);
  static const int edgeJumpsPerWindow = 2;
  static const int decoderAttempts = 3;
  static const Duration decoderRecovered = Duration(minutes: 2);

  /// Media3 `PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW`.
  static const int androidBehindLiveWindow = 1002;

  /// Media3 4001 `DECODER_INIT_FAILED`, 4002 `DECODER_QUERY_FAILED`, 4003
  /// `DECODING_FAILED`, 4004 `DECODING_FORMAT_EXCEEDS_CAPABILITIES`, 4005
  /// `DECODING_FORMAT_UNSUPPORTED`.
  static const Set<int> androidDecoderCodes = <int>{4001, 4002, 4003, 4004, 4005};

  /// AVFoundation `AVError` -11821 `decodeFailed`, -11833
  /// `decoderNotFound`, -11839 `decoderTemporarilyUnavailable` (the codes
  /// `ClearPlayerView` reports as `decoder`).
  static const Set<int> iosDecoderCodes = <int>{-11821, -11833, -11839};

  final List<Duration> _edgeJumps = <Duration>[];
  Duration? _playingSince;

  /// Decoder failures since the Live last played [decoderRecovered] in a row.
  int decoderFailures = 0;

  /// In-place edge jumps within the last [edgeWindow].
  int get edgeJumps => _edgeJumps.length;

  static bool behindLiveWindow({required String? category, required int code, TargetPlatform? platform}) =>
      (platform ?? defaultTargetPlatform) == TargetPlatform.android &&
      category == 'behind_live' &&
      code == androidBehindLiveWindow;

  static bool decoderFailure({required String? kind, required int code, TargetPlatform? platform}) {
    if (kind != 'decoder') return false;
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android => androidDecoderCodes.contains(code),
      TargetPlatform.iOS => iosDecoderCodes.contains(code),
      _ => false,
    };
  }

  /// The next step after a native failure observed at [now].
  LiveFailureAction decide({
    required String? category,
    required String? kind,
    required int code,
    required Duration now,
    TargetPlatform? platform,
  }) {
    if (behindLiveWindow(category: category, code: code, platform: platform)) {
      _edgeJumps.removeWhere((Duration at) => now - at >= edgeWindow);
      if (_edgeJumps.length < edgeJumpsPerWindow) {
        _edgeJumps.add(now);
        return LiveFailureAction.edgeJump;
      }
      // The full reload starts a new player: its own edge jumps later.
      _edgeJumps.clear();
      return LiveFailureAction.usual;
    }
    if (decoderFailure(kind: kind, code: code, platform: platform)) {
      decoderFailures++;
      return decoderFailures > decoderAttempts ? LiveFailureAction.decoderGiveUp : LiveFailureAction.decoderRetry;
    }
    return LiveFailureAction.usual;
  }

  /// One playback observation: [decoderRecovered] of continuous playback
  /// clears the decoder failures.
  void observe({required bool playing, required Duration now}) {
    if (!playing) {
      _playingSince = null;
      return;
    }
    final Duration since = _playingSince ??= now;
    if (now - since >= decoderRecovered) decoderFailures = 0;
  }

  /// The Student pressed "Try again" on the decoder error: one more
  /// attempt, and the next decoder failure shows the error again.
  void retriedByStudent() {
    if (decoderFailures > decoderAttempts) decoderFailures = decoderAttempts;
  }
}

/// The first decoder retry asks for one rendition lower (web decode guard,
/// D-116): the highest of [heights] (highest first) below [current], or
/// below the highest rendition when no cap is set yet; null when there is
/// no lower rendition (the cap stays as it was).
int? lowerDecodeHeight(List<int> heights, {int? current}) {
  final List<int> sorted = <int>[...heights.where((int h) => h > 0)]..sort((int a, int b) => b.compareTo(a));
  if (sorted.isEmpty) return current;
  final int top = current ?? sorted.first;
  for (final int height in sorted) {
    if (height < top) return height;
  }
  return current;
}

/// D-192 G (owner approval 2026-10-31 « B jusqu'à K »): the first
/// bandwidth estimate of the Android player (Media3 `DefaultBandwidthMeter`).
/// Media3 picks the highest rendition whose bitrate fits 70 % of it: without
/// a measurement 2.2 Mbit/s lands on 480p on both Live ladders (clear HLS
/// 480p peak 1.33, 720p 2.47 Mbit/s; DASH video 480p ≤ 1.2, 720p ≥ 1.8) and
/// on the Lessons' 1080/720/480 ladder, instead of the country/network
/// default of Media3. A link measured earlier in this app session starts
/// from 80 % of it, between 0.7 Mbit/s (the 240p Live rung) and 8 Mbit/s.
class AbrStartMemory {
  AbrStartMemory._();

  static const int defaultBps = 2200000;
  static const int minBps = 700000;
  static const int maxBps = 8000000;
  static const double rememberedShare = 0.8;

  static int? _remembered;

  /// The estimate the next native player starts from.
  static int startBps() {
    final int? remembered = _remembered;
    if (remembered == null) return defaultBps;
    return (remembered * rememberedShare).round().clamp(minBps, maxBps);
  }

  /// A measured estimate of the native player (Media3 only reports measured ones).
  static void remember(int? bps) {
    if (bps != null && bps > 0) _remembered = bps;
  }

  @visibleForTesting
  static void reset() => _remembered = null;
}

/// D-192 F: what the sound-only fallback decides.
enum AudioOnlyDecision { enter, leave }

/// D-192 F (owner approval 2026-10-31): the app Live's automatic sound-only
/// fallback, same rules as the website (`live-audio-only.ts`). Below
/// 350 kbit/s no video rung fits (240p ≈ 320 kbit/s plus the sound): enter
/// when the measured estimate stayed below [enterBps] for [lowFor] (at
/// least [minLowSamples] samples), or after [stallsToEnter] stalls within
/// [stallWindow] on the lowest rung of a ladder; leave at a check every
/// [checkEvery], once the hold is over, when the estimate reaches
/// [returnBps] with no stall since the previous check. A new entry within
/// [repeatWindow] of the last return doubles the hold, up to [maxHold].
class LiveAudioOnly {
  static const bool enabled = true;
  static const int enterBps = 350000;
  static const Duration lowFor = Duration(seconds: 20);
  static const int minLowSamples = 3;
  static const int stallsToEnter = 2;
  static const Duration stallWindow = Duration(seconds: 60);
  static const Duration stallMin = Duration(milliseconds: 500);
  static const int returnBps = 700000;
  static const Duration checkEvery = Duration(seconds: 20);
  static const Duration minHold = Duration(seconds: 20);
  static const Duration maxHold = Duration(minutes: 5);
  static const Duration repeatWindow = Duration(minutes: 5);

  bool on = false;

  /// `bandwidth` or `stalls` while [on] (telemetry `audio_only` 1 or 2).
  String? reason;

  /// Entries in this Live (telemetry `attempt`).
  int entries = 0;
  Duration hold = minHold;

  Duration? _lowSince;
  int _lowSamples = 0;
  List<Duration> _stalls = <Duration>[];
  Duration _enteredAt = Duration.zero;
  Duration _lastCheckAt = Duration.zero;
  Duration? _leftAt;

  AudioOnlyDecision _enter(Duration now, String why) {
    final Duration? left = _leftAt;
    final bool repeated = left != null && now - left < repeatWindow;
    hold = repeated ? Duration(milliseconds: min(maxHold.inMilliseconds, hold.inMilliseconds * 2)) : minHold;
    on = true;
    reason = why;
    _enteredAt = now;
    _lastCheckAt = now;
    _lowSince = null;
    _lowSamples = 0;
    _stalls = <Duration>[];
    entries++;
    return AudioOnlyDecision.enter;
  }

  /// A periodic sample: the measured estimate (null before any) while the
  /// player is meant to play.
  AudioOnlyDecision? observe({required Duration now, required int? bandwidthBps, required bool playing}) {
    if (!on) {
      if (!playing || bandwidthBps == null) return null;
      if (bandwidthBps >= enterBps) {
        _lowSince = null;
        _lowSamples = 0;
        return null;
      }
      final Duration since = _lowSince ??= now;
      _lowSamples++;
      return now - since >= lowFor && _lowSamples >= minLowSamples ? _enter(now, 'bandwidth') : null;
    }
    if (now - _lastCheckAt < checkEvery || now - _enteredAt < hold) return null;
    _lastCheckAt = now;
    final bool calm = _stalls.isEmpty;
    _stalls = <Duration>[];
    if (!playing || !calm || bandwidthBps == null || bandwidthBps < returnBps) return null;
    on = false;
    reason = null;
    _leftAt = now;
    return AudioOnlyDecision.leave;
  }

  /// A stall of [duration] ended; [lowestRung]: on the lowest rendition of a
  /// ladder ([onLowestRung]).
  AudioOnlyDecision? stall({required Duration now, required Duration duration, required bool lowestRung}) {
    if (duration <= stallMin) return null;
    if (on) {
      _stalls.add(now);
      return null;
    }
    if (!lowestRung) {
      _stalls = <Duration>[];
      return null;
    }
    _stalls = <Duration>[..._stalls.where((Duration at) => now - at < stallWindow), now];
    return _stalls.length >= stallsToEnter ? _enter(now, 'stalls') : null;
  }
}

/// True when [current] is the lowest of at least two video [heights].
bool onLowestRung(List<int> heights, int? current) {
  final List<int> ladder = heights.where((int h) => h > 0).toSet().toList();
  return ladder.length > 1 && current != null && current > 0 && current == ladder.reduce(min);
}

/// D-192 H: the target distance behind the live edge of the Android player.
enum LiveLatencyMode { normal, low }

/// D-192 H (owner approval 2026-10-31): adaptive Live latency per Student on
/// Android (Media3 `setTargetLiveOffsetOverrideUs`; iPhone and the PC app
/// keep today's behaviour). Normal: the MediaItem's 12 s target with
/// Media3's catch-up up to 1.08×. After [lowAfter] of playback with at least
/// [healthyBuffer] buffered and no stall, the target becomes [lowOffset]
/// (Media3 reaches it by playing up to 1.08×, never by a seek). Any stall
/// there goes back to 12 s at once (Media3 never slows below 1×, so the
/// stall itself and Media3's own +0.5 s per rebuffer rebuild the margin),
/// and the next try waits [retryBase], doubled after each failed try up to
/// [retryMax]; [resetAfter] close without a stall forgets the failures.
/// A fresh native player starts at 12 s and counts as a stall.
class LiveLatencyTarget {
  static const bool enabled = true;
  static const Duration normalOffset = Duration(seconds: 12);
  static const Duration lowOffset = Duration(seconds: 7);
  static const Duration lowAfter = Duration(seconds: 60);
  static const Duration healthyBuffer = Duration(seconds: 4);
  static const Duration stallMin = Duration(milliseconds: 500);
  static const Duration retryBase = Duration(minutes: 2);
  static const Duration retryMax = Duration(minutes: 16);
  static const Duration resetAfter = Duration(minutes: 10);

  LiveLatencyMode mode = LiveLatencyMode.normal;
  int failures = 0;
  Duration? _healthySince;
  Duration _nextTryAt = Duration.zero;
  Duration _lowSince = Duration.zero;

  /// The target of [mode] behind the live edge (telemetry `target_latency_s`).
  Duration get target => mode == LiveLatencyMode.low ? lowOffset : normalOffset;

  LiveLatencyMode observe({required Duration now, required bool playing, required Duration bufferAhead, required Duration? liveOffset}) {
    if (!playing) {
      _healthySince = null;
      return mode;
    }
    if (mode == LiveLatencyMode.low) {
      if (failures > 0 && now - _lowSince >= resetAfter) failures = 0;
      return mode;
    }
    if (bufferAhead < healthyBuffer) {
      _healthySince = null;
      return mode;
    }
    final Duration since = _healthySince ??= now;
    if (now - since >= lowAfter && now >= _nextTryAt && liveOffset != null) {
      mode = LiveLatencyMode.low;
      _lowSince = now;
    }
    return mode;
  }

  /// A stall of [duration] ended (a fresh native player: [Duration] of a day).
  LiveLatencyMode stall({required Duration now, required Duration duration}) {
    if (duration <= stallMin) return mode;
    _healthySince = null;
    if (mode == LiveLatencyMode.low) {
      failures++;
      final int wait = retryBase.inMilliseconds * (1 << min(failures - 1, 20));
      _nextTryAt = now + Duration(milliseconds: min(retryMax.inMilliseconds, wait));
      mode = LiveLatencyMode.normal;
    }
    return mode;
  }
}
