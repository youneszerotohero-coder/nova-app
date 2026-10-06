import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/security/capture_shield.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/live_store.dart';
import '../../data/playback_diagnostics.dart';
import '../../data/models.dart';
import '../learning/live_name_form.dart';
import 'lesson_player.dart';
import 'playback_rules.dart';
import 'protected_video.dart';

enum _LiveStage { connecting, waiting, recovering, interrupted, playing, nameRequired, failed }

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
class LivePlayer extends StatefulWidget {
  const LivePlayer({
    super.key,
    required this.live,
    required this.mediaState,
    required this.onWithdrawn,
    this.fullscreen = false,
    this.onToggleFullscreen,
  });

  final LiveSession live;

  /// Server `media_state` from the room's latest detail.
  final String? mediaState;

  /// Access ended (401/403/404/410): the room re-fetches the Live.
  final VoidCallback onWithdrawn;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  State<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<LivePlayer> with WidgetsBindingObserver {
  static const Set<int> _withdrawn = <int>{401, 403, 404, 410};
  static const Duration _sampleEvery = Duration(seconds: 30);
  static const Duration _expiryReloadInterval = Duration(seconds: 30);

  final Random _random = Random();
  _LiveStage _stage = _LiveStage.connecting;
  String? _failure;

  LivePolicy? _policy;
  LiveDrmCandidate? _candidate;
  LiveJoin? _join;
  ProtectedVideoController? _video;
  LiveTelemetry? _telemetry;

  Timer? _retry;
  Timer? _renewal;
  Timer? _sampler;
  Timer? _watermarkTimer;
  Timer? _hideTimer;
  Timer? _startWatch;
  final Stopwatch _notReadyWaited = Stopwatch();
  int _notReadyAttempts = 0;
  int _retryAttempts = 0;
  int _renewalFailures = 0;
  int _quickReloads = 0;
  DateTime? _lastExpiryReload;

  /// Why this device plays the clear stream (telemetry `fallback_reason`).
  int _fallbackReason = 0;

  /// This Live continues on the clear stream (its protected copy was
  /// unreachable); unlike [ClearDeliveryMemory.live] not kept for the device.
  bool _clearForThisLive = false;

  /// 0 = automatic; a manual choice survives reconnections (web).
  int _quality = 0;
  bool _qualityApplied = false;
  int _spot = 0;
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
    _start();
  }

  @override
  void didUpdateWidget(LivePlayer old) {
    super.didUpdateWidget(old);
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
    _telemetry?.record('ended');
    _telemetry?.stop();
    _retry?.cancel();
    _teardown();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _video?.pause();
    } else if (_stage == _LiveStage.playing) {
      _video?.seekToLiveEdge();
      _video?.play();
    }
  }

  void _onCapture() {
    if (CaptureMonitor.instance.captured) _video?.pause();
  }

  /// Stops the current playback; the telemetry session survives.
  void _teardown() {
    _renewal?.cancel();
    _sampler?.cancel();
    _watermarkTimer?.cancel();
    _hideTimer?.cancel();
    _startWatch?.cancel();
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

      _candidate = candidate;
      _retryAttempts = 0;
      _notReadyAttempts = 0;
      _notReadyWaited
        ..stop()
        ..reset();
      _play(join);
      _telemetry?.record('ready', <String, num>{
        'startup_ms': startup.elapsedMilliseconds,
        'policy_ms': policyClock.elapsedMilliseconds,
        'join_ms': joinClock.elapsedMilliseconds,
        'delivery_mode': clear ? 1 : 0,
        'fallback_reason': _fallbackReason,
        // Web codes: Widevine 1, FairPlay 3 (FairPlay is hardware-backed).
        if (!clear) 'drm_system': candidate?.drm == 'fairplay' ? 3 : 1,
        if (!clear)
          'drm_hardware': candidate?.drm == 'fairplay' || candidate?.robustness == 'HW_SECURE_ALL' ? 1 : 0,
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

  /// Transient failure: "reconnecting", then another attempt.
  void _retryLater({int httpStatus = 0, int errorCode = 0}) {
    if (_disposed) return;
    _retryAttempts++;
    _telemetry?.record('reload', <String, num>{
      'attempt': _retryAttempts,
      'http_status': httpStatus,
      'error_code': errorCode,
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
    _qualityApplied = false;
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
    video.setVolume(_muted ? 0 : 1);
    if (!join.clear && (_policy?.clearAvailable ?? false)) _watchProtectedStart(video);
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

  void _fail(String category) {
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
    _telemetry?.record('reload', <String, num>{'fallback_reason': reason, 'delivery_mode': 1});
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
    if (current.signedUrls) return _start(recovering: true);
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
    if (restart) unawaited(_start(recovering: true));
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
      _set(() {});
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
      if (drmSide) 'license_status': state.licenseStatus,
      ..._deliveryField,
    });

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
          _start(recovering: true);
        } else {
          _retryLater(errorCode: state.errorCode);
        }
      case 'delivery' || 'timeout' || 'behind_live':
        // Two quick reloads, then the regular back-off (web hardRecover).
        if (_quickReloads < 2) {
          _quickReloads++;
          _telemetry?.record('reload', <String, num>{'attempt': _quickReloads});
          _start(recovering: true);
        } else {
          _retryLater(errorCode: state.errorCode);
        }
      default:
        // Mode A and a DRM failure: only this is a final message.
        _fail(category);
    }
  }

  void _sample() {
    final VideoState? state = _video?.value;
    if (state == null || !state.firstFrame) return;
    _telemetry?.record('sample', <String, num>{
      'buffer_ahead_s': (state.buffered - state.position).inMilliseconds / 1000,
      if (state.liveOffset != null) 'edge_distance_s': state.liveOffset!.inMilliseconds / 1000,
      if (_quality > 0) 'height': _quality,
    });
  }

  void _cycleWatermark() {
    _watermarkTimer?.cancel();
    _watermarkTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _set(() => _spot = (_spot + 1) % liveWatermarkSpots.length);
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (_video?.value.playing ?? false) _set(() => _controls = false);
    });
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
      video.pause();
    } else {
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
              licenseUrl: fairPlay ? join.fairplayLicenseUrl : join.licenseUrl,
              certificateUrl: fairPlay ? join.fairplayCertificateUrl : '',
              token: join.token,
              maxHeight: join.clear ? null : join.maxHeight ?? _policy?.maxHeight,
              live: true,
              controller: video,
            ),
            _watermark(context),
            if (video.value.phase == 'buffering' || !video.value.firstFrame)
              const Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
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
              child: IgnorePointer(ignoring: !_controls, child: _liveControls(context, video.value)),
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

  Widget _watermark(BuildContext context) {
    final StudentProfile? me = AppScope.of(context).profile;
    final WatermarkSpot spot = liveWatermarkSpots[_spot];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => IgnorePointer(
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOutCubic,
              top: box.maxHeight * spot.top,
              left: spot.right ? null : box.maxWidth * spot.inset,
              right: spot.right ? box.maxWidth * spot.inset : null,
              child: PlayerWatermark(
                name: me?.fullName ?? '',
                phone: me?.phone ?? '',
                session: 'LIVE-${widget.live.id}',
                strong: _clear || (_policy?.softwareFallback ?? false),
              ),
            ),
          ],
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
                fontFamily: 'Inter',
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
                fontFamily: 'Inter',
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

  Widget _liveControls(BuildContext context, VideoState state) {
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
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                    letterSpacing: 1,
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
              if (state.heights.isNotEmpty)
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
