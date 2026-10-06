import 'dart:async';
import 'dart:math';

import '../core/api/nova_api.dart';
import 'json.dart';
import 'models.dart';
import 'playback_models.dart';

/// `GET /lives/{id}`: the session plus the Student's own hand state.
class LiveDetail {
  const LiveDetail({
    required this.live,
    required this.mediaState,
    required this.replayAvailable,
    required this.startedAt,
    required this.serverTime,
    required this.handStatus,
    required this.muted,
    this.speaker,
    this.replayDelivery,
  });

  factory LiveDetail.fromJson(Json body) {
    final Json data = body.obj('data') ?? <String, dynamic>{};
    final DateTime? server = data.date('server_time');
    return LiveDetail(
      live: LiveSession.fromJson(data),
      mediaState: data.strOrNull('media_state'),
      replayAvailable: data.flag('replay_available'),
      startedAt: data.date('started_at'),
      serverTime: server,
      handStatus: body.strOrNull('hand_status'),
      muted: body.flag('muted'),
      speaker: LiveSpeakerName.fromJson(body.obj('speaker')),
      replayDelivery: data.strOrNull('replay_delivery'),
    );
  }

  /// The Videos switch the Replay player follows (D-070/D-077), sent while
  /// a replay is available, so its texts match the mode from the start.
  final String? replayDelivery;

  final LiveSession live;

  /// `preparing | ready | recovering | unavailable`, only while live.
  final String? mediaState;
  final bool replayAvailable;
  final DateTime? startedAt;
  final DateTime? serverTime;

  /// `pending | accepted | rejected | ended` or null.
  final String? handStatus;
  final bool muted;

  /// The accepted speaker while the Live runs (top-level `speaker`), kept
  /// current afterwards by `LiveSpeakerChanged` (D-073).
  final LiveSpeakerName? speaker;

  String get status => live.rawStatus;
  bool get isLive => status == 'live';
  bool get isWaiting => status == 'scheduled' || status == 'starting';
  bool get isOver => const <String>{
        'ending',
        'processing_replay',
        'ended',
        'cancelled',
        'failed',
      }.contains(status);
}

/// First and last name of the Student who is speaking (D-073).
class LiveSpeakerName {
  const LiveSpeakerName({required this.firstName, required this.lastName});

  static LiveSpeakerName? fromJson(Json? json) => json == null
      ? null
      : LiveSpeakerName(firstName: json.str('first_name'), lastName: json.str('last_name'));

  final String firstName;
  final String lastName;

  String get fullName => '$firstName $lastName'.trim();
}

/// `POST /lives/{id}/playback-policy`: a one-use challenge plus the DRM
/// systems the server accepts for this Student, and whether the Admin's
/// delivery mode (D-070) lets this device use the clear stream.
class LivePolicy {
  const LivePolicy({
    required this.mode,
    required this.challenge,
    required this.candidates,
    required this.strict,
    required this.softwareFallback,
    required this.maxHeight,
    required this.telemetry,
    this.clearDeliveryAvailable = false,
  });

  factory LivePolicy.fromJson(Json data) {
    final Json policy = data.obj('policy') ?? <String, dynamic>{};
    return LivePolicy(
      mode: data.str('mode'),
      clearDeliveryAvailable: data.flag('clear_delivery_available'),
      challenge: data.str('challenge'),
      candidates: <LiveDrmCandidate>[
        for (final Json c in data.list('candidates'))
          LiveDrmCandidate(drm: c.str('drm'), keySystem: c.str('key_system'), robustness: c.strOrNull('robustness')),
      ],
      strict: policy.str('mode', 'strict') == 'strict',
      softwareFallback: policy.flag('software_fallback'),
      maxHeight: policy['max_height'] is int ? policy['max_height'] as int : null,
      telemetry: data.flag('telemetry'),
    );
  }

  /// `protected`, or `clear` when every device plays the clear stream
  /// (mode C, D-070).
  final String mode;
  final String challenge;
  final List<LiveDrmCandidate> candidates;
  final bool strict;
  final bool softwareFallback;
  final int? maxHeight;
  final bool telemetry;

  /// Mode B: a device that cannot play DRM may ask for the clear stream.
  final bool clearDeliveryAvailable;

  bool get isClear => mode == 'clear';

  /// The clear stream is allowed for this device (mode B or C).
  bool get clearAvailable => isClear || clearDeliveryAvailable;

  /// The Widevine candidate this device can honour, if any. The server
  /// offers `HW_SECURE_ALL` under the strict policy and
  /// `SW_SECURE_DECODE` only when software fallback is allowed.
  LiveDrmCandidate? widevineFor({required bool hardware}) {
    for (final LiveDrmCandidate c in candidates) {
      if (c.drm != 'widevine') continue;
      if (c.robustness == 'HW_SECURE_ALL' && !hardware) continue;
      return c;
    }
    return null;
  }

