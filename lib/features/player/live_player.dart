import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_exception.dart';
import '../../core/desktop/desktop_layout.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/security/capture_shield.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/app_lifecycle.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/live_store.dart';
import '../../data/playback_diagnostics.dart';
import '../../data/models.dart';
import '../learning/live_name_form.dart';
import 'lesson_player.dart';
import 'playback_rules.dart';
import 'protected_video.dart';

enum _LiveStage { connecting, waiting, recovering, interrupted, playing, nameRequired, failed }

/// What the overlays above the native picture show: the only part of the
/// player's state that changes the screen (2026-10-30, iPhone picture not
/// fluid). Position reports never rebuild the tree holding the platform view.
typedef _Overlay = ({bool busy, bool playing, bool qualities});

_Overlay _overlayOf(VideoState state) => (
      busy: state.phase == 'buffering' || !state.firstFrame,
      playing: state.playing,
      qualities: state.heights.isNotEmpty,
    );

/// Live playback, the mobile counterpart of the web `LiveHlsPlayer`:
/// playback policy → device-matched Widevine candidate → join, then a
/// renewal loop that swaps the entitlement before it expires.
///
/// D-070: in mode C every device plays the clear adaptive HLS stream; in
/// mode B a device without usable DRM (iPhone until FairPlay, Android
/// without hardware Widevine) or whose DRM/decoder fails asks for it, and
/// keeps using it for the rest of the app session. Mode A is unchanged.
///
/// D-071: transient failures (busy server, throttling, 5xx, network,
/// delivery) are retried forever with jittered back-off up to 15 s; the
/// only final messages are a device that cannot play at all in mode A,
/// and a withdrawn access (401/403/404/410), which refreshes the room.
///
/// D-190: a player behind the live window after a stall (Media3 1002) goes
/// back to the live edge in place (telemetry `edge_jump`), a full reload
/// only after two such jumps within 60 s; a decoder failure gets at most
/// three automatic attempts (the first a rendition lower), then the error
/// screen ([LiveRecovery]). Network failures are handled as before.
///
/// D-192 (Android only; iPhone and the PC app unchanged): a conservative
/// first bandwidth estimate ([AbrStartMemory]), the sound only on a link too
/// weak for the lowest rung ([LiveAudioOnly], banner « Connexion faible :
/// son seul », back to the picture by itself) and a target 7 s behind the
/// live edge while the playback is healthy ([LiveLatencyTarget]).
///
/// Speaking turn (owner decision 2026-10-30, amends D-066 for the apps):
/// while [suspended] the player is kept, muted and hidden under the
/// speaking stage, so the turn's end shows it again at once, without a new
/// join (back at the live edge only if it drifted, [liveReturnNeedsEdge]).
/// During the turn nothing joins: a player that fails or stalls, needs a
/// fresh start, or whose app goes to the background is released instead,
/// and the turn's end starts a fresh one (D-066 as before). A weak
/// downlink ([downlinkWeak]) pauses it for the rest of the turn.
class LivePlayer extends StatefulWidget {
  const LivePlayer({
    super.key,
    required this.live,
    required this.mediaState,
    required this.onWithdrawn,
    this.fullscreen = false,
    this.onToggleFullscreen,
    this.suspended = false,
    this.downlinkWeak = false,
  });

  final LiveSession live;

  /// Server `media_state` from the room's latest detail.
  final String? mediaState;

  /// Access ended (401/403/404/410): the room re-fetches the Live.
  final VoidCallback onWithdrawn;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  /// The Student is speaking: muted, hidden, nothing joins.
  final bool suspended;

  /// The speaking stage's downlink cannot carry the Professor's camera
  /// ([LiveSpeaker.downlinkWeak]): the suspended player pauses until the
  /// turn ends, leaving the bandwidth to the conversation.
  final bool downlinkWeak;

  @override
  State<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<LivePlayer> with WidgetsBindingObserver {
  static const Set<int> _withdrawn = <int>{401, 403, 404, 410};
  static const Duration _sampleEvery = Duration(seconds: 30);
  static const Duration _expiryReloadInterval = Duration(seconds: 30);
  static const Duration _watchEvery = Duration(seconds: 1);

  final Random _random = Random();
  _LiveStage _stage = _LiveStage.connecting;
  String? _failure;

  LivePolicy? _policy;
  LiveDrmCandidate? _candidate;

  /// Paused because the app left the screen: back at the live edge on return.
  bool _pausedAway = false;

  /// Paused for a weak downlink during the speaking turn, until it ends.
  bool _pausedForDownlink = false;

  /// Released during the speaking turn: its end starts a fresh player.
  bool _freshAfterTurn = false;
  LiveJoin? _join;
  ProtectedVideoController? _video;
  LiveTelemetry? _telemetry;

  Timer? _retry;
  Timer? _renewal;
  Timer? _sampler;
  Timer? _watermarkTimer;
  Timer? _hideTimer;
  Timer? _startWatch;

  /// Start/stall watchdog of the current native player (LivePlaybackWatch).
  Timer? _watch;
  LivePlaybackWatch? _playback;
  Duration _watchElapsed = Duration.zero;

  /// Watchdog restarts since the Live last played (longer waits each time).
  int _watchRestarts = 0;

  /// D-212, PC app: software asked of this native player, and its software
  /// switches already handled ([VideoState.drmFallbacks]).
  bool _softwareAsked = false;
  int _seenFallbacks = 0;

  /// iPhone: the last drift seek, on the watchdog's clock ([liveDriftNeedsSeek]).
  Duration? _lastDriftSeek;

  /// Since the player opened: the first picture's `first_frame_ms` (web).
  final Stopwatch _opened = Stopwatch();
  bool _firstPlayRecorded = false;

  /// The current native player has played; a stall in progress.
  bool _playerPlayed = false;
  Stopwatch? _stall;
  int _stallCount = 0;

  /// The reload in progress (web `reload`): its code, since when, and
  /// whether its `ready` was recorded.
  int? _reloadCode;
  Stopwatch? _reloadClock;
  bool _reloadReady = false;

  /// Paused with the play button: not a stall.
  bool _pausedByStudent = false;
  final Stopwatch _notReadyWaited = Stopwatch();
  int _notReadyAttempts = 0;
  int _retryAttempts = 0;
  int _renewalFailures = 0;
  int _quickReloads = 0;
  DateTime? _lastExpiryReload;

  /// Why this device plays the clear stream (telemetry `fallback_reason`).
  int _fallbackReason = 0;

  /// D-190: in-place edge jumps and the decoder's automatic attempts, on
  /// the [_opened] clock.
  final LiveRecovery _recovery = LiveRecovery();

  /// D-190: the rendition cap after a decoder failure (web decode guard).
  int? _decodeCap;

  /// This Live continues on the clear stream (its protected copy was
  /// unreachable); unlike [ClearDeliveryMemory.live] not kept for the device.
  bool _clearForThisLive = false;

  /// D-192 F/H: the sound-only fallback and the latency target of this
  /// Live, kept across native players; what the current player has.
  final LiveAudioOnly _audioOnly = LiveAudioOnly();
  final LiveLatencyTarget _latency = LiveLatencyTarget();
  LiveLatencyMode _appliedLatency = LiveLatencyMode.normal;
  bool _audioSwitching = false;
  final ValueNotifier<bool> _soundOnly = ValueNotifier<bool>(false);

  /// D-192's clock (`clock`, so tests drive it) and when the stall in progress began on it.
  final DateTime _clockStart = clock.now();
  Duration get _now => clock.now().difference(_clockStart);
  Duration? _stallSince;

  /// 0 = automatic; a manual choice survives reconnections (web).
  int _quality = 0;
  bool _qualityApplied = false;

  /// Listened to by the overlays and the watermark only: changing them
  /// never rebuilds the native picture's widget.
  final ValueNotifier<_Overlay> _overlay = ValueNotifier<_Overlay>(_overlayOf(const VideoState()));
  final ValueNotifier<int> _spot = ValueNotifier<int>(0);
  bool _muted = false;
  bool _controls = true;
  bool _loading = false;
  bool _disposed = false;

  LiveStore get _store => AppState.instance.live!;
  bool get _clear => _join?.clear ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CaptureMonitor.instance.addListener(_onCapture);
    if (isDesktopApp) HardwareKeyboard.instance.addHandler(_onKey);
    _opened.start();
    _start();
  }

