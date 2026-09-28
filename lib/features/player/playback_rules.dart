import 'dart:math';

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

/// The server already resets finished lessons to 0; the client also
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