  /// The FairPlay candidate, offered first while FairPlay is enabled.
  LiveDrmCandidate? get fairplay {
    for (final LiveDrmCandidate c in candidates) {
      if (c.drm == 'fairplay') return c;
    }
    return null;
  }
}

class LiveDrmCandidate {
  const LiveDrmCandidate({required this.drm, required this.keySystem, required this.robustness});

  final String drm;
  final String keySystem;
  final String? robustness;
}

/// `POST /lives/{id}/join`: the protected stream with its entitlement
/// (DASH + Widevine, or HLS + FairPlay on iPhone, D-118), or (`mode: cdn`)
/// the clear adaptive HLS stream (D-070).
class LiveJoin {
  const LiveJoin({
    required this.dashUrl,
    required this.token,
    required this.licenseUrl,
    this.hlsUrl = '',
    this.fairplayLicenseUrl = '',
    this.fairplayCertificateUrl = '',
    required this.maxHeight,
    required this.renewAfter,
    required this.signedUrls,
    this.clear = false,
    this.manifestUrl = '',
    this.mimeType = '',
  });

  factory LiveJoin.fromJson(Json data) {
    final Json drm = data.obj('drm') ?? <String, dynamic>{};
    final Json protection = data.obj('protection') ?? <String, dynamic>{};
    final int expires = data.integer('expires_at');
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int? renewAfter = data['renew_after_seconds'] is int ? data['renew_after_seconds'] as int : null;
    // Web: renew_after_seconds, else expires_at − 30 s, within 15–240 s.
    final int seconds = (renewAfter ?? (expires > 0 ? expires - now - 30 : 90)).clamp(15, 240);
    return LiveJoin(
      dashUrl: data.obj('manifests')?.str('dash') ?? '',
      token: drm.str('token'),
      licenseUrl: drm.obj('license_urls')?.str('widevine') ?? '',
      hlsUrl: data.obj('manifests')?.str('hls') ?? '',
      fairplayLicenseUrl: drm.obj('license_urls')?.str('fairplay') ?? '',
      fairplayCertificateUrl: drm.str('fairplay_certificate_url'),
      maxHeight: protection['max_height'] is int ? protection['max_height'] as int : null,
      renewAfter: Duration(seconds: seconds),
      signedUrls: data.str('url_protection') == 'signed',
      clear: data.str('mode') == 'cdn',
      manifestUrl: data.str('manifest_url'),
      mimeType: data.str('mime_type', 'application/x-mpegurl'),
    );
  }

  final String dashUrl;
  final String token;
  final String licenseUrl;
  final String hlsUrl;
  final String fairplayLicenseUrl;
  final String fairplayCertificateUrl;
  final int? maxHeight;
  final Duration renewAfter;

  /// Signed CDN URLs expire with the token, so renewal must reload the
  /// stream instead of only swapping the licence token.
  final bool signedUrls;

  /// The clear HLS stream (`mode: cdn`), protected by the watermark only.
  final bool clear;
  final String manifestUrl;
  final String mimeType;
}

/// `POST /lives/{id}/speaker`: a microphone-only LiveKit grant, issued
/// only after the teaching team accepted the raised hand.
class SpeakerGrant {
  const SpeakerGrant({required this.url, required this.token});

  factory SpeakerGrant.fromJson(Json data) =>
      SpeakerGrant(url: data.str('url'), token: data.str('token'));

  final String url;
  final String token;
}

/// Live endpoints for the Student (routes/api.php `lives/*`).
class LiveStore {
  LiveStore(this._api);

  final NovaApi _api;

  /// For best-effort traces (`/playback-diagnostics`).
  NovaApi get api => _api;

  Future<LiveDetail> detail(int id) async => LiveDetail.fromJson(await _api.get('/lives/$id'));

  Future<LivePolicy> policy(int id) async =>
      LivePolicy.fromJson((await _api.post('/lives/$id/playback-policy')).obj('data') ?? <String, dynamic>{});

  Future<LiveJoin> join(int id, LivePolicy policy, LiveDrmCandidate candidate) async =>
      LiveJoin.fromJson((await _api.post('/lives/$id/join', <String, Object?>{
            'challenge': policy.challenge,
            'key_system': candidate.keySystem,
            'robustness': candidate.robustness,
          }))
              .obj('data') ??
          <String, dynamic>{});

  /// The clear stream (D-070). Mode C needs no body; mode B asks for it,
  /// which mode A refuses with 403 `LIVE_CLEAR_DELIVERY_DISABLED`.
  Future<LiveJoin> joinClear(int id, LivePolicy policy) async => LiveJoin.fromJson(
      (await _api.post('/lives/$id/join', policy.isClear ? null : const <String, String>{'delivery': 'clear'}))
              .obj('data') ??
          <String, dynamic>{});