  @override
  void didUpdateWidget(LivePlayer old) {
    super.didUpdateWidget(old);
    if (widget.suspended && !old.suspended) _suspend();
    if (!widget.suspended && old.suspended) return _endTurn();
    if (widget.suspended && widget.downlinkWeak && !_pausedForDownlink) {
      // Latched for the turn: playing again would compete with the
      // conversation for the same weak link.
      _pausedForDownlink = true;
      _video?.pause();
    }
    // Media came back after an interruption: rejoin (web resumeWaiting).
    if (_stage == _LiveStage.interrupted && widget.mediaState != 'unavailable') {
      _retry?.cancel();
      _start();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    CaptureMonitor.instance.removeListener(_onCapture);
    if (isDesktopApp) HardwareKeyboard.instance.removeHandler(_onKey);
    _telemetry?.record('ended');
    _telemetry?.stop();
    _retry?.cancel();
    _teardown();
    _overlay.dispose();
    _spot.dispose();
    _soundOnly.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (leftScreen(state)) {
      // In the background during a speaking turn: released (owner, 2026-10-30).
      if (widget.suspended && state != AppLifecycleState.inactive) return _releaseForTurn();
      _pausedAway = true;
      _video?.pause();
    } else if (state == AppLifecycleState.resumed && _pausedAway) {
      _pausedAway = false;
      if (_stage == _LiveStage.playing) {
        _pausedByStudent = false;
        _video?.seekToLiveEdge();
        _video?.play();
      }
    }
  }

  void _onCapture() {
    if (CaptureMonitor.instance.captured) _video?.pause();
  }

  // Speaking turn -------------------------------------------------------

  void _suspend() {
    _hideTimer?.cancel();
    _video?.setVolume(0);
    if (widget.downlinkWeak) {
      _pausedForDownlink = true;
      _video?.pause();
    }
    _set(() => _controls = false);
  }

  /// No join during the turn: whatever would start a player releases this
  /// one, and the turn's end starts a fresh one.
  void _releaseForTurn() {
    _retry?.cancel();
    _teardown();
    _freshAfterTurn = true;
    // A fresh start, not the reload of a failure (telemetry).
    _reloadClock = null;
    _reloadCode = null;
    _reloadReady = false;
    _set(() => _stage = _LiveStage.connecting);
  }

  /// The turn ended: the kept player is shown and heard again at once.
  void _endTurn() {
    final bool paused = _pausedForDownlink;
    _pausedForDownlink = false;
    final ProtectedVideoController? video = _video;
    if (_freshAfterTurn || video == null || _stage != _LiveStage.playing) {
      _freshAfterTurn = false;
      if (_stage == _LiveStage.nameRequired) return;
      return unawaited(_start());
    }
    video.setVolume(_muted ? 0 : 1);
    _pausedByStudent = false;
    if (!_pausedAway && !CaptureMonitor.instance.captured) {
      final VideoState state = video.value;
      if (liveReturnNeedsEdge(playing: state.playing && !paused, liveOffset: state.liveOffset)) {
        video.seekToLiveEdge();
      }
      video.play();
    }
    _set(() => _controls = true);
    _scheduleHide();
  }

  /// Stops the current playback; the telemetry session survives.
  void _teardown() {
    _renewal?.cancel();
    _sampler?.cancel();
    _watermarkTimer?.cancel();
    _hideTimer?.cancel();
    _startWatch?.cancel();
    _watch?.cancel();
    _playback = null;
    _playerPlayed = false;
    _stall = null;
    final ProtectedVideoController? video = _video;
    if (video != null) {
      video
        ..removeListener(_onVideo)
        ..dispose();
    }
    _video = null;
    _join = null;
  }

  void _set(VoidCallback change) {
    if (!_disposed && mounted) setState(change);
  }

  Map<String, num> get _deliveryField => <String, num>{'delivery_mode': _clear ? 1 : 0};

  // Join ----------------------------------------------------------------

  Future<void> _start({bool recovering = false}) async {
    if (_loading || _disposed) return;
    if (widget.suspended) return _releaseForTurn();
    _loading = true;
    _retry?.cancel();
    _teardown();
    _set(() {
      if (_stage != _LiveStage.waiting) _stage = recovering ? _LiveStage.recovering : _LiveStage.connecting;
      _failure = null;
    });
    final Stopwatch startup = Stopwatch()..start();

    try {
      final Stopwatch policyClock = Stopwatch()..start();
      final LivePolicy policy = await _store.policy(widget.live.id);
      policyClock.stop();
      if (_disposed) return;
      _telemetry ??= LiveTelemetry(_store, widget.live.id);
      _telemetry!.enabled = policy.telemetry;
      // Known at once: the wording and a failure's fallback depend on it.
      _policy = policy;

      bool clear = policy.isClear;
      LiveDrmCandidate? candidate;
      if (!clear && policy.clearDeliveryAvailable && (ClearDeliveryMemory.live || _clearForThisLive)) {
        // DRM already failed on this device during this session (mode B).
        clear = true;
        if (_fallbackReason == 0) _fallbackReason = liveFallbackDrmError;
      } else if (!clear) {
        final DrmSupport support = await detectDrmSupport();
        if (_disposed) return;
        candidate = switch (support) {
          DrmSupport.hardware || DrmSupport.software when isWindowsApp =>
            policy.playreadyFor(hardware: support == DrmSupport.hardware),
          DrmSupport.hardware || DrmSupport.software =>
            policy.widevineFor(hardware: support == DrmSupport.hardware),
          DrmSupport.fairplay => policy.fairplay,
          _ => null,
        };
        if (candidate == null) {
          _telemetry?.record('error', <String, num>{
            'error_category': liveFailureCodes['capability']!,
            'attempt': policy.candidates.length,
          });
          if (!policy.clearDeliveryAvailable) {
            return _fail(switch (support) {
              DrmSupport.fairplay => 'ios_blocked',
              DrmSupport.software => 'security',
              _ => 'capability',
            });
          }
          // Mode B: no approved DRM on this device — the clear stream.
          clear = true;
          _fallbackReason = liveFallbackCapability;
          ClearDeliveryMemory.live = true;
          reportPlaybackDiagnostic(
        _store.api,
            content: 'live',
            contentId: widget.live.id,
            event: 'clear_fallback',
            reason: 'no_drm',
            category: 'capability',
            phase: 'capability',
          );
        }
      }

      final Stopwatch joinClock = Stopwatch()..start();
      final LiveJoin join = clear
          ? await _store.joinClear(widget.live.id, policy)
          : await _store.join(widget.live.id, policy, candidate!);
      joinClock.stop();
      if (_disposed) return;
      if (join.clear != clear) {
        // The server answered another delivery than asked: start again.
        _loading = false;
        return _retryLater(httpStatus: 0);
      }
      if (widget.suspended) {
        // The Student started speaking during the join: a player started
        // now would be heard before it could be muted.
        _loading = false;
        return _releaseForTurn();
      }

      _candidate = candidate;
      _retryAttempts = 0;
      _notReadyAttempts = 0;
      _notReadyWaited
        ..stop()
        ..reset();
      _play(join);
      final Stopwatch? reload = _reloadClock;
      _reloadReady = reload != null;
      _telemetry?.record('ready', <String, num>{
        // After a reload: the time since that reload started, and why (web).
        'startup_ms': reload?.elapsedMilliseconds ?? startup.elapsedMilliseconds,
        if (reload != null) 'error_code': _reloadCode!,
        'policy_ms': policyClock.elapsedMilliseconds,
        'join_ms': joinClock.elapsedMilliseconds,
        'delivery_mode': clear ? 1 : 0,
        'fallback_reason': _fallbackReason,
        // D-192 G: the first bandwidth estimate given to the native player (Android).
        if (_adaptive) 'startup_bps': AbrStartMemory.startBps(),
        // Web codes: Widevine 1, PlayReady 2, FairPlay 3 (FairPlay is hardware-backed).
        if (!clear) 'drm_system': switch (candidate?.drm) { 'fairplay' => 3, 'playready' => 2, _ => 1 },
        if (!clear)
          'drm_hardware': candidate?.drm == 'fairplay' ||
                  candidate?.robustness == 'HW_SECURE_ALL' ||
                  candidate?.robustness == '3000'
              ? 1
              : 0,
      });
    } on ApiException catch (error) {
      _loading = false;
      _onJoinError(error);
    } catch (_) {
      // An unexpected answer is retried like any transient failure.
      _loading = false;
      _retryLater();
    } finally {
      _loading = false;
    }
  }

  void _onJoinError(ApiException error) {
    if (_disposed) return;
    switch (error.code) {
      case 'PROFILE_NAME_REQUIRED':
        // D-073: a Live needs a first and last name.
        return _set(() => _stage = _LiveStage.nameRequired);
      case 'LIVE_CLEAR_DELIVERY_DISABLED':
        // The Admin went back to mode A: DRM again.
        ClearDeliveryMemory.live = false;
        _clearForThisLive = false;
        _fallbackReason = 0;
        return _retryLater(httpStatus: error.status);
      case 'LIVE_PROTECTED_MEDIA_NOT_READY':
        return _waitForMedia(error);
      case 'LIVE_DRM_CAPABILITY_INVALID':
        // A consumed or expired challenge: a fresh policy fixes it.
        return _retryLater(httpStatus: error.status);
    }
    if (_withdrawn.contains(error.status)) return _withdraw(error);
    // Busy server (409 LIVE_BUSY), throttling, 5xx or no network.
    _retryLater(httpStatus: error.status);
  }

  /// 409 `LIVE_PROTECTED_MEDIA_NOT_READY` until the packager is healthy:
  /// wait with the web's back-off, slower past 180 s, never a dead end;
  /// while the server reports the delivery interrupted, wait for its
  /// media state to change instead.
  void _waitForMedia(ApiException error) {
    _telemetry?.record('not_ready', <String, num>{'attempt': _notReadyAttempts, 'http_status': error.status});
    if (widget.mediaState == 'unavailable') {
      return _set(() => _stage = _LiveStage.interrupted);
    }
    if (!_notReadyWaited.isRunning) _notReadyWaited.start();
    _set(() => _stage = _LiveStage.waiting);
    _retry = Timer(
      notReadyDelay(
        _notReadyAttempts++,
        _random,
        waited: _notReadyWaited.elapsed,
        mediaState: widget.mediaState,
      ),
      _start,
    );
  }

  /// A `reload` event with its cause (web `beginReload`); the first reload
  /// of a burst is the one the next `ready` and `playing` measure from.
  void _beginReload(int code, [Map<String, num> fields = const <String, num>{}]) {
    _telemetry?.record('reload', <String, num>{...fields, 'error_code': code});
    if (_reloadClock == null) {
      _reloadCode = code;
      _reloadClock = Stopwatch()..start();
      _reloadReady = false;
    }
  }

  /// The finished reload's fields for a `playing` event, once its `ready`
  /// was recorded; the reload is then over.
  Map<String, num> _takeReload() {
    final Stopwatch? clock = _reloadClock;
    if (clock == null || !_reloadReady) return const <String, num>{};
    final Map<String, num> fields = <String, num>{'startup_ms': clock.elapsedMilliseconds, 'error_code': _reloadCode!};
    _reloadClock = null;
    _reloadCode = null;
    _reloadReady = false;
    return fields;
  }

  /// Transient failure: "reconnecting", then another attempt.
  void _retryLater({int httpStatus = 0, int errorCode = 0}) {
    if (_disposed) return;
    if (widget.suspended) return _releaseForTurn();
    _retryAttempts++;
    _beginReload(liveReloadRetryLater, <String, num>{
      'attempt': _retryAttempts,
      'http_status': httpStatus,
      'error_data_code': errorCode,
      ..._deliveryField,
    });
    _teardown();
    _set(() => _stage = _LiveStage.recovering);
    _retry?.cancel();
    _retry = Timer(liveRetryDelay(_retryAttempts, _random), () => _start(recovering: true));
  }

  /// Access withdrawn (session replaced, Live over, access removed).
  void _withdraw(ApiException error) {
    _telemetry?.record('ended', <String, num>{'http_status': error.status});
    _telemetry?.flush();
    _fail('access');
    widget.onWithdrawn();
  }

  void _play(LiveJoin join) {
    final ProtectedVideoController video = ProtectedVideoController()..addListener(_onVideo);
    _softwareAsked = false;
    _seenFallbacks = 0;
    _overlay.value = _overlayOf(video.value);
    _qualityApplied = false;
    // A new native player starts playing by itself.
    _pausedByStudent = false;
    _set(() {
      _join = join;
      _video = video;
      _stage = _LiveStage.playing;
      _controls = true;
    });
    _scheduleRenewal(join.renewAfter);
    _cycleWatermark();
    _scheduleHide();
    _sampler?.cancel();
    _sampler = Timer.periodic(_sampleEvery, (_) => _sample());
    // D-192 H: a fresh native player starts at the normal target (12 s) and counts as a stall.
    _appliedLatency = LiveLatencyMode.normal;
    _latency.stall(now: _now, duration: const Duration(days: 1));
    _soundOnly.value = _audioOnly.on && _adaptive;
    video.setVolume(_muted ? 0 : 1);
    if (!join.clear && (_policy?.clearAvailable ?? false)) _watchProtectedStart(video);
    _watchPlayback(video);
  }

  /// The player is meant to play: not paused by the Student, by the app
  /// leaving the screen or by a capture, and its media is ready server-side
  /// (while it prepares or recovers, waiting is the truth, D-065).
  bool get _expectedToPlay =>
      !_pausedByStudent &&
      !_pausedAway &&
      !_pausedForDownlink &&
      !CaptureMonitor.instance.captured &&
      (widget.mediaState == null || widget.mediaState == 'ready');

  /// Bug of 2026-10-29 (Lives 55–64: 14–32 % of app sessions): a native
  /// player can load the Live and never play, without any error; only
  /// leaving and opening the Live again helped. The same reload now
  /// happens by itself ([LivePlaybackWatch]).
  void _watchPlayback(ProtectedVideoController video) {
    _watch?.cancel();
    final LivePlaybackWatch watch = LivePlaybackWatch();
    _playback = watch;
    _watchElapsed = Duration.zero;
    _lastDriftSeek = null;
    _watch = Timer.periodic(_watchEvery, (_) {
      if (_disposed || _video != video || _playback != watch || _loading) return;
      _watchElapsed += _watchEvery;
      final VideoState state = video.value;
      watch.observe(
        elapsed: _watchElapsed,
        expected: _expectedToPlay,
        playing: state.playing,
        position: state.position,
        buffered: state.buffered,
      );
      // D-212: hardware PlayReady with no picture goes on in software first.
      if (state.drmFallbacks > _seenFallbacks) return _wentSoftware(video, state);
      if (PcHardwareStart.fallbackDue(
        hardware: _hardwarePlayReady,
        asked: _softwareAsked,
        firstFrame: state.firstFrame,
        waited: watch.waited,
      )) {
        _softwareAsked = true;
        unawaited(video.softwareFallback());
      }
      // Mode B: the protected start watch decides first (D-077).
      if (_startWatch?.isActive ?? false) return;
      if (watch.stuck(restarts: _watchRestarts, slowDrm: isWindowsApp && !_clear)) {
        return _restartStuck(video, state, played: watch.played);
      }
      _keepNearEdge(video, state);
      _adapt(video, state);
    });
  }

  /// The PC app's player on hardware PlayReady (SL3000).
  bool get _hardwarePlayReady => isWindowsApp && !_clear && _candidate?.robustness == '3000';

  /// D-212: the PC page went on in software PlayReady (asked above, or after
  /// its own DRM error or start check). The watch counts again from here, and
  /// later starts in this app run are software (the native side remembers).
  void _wentSoftware(ProtectedVideoController video, VideoState state) {
    _seenFallbacks = state.drmFallbacks;
    _candidate = _policy?.playreadyFor(hardware: false) ?? _candidate;
    _telemetry?.record('reload', <String, num>{
      'error_code': liveReloadSoftwareFallback,
      'drm_hardware': 0,
      ..._mediaFields(state),
      ..._deliveryField,
    });
    _watchPlayback(video);
  }

  /// D-192: Android's Media3 player only (track disabling, target offset override).
  bool get _adaptive => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !isWindowsApp;

  bool _playingNow(VideoState state) =>
      state.playing && state.firstFrame && _stall == null && _expectedToPlay && !widget.suspended && !_audioSwitching;

  /// D-192 F/H, once a second: the measured bandwidth and the buffer decide.
  void _adapt(ProtectedVideoController video, VideoState state) {
    if (!_adaptive) return;
    AbrStartMemory.remember(state.bandwidthBps);
    final Duration now = _now;
    final bool playing = _playingNow(state);
    if (LiveLatencyTarget.enabled) {
      _applyLatency(video, state, _latency.observe(now: now, playing: playing, bufferAhead: state.buffered - state.position, liveOffset: state.liveOffset));
    }
    if (LiveAudioOnly.enabled && !_audioSwitching) {
      final AudioOnlyDecision? decision = _audioOnly.observe(now: now, bandwidthBps: state.bandwidthBps, playing: playing);
      if (decision != null) _switchSoundOnly(video, state, decision == AudioOnlyDecision.enter);
    }
  }

  void _adaptToStall(ProtectedVideoController video, VideoState state, Duration duration) {
    if (!_adaptive) return;
    final Duration now = _now;
    if (LiveLatencyTarget.enabled) _applyLatency(video, state, _latency.stall(now: now, duration: duration));
    if (!LiveAudioOnly.enabled || _audioSwitching) return;
    final AudioOnlyDecision? decision = _audioOnly.stall(now: now, duration: duration, lowestRung: onLowestRung(state.heights, state.videoHeight));
    if (decision == AudioOnlyDecision.enter) _switchSoundOnly(video, state, true);
  }

  void _applyLatency(ProtectedVideoController video, VideoState state, LiveLatencyMode mode) {
    if (mode == _appliedLatency) return;
    _appliedLatency = mode;
    unawaited(video.setLiveTargetOffset(mode == LiveLatencyMode.low ? LiveLatencyTarget.lowOffset : null));
    _telemetry?.record('latency_target', <String, num>{
      'target_latency_s': _latency.target.inMilliseconds / 1000,
      if (state.liveOffset != null) 'live_latency_s': state.liveOffset!.inMilliseconds / 1000,
      'buffer_ahead_s': (state.buffered - state.position).inMilliseconds / 1000,
      'attempt': _latency.failures,
      ..._deliveryField,
    });
  }

  /// D-192 F: the same native player disables (or enables again) its video
  /// track: no new join, authorization or player.
  void _switchSoundOnly(ProtectedVideoController video, VideoState state, bool on) {
    _audioSwitching = true;
    _telemetry?.record(on ? 'audio_only_on' : 'audio_only_off', <String, num>{
      if (state.bandwidthBps != null) 'bandwidth_bps': state.bandwidthBps!,
      if (state.videoHeight != null) 'height': state.videoHeight!,
      'stall_count': _stallCount,
      'attempt': _audioOnly.entries,
      'audio_only': on ? (_audioOnly.reason == 'stalls' ? 2 : 1) : 0,
      ..._deliveryField,
    });
    _telemetry?.flush();
    _soundOnly.value = on;
    unawaited(video.setAudioOnly(on).whenComplete(() => _audioSwitching = false));
  }

  /// iPhone: AVPlayer plays the Live at exactly 1.0× without catching up
  /// by itself; one that fell far behind (stalls) is sent back to the edge
  /// once. Android keeps Media3's own catch-up (D-065).
  void _keepNearEdge(ProtectedVideoController video, VideoState state) {
    if (defaultTargetPlatform != TargetPlatform.iOS || widget.suspended || !_expectedToPlay) return;
    final Duration? last = _lastDriftSeek;
    if (!liveDriftNeedsSeek(
      playing: state.playing,
      liveOffset: state.liveOffset,
      sinceLastSeek: last == null ? null : _watchElapsed - last,
    )) {
      return;
    }
    _lastDriftSeek = _watchElapsed;
    video.seekToLiveEdge();
  }

  void _restartStuck(ProtectedVideoController video, VideoState state, {required bool played}) {
    _watch?.cancel();
    video.removeListener(_onVideo);
    _watchRestarts++;
    _telemetry?.record('error', <String, num>{
      'error_category': liveFailureCodes[played ? 'timeout' : 'first_frame_timeout']!,
      ..._mediaFields(state),
      ..._deliveryField,
    });
    _beginReload(liveReloadHardRecover, <String, num>{'attempt': _watchRestarts, ..._deliveryField});
    _start(recovering: true);
  }

  /// What the native player holds, for `sample`, `waiting` and `error`.
  Map<String, num> _mediaFields(VideoState state) => <String, num>{
        'buffer_ahead_s': (state.buffered - state.position).inMilliseconds / 1000,
        if (state.liveOffset != null) 'edge_distance_s': state.liveOffset!.inMilliseconds / 1000,
        'current_time_s': state.position.inMilliseconds / 1000,
        'ready_state': liveReadyState(phase: state.phase, firstFrame: state.firstFrame, playing: state.playing),
      };

  /// Web `playing`/`waiting` telemetry: the first moving picture
  /// (`first_frame_ms` since the player opened), the first one after a
  /// reload (`startup_ms` since it started, `error_code`), and stalls
  /// (`waiting`, then `playing` with `stall_ms`).
  void _observePlayback(VideoState state) {
    _recovery.observe(playing: state.playing, now: _opened.elapsed);
    if (state.playing) {
      _watchRestarts = 0;
      final Stopwatch? stall = _stall;
      if (!_firstPlayRecorded) {
        _firstPlayRecorded = true;
        _telemetry?.record('playing', <String, num>{
          'first_frame_ms': _opened.elapsedMilliseconds,
          ..._takeReload(),
          ..._deliveryField,
        });
      } else if (stall != null) {
        _stallCount++;
        _telemetry?.record('playing', <String, num>{
          'stall_ms': stall.elapsedMilliseconds,
          'stall_count': _stallCount,
          ..._takeReload(),
        });
        final ProtectedVideoController? video = _video;
        final Duration? since = _stallSince;
        if (video != null && since != null) _adaptToStall(video, state, _now - since);
      } else if (!_playerPlayed) {
        final Map<String, num> reloaded = _takeReload();
        if (reloaded.isNotEmpty) _telemetry?.record('playing', reloaded);
      }
      _stall = null;
      _stallSince = null;
      _playerPlayed = true;
    } else if (_playerPlayed && _stall == null && state.phase == 'buffering' && _expectedToPlay) {
      _stall = Stopwatch()..start();
      _stallSince = _now;
      final Map<String, num> media = _mediaFields(state);
      _telemetry?.record('waiting', <String, num>{
        'buffer_ahead_s': media['buffer_ahead_s']!,
        'ready_state': media['ready_state']!,
      });
    }
  }

  /// Mode B: a protected picture that never starts although media is
  /// buffered goes clear (D-077).
  void _watchProtectedStart(ProtectedVideoController video) {
    _startWatch?.cancel();
    final Stopwatch clock = Stopwatch()..start();
    Duration? start;
    _startWatch = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      final VideoState state = video.value;
      start ??= state.position;
      if (_video != video || state.firstFrame || clock.elapsed > ProtectedStartWatch.giveUp) {
        timer.cancel();
        return;
      }
      if (ProtectedStartWatch.stuck(
        elapsed: clock.elapsed,
        firstFrame: state.firstFrame,
        start: start!,
        position: state.position,
        buffered: state.buffered,
      )) {
        timer.cancel();
        video.removeListener(_onVideo);
        _switchToClear(liveFallbackFirstFrame, state: state, category: 'decode');
      }
    });
  }

  /// Modes B and C: nothing the Student reads speaks of protection
  /// (D-077); before the policy answers, the wording stays neutral.
  bool get _neutral => _clear || (_policy?.clearAvailable ?? true);

  void _fail(String category, {int? code, int? attempt}) {
    final bool drm = !_clear;
    _teardown();
    // Only access refusals (any mode) and DRM failures in mode A end here.
    if (category != 'access') {
      reportPlaybackDiagnostic(
        _store.api,
        content: 'live',
        contentId: widget.live.id,
        event: 'error_shown',
        category: category,
        code: code,
        attempt: attempt,
        drm: drm && _candidate != null,
        robustness: _candidate?.robustness,
        neutral: _neutral,
        clear: !drm,
      );
    }
    _set(() {
      _stage = _LiveStage.failed;
      _failure = category;
    });
  }

  /// D-070/D-077 mode B: the protected attempt failed on this device —
  /// continue on the clear stream with a fresh player. An unreachable
  /// protected stream concerns this Live only and is not remembered.
  void _switchToClear(int reason, {VideoState? state, String? category}) {
    if (reason != liveFallbackMediaUnavailable) ClearDeliveryMemory.live = true;
    _clearForThisLive = true;
    _fallbackReason = reason;
    _beginReload(liveReloadClearFallback, <String, num>{'fallback_reason': reason, 'delivery_mode': 1});
    _telemetry?.flush();
    reportPlaybackDiagnostic(
        _store.api,
      content: 'live',
      contentId: widget.live.id,
      event: 'clear_fallback',
      reason: liveFallbackReasons[reason] ?? 'drm_error',
      category: category,
      phase: reason == liveFallbackFirstFrame ? 'first_frame' : 'streaming',
      code: state?.errorCode,
      drm: true,
      robustness: _candidate?.robustness,
    );
    _start(recovering: true);
  }

  // Renewal -------------------------------------------------------------

  void _scheduleRenewal(Duration after) {
    _renewal?.cancel();
    _renewal = Timer(after, _renew);
  }

  Future<void> _renew() async {
    final LiveJoin? current = _join;
    if (current == null || _disposed) return;
    if (_loading) return _scheduleRenewal(renewalRetryDelay(1));
    // Signed media URLs expire with the authorization: a fresh start.
    if (current.signedUrls) {
      _beginReload(liveReloadRenewal, _deliveryField);
      return _start(recovering: true);
    }
    bool restart = false;
    try {
      final LivePolicy policy = await _store.policy(widget.live.id);
      if (_disposed || _join != current) return;
      if (current.clear) {
        // The clear stream has no licence: renewal re-checks the
        // authorization and keeps playing while the manifest is unchanged.
        if (!policy.clearAvailable) {
          restart = true;
        } else {
          final LiveJoin join = await _store.joinClear(widget.live.id, policy);
          if (_disposed || _join != current) return;
          restart = !join.clear || join.manifestUrl != current.manifestUrl;
          if (!restart) _renewed(join);
        }
      } else {
        final LiveDrmCandidate? candidate = _candidate;
        if (policy.mode != 'protected' || candidate == null) {
          restart = true;
        } else {
          final LiveJoin join = await _store.join(widget.live.id, policy, candidate);
          if (_disposed || _join != current) return;
          restart = join.clear;
          if (!restart) {
            await _video?.renewToken(join.token);
            _renewed(join);
          }
        }
      }
    } on ApiException catch (error) {
      if (_disposed) return;
      _telemetry?.record('renewal_failed', <String, num>{'http_status': error.status, ..._deliveryField});
      if (error.code == 'LIVE_CLEAR_DELIVERY_DISABLED') {
        ClearDeliveryMemory.live = false;
        _clearForThisLive = false;
        _fallbackReason = 0;
        restart = true;
      } else if (_withdrawn.contains(error.status) && error.code != 'LIVE_DRM_CAPABILITY_INVALID') {
        return _withdraw(error);
      } else {
        _renewalFailures++;
        _scheduleRenewal(renewalRetryDelay(_renewalFailures));
      }
    }
    if (restart) {
      _beginReload(liveReloadRenewal, _deliveryField);
      unawaited(_start(recovering: true));
    }
  }

  void _renewed(LiveJoin join) {
    _renewalFailures = 0;
    _telemetry?.record('renewal', _deliveryField);
    _join = join;
    _scheduleRenewal(join.renewAfter);
  }

  // Player events -------------------------------------------------------

  void _onVideo() {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    final VideoState state = video.value;
    final String? category = state.errorCategory;
    if (category == null) {
      if (!_qualityApplied && _quality > 0 && state.heights.isNotEmpty) {
        _qualityApplied = true;
        video.setQuality(state.heights.contains(_quality) ? _quality : 0);
      }
      _observePlayback(state);
      // Not setState: a position report (each second) would rebuild the
      // whole player, platform view included, for nothing on screen.
      _overlay.value = _overlayOf(state);
      return;
    }

    // Handled once, outside the notification: every branch replaces or
    // stops (disposes) this player.
    video.removeListener(_onVideo);
    scheduleMicrotask(() {
      if (!_disposed && _video == video) _onVideoError(state, category);
    });
  }

  void _onVideoError(VideoState state, String category) {
    final bool drmSide = state.errorKind == 'drm' || state.errorKind == 'decoder';
    _telemetry?.record('error', <String, num>{
      'error_category': liveFailureCodes[category] ?? 0,
      'error_data_code': state.errorCode,
      if (state.errorCause > 0) 'error_cause': state.errorCause,
      if (drmSide) 'license_status': state.licenseStatus,
      ..._deliveryField,
    });

    switch (_recovery.decide(
      category: category,
      kind: state.errorKind,
      code: state.errorCode,
      now: _opened.elapsed,
    )) {
      case LiveFailureAction.edgeJump:
        return _jumpToEdge(state);
      case LiveFailureAction.decoderGiveUp:
        return _giveUpDecoder(state);
      case LiveFailureAction.decoderRetry:
        // The first attempt asks for one rendition lower (web decode guard).
        if (_recovery.decoderFailures == 1) _decodeCap = lowerDecodeHeight(state.heights, current: _decodeCap);
      case LiveFailureAction.usual:
        break;
    }

    if (_clear) return _retryLater(errorCode: state.errorCode);

    // D-077 mode B: every failure of the protected attempt continues on the
    // clear stream; an unreachable protected stream first gets the two
    // quick reloads, an expired licence its fresh start.
    if (_policy?.clearAvailable ?? false) {
      switch (category) {
        case 'expired':
          break;
        case 'delivery' || 'timeout' || 'behind_live':
          if (_quickReloads < 2) break;
          return _switchToClear(liveFallbackMediaUnavailable, state: state, category: category);
        default:
          return _switchToClear(
            switch (category) {
              _ when state.errorKind == 'decoder' || category == 'decode' => liveFallbackDecoderError,
              'output' => liveFallbackOutput,
              _ when state.errorKind == 'drm' || clearFallbackReason(category) == 'drm_error' => liveFallbackDrmError,
              _ => liveFallbackOther,
            },
            state: state,
            category: category,
          );
      }
    }

    switch (category) {
      case 'expired':
        // Only a licence the CDM reports as expired is replaced, through a
        // freshly authorized start, at most once per 30 s.
        final DateTime now = DateTime.now();
        final DateTime? last = _lastExpiryReload;
        if (last == null || now.difference(last) >= _expiryReloadInterval) {
          _lastExpiryReload = now;
          _telemetry?.record('expired');
          _beginReload(liveReloadExpired, <String, num>{'error_data_code': state.errorCode});
          _start(recovering: true);
        } else {
          _retryLater(errorCode: state.errorCode);
        }
      case 'delivery' || 'timeout' || 'behind_live':
        // Two quick reloads, then the regular back-off (web hardRecover).
        if (_quickReloads < 2) {
          _quickReloads++;
          _beginReload(liveReloadHardRecover, <String, num>{
            'attempt': _quickReloads,
            'error_data_code': state.errorCode,
            ..._deliveryField,
          });
          _start(recovering: true);
        } else {
          _retryLater(errorCode: state.errorCode);
        }
      default:
        // Mode A and a DRM failure: only this is a final message.
        _fail(category);
    }
  }

  /// D-190: behind the live window after a stall (Media3 1002): back to the
  /// live edge in the same player — no new authorization, playback session
  /// or player. A native player that cannot do it gets the full reload.
  void _jumpToEdge(VideoState state) {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    _telemetry?.record(liveEdgeJumpEvent, <String, num>{
      'error_code': state.errorCode,
      'attempt': _recovery.edgeJumps,
      if (state.liveOffset != null) 'edge_distance_s': state.liveOffset!.inMilliseconds / 1000,
      ..._deliveryField,
    });
    // The failure is cleared synchronously, so the listener sees the next one.
    final Future<bool> recovery = video.recoverAtLiveEdge();
    video.addListener(_onVideo);
    unawaited(recovery.then((bool recovered) {
      if (recovered || _disposed || _video != video) return;
      video.removeListener(_onVideo);
      _beginReload(liveReloadHardRecover, <String, num>{'error_data_code': state.errorCode, ..._deliveryField});
      _start(recovering: true);
    }));
  }

  /// D-190: the decoder failed again after its automatic attempts (Live 69:
  /// two phones looped 282 times): one telemetry event, the error screen,
  /// and no further automatic retry.
  void _giveUpDecoder(VideoState state) {
    _telemetry?.record('error', <String, num>{
      'error_category': liveFailureCodes['decoder']!,
      'error_data_code': state.errorCode,
      'attempt': _recovery.decoderFailures,
      ..._deliveryField,
    });
    _telemetry?.flush();
    _fail('decoder', code: state.errorCode, attempt: _recovery.decoderFailures);
  }

  void _sample() {
    final VideoState? state = _video?.value;
    if (state == null || !state.firstFrame) return;
    _telemetry?.record('sample', <String, num>{
      ..._mediaFields(state),
      if (_quality > 0) 'height': _quality,
      // D-192: the latency target and the sound only (Android).
      if (_adaptive) 'target_latency_s': _latency.target.inMilliseconds / 1000,
      if (_adaptive) 'audio_only': _audioOnly.on ? 1 : 0,
    });
  }

  void _cycleWatermark() {
    _watermarkTimer?.cancel();
    _watermarkTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _spot.value = (_spot.value + 1) % liveWatermarkSpots.length;
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (_video?.value.playing ?? false) _set(() => _controls = false);
    });
  }

  /// D-193, PC app: F full screen and M sound on/off while this Live is in
  /// front and nothing is being typed (the room's comment field).
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || _video == null) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyF && widget.onToggleFullscreen != null) {
      widget.onToggleFullscreen!();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return true;
    }
    return false;
  }

  void _toggleMute() {
    _set(() => _muted = !_muted);
    _video?.setVolume(_muted ? 0 : 1);
    _scheduleHide();
  }

  void _togglePlay() {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    if (video.value.playing) {
      _pausedByStudent = true;
      video.pause();
    } else {
      _pausedByStudent = false;
      // Rejoin the edge rather than resuming minutes behind the class.
      video
        ..seekToLiveEdge()
        ..play();
    }
    _scheduleHide();
  }

  Future<void> _pickQuality() async {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => LiveQualitySheet(
        heights: video.value.heights,
        selected: _quality,
        onSelected: (int height) {
          _set(() => _quality = height);
          _qualityApplied = true;
          _video?.setQuality(height);
        },
      ),
    );
    _scheduleHide();
  }

  // UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_stage == _LiveStage.nameRequired) {
      return LiveNameForm(onSaved: () {
        _set(() => _stage = _LiveStage.connecting);
        _start();
      });
    }
    final LiveJoin? join = _join;
    final ProtectedVideoController? video = _video;
    final bool fairPlay = _candidate?.drm == 'fairplay';
    final Widget box = ColoredBox(
      key: _boxKey,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_stage == _LiveStage.playing && join != null && video != null) ...[
            ProtectedVideoView(
              // One native view per controller: a reload with the same URL must
              // create a new player, not reuse the released one.
              key: ObjectKey(video),
              manifest: join.clear
                  ? join.manifestUrl
                  : fairPlay
                      ? join.hlsUrl
                      : join.dashUrl,
              clear: join.clear,
              licenseUrl: isWindowsApp
                  ? join.playreadyLicenseUrl
                  : fairPlay
                      ? join.fairplayLicenseUrl
                      : join.licenseUrl,
              certificateUrl: fairPlay ? join.fairplayCertificateUrl : '',
              keySystem: _candidate?.keySystem ?? playReadyKeySystem,
              robustness: _candidate?.robustness ?? '2000',
              token: join.token,
              maxHeight: _maxHeight(join),
              live: true,
              controller: video,
              startBps: _adaptive ? AbrStartMemory.startBps() : null,
              audioOnly: _adaptive && _audioOnly.on,
            ),
            _watermark(context),
            ValueListenableBuilder<bool>(
              valueListenable: _soundOnly,
              builder: (BuildContext context, bool soundOnly, _) => soundOnly ? const _SoundOnlyBanner() : const SizedBox.shrink(),
            ),
            ValueListenableBuilder<_Overlay>(
              valueListenable: _overlay,
              builder: (BuildContext context, _Overlay overlay, Widget? spinner) =>
                  overlay.busy ? spinner! : const SizedBox.shrink(),
              child: const Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _set(() => _controls = !_controls);
                  if (_controls) _scheduleHide();
                },
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _controls ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_controls,
                child: ValueListenableBuilder<_Overlay>(
                  valueListenable: _overlay,
                  builder: (BuildContext context, _Overlay overlay, _) => _liveControls(context, overlay),
                ),
              ),
            ),
          ] else
            _stageNotice(context),
          if (_policy != null || join != null)
            Positioned(top: 10, left: 10, child: ProtectedBadge(clear: _neutral)),
        ],
      ),
    );
    if (widget.fullscreen) return box;
    return AspectRatio(aspectRatio: 16 / 9, child: box);
  }

  /// The server's cap (protected stream only), lowered by a decoder
  /// failure (D-190) on either stream.
  int? _maxHeight(LiveJoin join) {
    final int? server = join.clear ? null : join.maxHeight ?? _policy?.maxHeight;
    final int? decode = _decodeCap;
    if (decode == null) return server;
    return server == null ? decode : min(server, decode);
  }

  /// Keeps the picture (and its native player) when fullscreen moves it to
  /// another place in the tree: without it a second player would start.
  final GlobalKey _boxKey = GlobalKey();

  /// Its move every 12 s rebuilds and repaints the watermark alone.
  Widget _watermark(BuildContext context) {
    final StudentProfile? me = AppScope.of(context).profile;
    final Widget mark = PlayerWatermark(
      name: me?.fullName ?? '',
      phone: me?.phone ?? '',
      session: 'LIVE-${widget.live.id}',
      strong: _clear || (_policy?.softwareFallback ?? false),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => IgnorePointer(
        child: RepaintBoundary(
          child: ValueListenableBuilder<int>(
            valueListenable: _spot,
            child: mark,
            builder: (BuildContext context, int index, Widget? mark) {
              final WatermarkSpot spot = liveWatermarkSpots[index];
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeInOutCubic,
                    top: box.maxHeight * spot.top,
                    left: spot.right ? null : box.maxWidth * spot.inset,
                    right: spot.right ? box.maxWidth * spot.inset : null,
                    child: mark!,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _stageNotice(BuildContext context) {
    return switch (_stage) {
      _LiveStage.connecting => _notice(context, null, 'live.connecting'),
      _LiveStage.waiting => _notice(context, null, 'live.starting'),
      _LiveStage.recovering => _notice(context, null, 'live.reconnectingPlayer'),
      _LiveStage.interrupted => _notice(context, Icons.portable_wifi_off_rounded, 'live.interrupted'),
      _ => _failed(context),
    };
  }

  Widget _notice(BuildContext context, IconData? icon, String key) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon == null)
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
              )
            else
              Icon(icon, size: 30, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              context.tr(key),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.4,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final String category = _failure ?? 'delivery';
    final bool retryable = !const <String>{'ios_blocked', 'security', 'capability', 'access'}.contains(category);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 30, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              context.tr(playerFailureKey(category, clear: _neutral)),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.4,
                color: Colors.white,
              ),
            ),
            if (retryable) ...[
              const SizedBox(height: 12),
              PressableScale(
                onTap: () {
                  _quickReloads = 0;
                  _recovery.retriedByStudent();
                  _start();
                },
                semanticLabel: context.tr('common.retry'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    context.tr('common.retry'),
                    style: NovaTypography.textTheme.labelMedium!.copyWith(color: NovaColors.ink950),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _liveControls(BuildContext context, _Overlay state) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x00000000), Color(0xAA000000)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 6, 2),
          child: Row(
            children: [
              IconButton(
                onPressed: _togglePlay,
                icon: Icon(
                  state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: NovaColors.heartRed,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _toggleMute,
                tooltip: context.tr('live.sound'),
                icon: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
              ),
              if (state.qualities)
                IconButton(
                  onPressed: _pickQuality,
                  tooltip: context.tr('player.quality'),
                  icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                ),
              if (widget.onToggleFullscreen != null)
                IconButton(
                  onPressed: widget.onToggleFullscreen,
                  tooltip: context.tr('player.fullscreen'),
                  icon: Icon(
                    widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto or one of the Live renditions (1080p, 720p, 480p), web parity.
/// D-192 F: « Connexion faible : son seul » over the dark picture.
class _SoundOnlyBanner extends StatelessWidget {
  const _SoundOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xEB0F172A),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.volume_up_rounded, size: 18, color: Color(0xFFFACC15)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('player.audio_only'),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveQualitySheet extends StatelessWidget {
  const LiveQualitySheet({
    super.key,
    required this.heights,
    required this.selected,
    required this.onSelected,
  });

  final List<int> heights;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, int height) {
      final bool active = height == selected;
      return PressableScale(
        onTap: () {
          onSelected(height);
          Navigator.of(context).pop();
        },
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? NovaColors.ink950 : NovaColors.subtleFill,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label,
            style: NovaTypography.textTheme.labelMedium!.copyWith(
              color: active ? Colors.white : NovaColors.textStrong,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('player.quality'), style: NovaTypography.textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              option(context.tr('player.auto'), 0),
              for (final int height in heights) option('${height}p', height),
            ],
          ),
        ],
      ),
    );
  }
}