  /// Replay of a finished Live: protected like a lesson, no progress;
  /// [clear] asks for the watermarked clear copy (D-070 mode B).
  Future<PlaybackAuthorization> replay(int id, {bool clear = false}) async => PlaybackAuthorization.fromJson(
      (await _api.get('/lives/$id/replay/playback', query: clear ? const <String, String>{'delivery': 'clear'} : null))
              .obj('data') ??
          <String, dynamic>{});

  /// A private question to the teaching team; the Student never sees a
  /// feed, not even their own messages (conception).
  Future<void> ask(int id, String message) => _api.post('/lives/$id/comments', <String, String>{'message': message});

  Future<void> raiseHand(int id) => _api.post('/lives/$id/raise-hand');

  Future<void> lowerHand(int id) => _api.delete('/lives/$id/raise-hand');

  Future<SpeakerGrant> speaker(int id) async =>
      SpeakerGrant.fromJson((await _api.post('/lives/$id/speaker')).obj('data') ?? <String, dynamic>{});

  Future<void> telemetry(int id, String session, List<Json> events) =>
      _api.post('/lives/$id/playback-telemetry', <String, Object>{'session': session, 'events': events});
}

/// Numeric failure codes the backend telemetry log expects
/// (web `LIVE_FAILURE_CODES`).
const Map<String, int> liveFailureCodes = <String, int>{
  'capability': 1,
  'security': 2,
  'drm_init': 4,
  'output': 5,
  'license': 6,
  'delivery': 7,
  'decode': 8,
  'timeout': 9,
  'processing': 10,
  'access': 11,
  'session_expired': 12,
  'first_frame_timeout': 13,
};

/// Why a device plays the clear Live stream (telemetry `fallback_reason`,
/// web `LIVE_FALLBACK_*`, D-070).
const int liveFallbackCapability = 1;
const int liveFallbackDrmError = 2;
const int liveFallbackDecoderError = 3;

/// The protected stream stayed unreachable after the quick reloads (D-077).
const int liveFallbackMediaUnavailable = 4;

/// HDCP / output restriction.
const int liveFallbackOutput = 5;

/// A protected picture that never starts although media is buffered.
const int liveFallbackFirstFrame = 6;

/// Any other failure of the protected attempt.
const int liveFallbackOther = 7;

/// `reason` sent to `/playback-diagnostics` (web `LIVE_FALLBACK_REASONS`).
const Map<int, String> liveFallbackReasons = <int, String>{
  liveFallbackCapability: 'no_drm',
  liveFallbackDrmError: 'drm_error',
  liveFallbackDecoderError: 'drm_error',
  liveFallbackMediaUnavailable: 'media_unavailable',
  liveFallbackOutput: 'drm_error',
  liveFallbackFirstFrame: 'drm_error',
  liveFallbackOther: 'drm_error',
};

/// Batches passive player measurements for
/// `POST /lives/{id}/playback-telemetry` (enabled by the policy). Only
/// numeric, whitelisted fields; at most 600 events, 30 per request, sent
/// every 60 s (web `live-telemetry.ts`, D-071). A batch also counts the
/// Student as present in the Live.
class LiveTelemetry {
  LiveTelemetry(this._store, this._liveId, {Random? random})
      : session = List<String>.generate(16, (_) => (random ?? Random.secure()).nextInt(16).toRadixString(16)).join() {
    _timer = Timer.periodic(flushInterval, (_) => flush());
  }

  static const int maxEvents = 600;
  static const int batchSize = 30;
  static const Duration flushInterval = Duration(seconds: 60);

  final LiveStore _store;
  final int _liveId;
  final String session;
  final Stopwatch _clock = Stopwatch()..start();
  final List<Json> _queue = <Json>[];
  Timer? _timer;
  bool _enabled = false;
  int _recorded = 0;

  bool get enabled => _enabled;
  set enabled(bool value) {
    _enabled = value;
    if (!value) _queue.clear();
  }

  void record(String type, [Map<String, num> fields = const <String, num>{}]) {
    if (!_enabled || _recorded >= maxEvents) return;
    _recorded++;
    _queue.add(<String, dynamic>{
      'type': type,
      'at_ms': _clock.elapsedMilliseconds,
      for (final MapEntry<String, num> field in fields.entries)
        if (field.value.isFinite) field.key: (field.value * 1000).round() / 1000,
    });
    if (_queue.length >= batchSize) flush();
  }

  void flush() {
    while (_queue.isNotEmpty) {
      final List<Json> batch = _queue.take(batchSize).toList();
      _queue.removeRange(0, batch.length);
      _store.telemetry(_liveId, session, batch).catchError((Object _) {});
    }
  }

  /// Sends what is queued and stops the flush timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
    flush();
    _enabled = false;
  }
}
