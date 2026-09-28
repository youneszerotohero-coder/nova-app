import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/nova_api.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/security/capture_shield.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/json.dart';
import '../../data/models.dart';
import '../../data/playback_diagnostics.dart';
import '../../data/playback_models.dart';
import 'playback_rules.dart';
import 'protected_video.dart';

enum _Stage { idle, checking, playing, failed }

/// Protected lesson player, the mobile counterpart of the web
/// `ProtectedVideoPlayer`: nothing plays until the Student taps
/// "Check & play"; then access is authorized, the device's DRM level is
/// checked against the server policy, and the DASH stream plays under
/// Widevine with the server watermark on top.
///
/// D-070: when the Admin allows it (mode B), a device that cannot play
/// DRM — iPhone until FairPlay, Android without hardware Widevine, or a
/// DRM/decoder failure at runtime — continues on the clear HLS copy with
/// the watermark; mode C serves that copy to everyone.
class LessonPlayer extends StatefulWidget {
  const LessonPlayer({
    super.key,
    required Course this.course,
    required Lesson this.lesson,
    required ValueChanged<Json> this.onProgress,
    this.fullscreen = false,
    this.onToggleFullscreen,
  }) : replayOf = null;

  /// The protected replay of a finished Live: same player and rules,
  /// no progress, watermark from the signed-in Student (web replay).
  const LessonPlayer.replay({
    super.key,
    required LiveSession live,
    this.fullscreen = false,
    this.onToggleFullscreen,
  })  : replayOf = live,
        course = null,
        lesson = null,
        onProgress = null;

  final Course? course;
  final Lesson? lesson;
  final LiveSession? replayOf;

  /// A saved `/progress` response (resume, %, completed) for the lesson.
  final ValueChanged<Json>? onProgress;

  String get mediaKey => lesson != null ? 'lesson-${lesson!.id}' : 'replay-${replayOf!.id}';
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  State<LessonPlayer> createState() => _LessonPlayerState();
}

class _LessonPlayerState extends State<LessonPlayer> with WidgetsBindingObserver {
  /// A clear copy still being prepared is retried on its own (web).
  static const Duration clearUnavailableRetry = Duration(seconds: 20);

  _Stage _stage = _Stage.idle;
  String _phaseKey = 'player.phaseAccess';
  String? _failure;

  /// The failure is shown with neutral wording (clear copy, or modes B/C):
  /// it never speaks of protected media (D-077).
  bool _failureClear = false;
  Timer? _clearRetry;

  /// D-077: a protected picture that never starts goes clear in mode B.
  Timer? _startWatch;
  final Stopwatch _startClock = Stopwatch();
  String? _reportedFailure;
  PlaybackAuthorization? _auth;
  int _start = 0;
  ProtectedVideoController? _video;
  ProgressReporter? _reporter;
  bool _saving = false;
  bool _durationChecked = false;

  final WatermarkPlacer _placer = WatermarkPlacer();
  WatermarkSpot _spot = const WatermarkSpot(top: 0.12, inset: 0.06, right: false);
  Timer? _watermarkTimer;

  bool _controls = true;
  Timer? _hideTimer;
  double _speed = 1;
  int _quality = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CaptureMonitor.instance.addListener(_onCapture);
  }

  @override
  void didUpdateWidget(LessonPlayer old) {
    super.didUpdateWidget(old);
    if (old.mediaKey != widget.mediaKey) _reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CaptureMonitor.instance.removeListener(_onCapture);
    _clearRetry?.cancel();
    _teardown();
    super.dispose();
  }

  // Lifecycle -----------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pauseAndSave();
  }

  /// iOS screen recording/mirroring: stop protected playback (the app
  /// is already blurred by CaptureShield).
  void _onCapture() {
    if (CaptureMonitor.instance.captured) _pauseAndSave();
  }

  void _pauseAndSave() {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    video.pause();
    _save(video.value.position.inSeconds, force: true);
  }

  void _reset() {
    _clearRetry?.cancel();
    _teardown();
    setState(() {
      _stage = _Stage.idle;
      _failure = null;
      _auth = null;
      _reportedFailure = null;
    });
  }

  void _teardown() {
    final ProtectedVideoController? video = _video;
    if (video != null) {
      _save(video.value.position.inSeconds, force: true);
      video
        ..removeListener(_onVideo)
        ..dispose();
    }
    _video = null;
    _watermarkTimer?.cancel();
    _hideTimer?.cancel();
    _startWatch?.cancel();
  }

  String get _content => widget.lesson != null ? 'lesson' : 'replay';
  NovaApi? get _diagnosticsApi =>
      widget.lesson != null ? AppState.instance.learning.api : AppState.instance.live?.api;
  int get _contentId => widget.lesson?.id ?? widget.replayOf!.id;

  /// Texts may speak of protection only in a known mode A (D-077).
  bool get _neutral {
    final PlaybackAuthorization? auth = _auth;
    if (auth != null) return auth.clear || auth.clearDeliveryAvailable;
    return ClearDeliveryMemory.videoNeutral;
  }

  /// The Admin's Videos switch, learnt from each authorization.
  static void _learnMode(PlaybackAuthorization auth, {required bool requestedClear}) {
    ClearDeliveryMemory.videoMode = auth.clear
        ? (requestedClear ? 'drm_with_clear_fallback' : 'clear')
        : auth.clearDeliveryAvailable
            ? 'drm_with_clear_fallback'
            : 'drm_only';
  }

  // Start ---------------------------------------------------------------

  Future<void> _checkAndPlay() => _begin();

  /// Authorizes and starts playback. [clearReason] asks for the clear copy
  /// (`no_drm` / `drm_error`), defaulting to this session's remembered
  /// fallback; [resumeAt] continues where a failed DRM picture stopped.
  Future<void> _begin({String? clearReason, Duration? resumeAt}) async {
    final AppState app = AppScope.of(context);
    _clearRetry?.cancel();
    _teardown();
    setState(() {
      _stage = _Stage.checking;
      _failure = null;
      _failureClear = false;
      _phaseKey = 'player.phaseAccess';
      _durationChecked = false;
    });

    final DrmSupport support = await detectDrmSupport();
    if (!mounted) return;
    // A device with no usable DRM (iPhone until FairPlay, Android without
    // Widevine) asks for the clear copy straight away; mode A refuses it
    // and the device verdict stands.
    final String? noDrm = switch (support) {
      DrmSupport.iosBlocked => 'ios_blocked',
      DrmSupport.none || DrmSupport.unsupported => 'capability',
      _ => null,
    };
    final String? requested = clearReason ?? ClearDeliveryMemory.video ?? (noDrm == null ? null : 'no_drm');

    final PlaybackAuthorization auth;
    try {
      auth = widget.lesson != null
          ? await app.learning.playback(widget.lesson!.id, clear: requested != null)
          : await app.live!.replay(widget.replayOf!.id, clear: requested != null);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'VIDEO_CLEAR_DELIVERY_DISABLED') {
        // The Admin requires DRM again (mode A): forget the fallback.
        ClearDeliveryMemory.video = null;
        ClearDeliveryMemory.videoMode = 'drm_only';
        if (noDrm != null) return _fail(noDrm);
        return _begin();
      }
      if (error.code == 'VIDEO_CLEAR_COPY_UNAVAILABLE') {
        _fail('clear_unavailable', clear: true, phase: 'authorizing', httpStatus: error.status);
        _clearRetry = Timer(clearUnavailableRetry, () {
          if (mounted && _stage == _Stage.failed) _begin(clearReason: requested, resumeAt: resumeAt);
        });
        return;
      }
      return _fail(
        switch (error.code) {
          'PROTECTED_VIDEO_NOT_READY' || 'LIVE_REPLAY_NOT_READY' => 'processing',
          'TOO_MANY_REQUESTS' => 'rate',
          _ when error.status == 403 => 'access',
          _ when error.status == 401 => 'session_expired',
          _ when error.isNetwork => 'timeout',
          _ => 'delivery',
        },
        clear: requested != null || ClearDeliveryMemory.videoNeutral,
        phase: 'authorizing',
        httpStatus: error.status,
      );
    }
    if (!mounted) return;
    _learnMode(auth, requestedClear: requested != null);

    if (!auth.clear) {
      // Strict mode licenses hardware Widevine only; software is allowed
      // only when the server says so — same rule as the web selection.
      setState(() => _phaseKey = auth.clearDeliveryAvailable ? 'player.clearChecking' : 'player.phaseDevice');
      final String? refusal = noDrm ??
          (support == DrmSupport.software && (auth.strict || !auth.softwareFallback) ? 'security' : null);
      if (refusal != null) {
        if (!auth.clearDeliveryAvailable) return _fail(refusal, phase: 'capability');
        ClearDeliveryMemory.video = 'no_drm';
        reportPlaybackDiagnostic(
        _diagnosticsApi,
          content: _content,
          contentId: _contentId,
          event: 'clear_fallback',
          reason: 'no_drm',
          category: refusal,
          phase: 'capability',
        );
        return _begin(clearReason: 'no_drm');
      }
    }

    setState(() => _phaseKey =
        auth.clear || auth.clearDeliveryAvailable ? 'player.clearLoading' : 'player.phaseMedia');
    final int start = auth.clear && resumeAt != null
        ? safeResumeSeconds(resumeAt.inSeconds, auth.durationSeconds)
        : auth.watchAgain
            ? 0
            : safeResumeSeconds(auth.resumeSeconds, auth.durationSeconds);
    final ProtectedVideoController video = ProtectedVideoController()..addListener(_onVideo);
    setState(() {
      _auth = auth;
      _start = start;
      _video = video;
      _reporter = ProgressReporter(initialSeconds: start);
      _stage = _Stage.playing;
      _controls = true;
    });
    _moveWatermark();
    _scheduleHide();
    if (!auth.clear && auth.clearDeliveryAvailable) _watchProtectedStart(video, Duration(seconds: start));
  }

  /// Mode B: a protected picture that never starts although media is
  /// buffered is a DRM failure too (D-077).
  void _watchProtectedStart(ProtectedVideoController video, Duration start) {
    _startWatch?.cancel();
    _startClock
      ..reset()
      ..start();
    _startWatch = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      final VideoState state = video.value;
      if (_video != video || state.firstFrame || _startClock.elapsed > ProtectedStartWatch.giveUp) {
        timer.cancel();
        return;
      }
      if (ProtectedStartWatch.stuck(
        elapsed: _startClock.elapsed,
        firstFrame: state.firstFrame,
        start: start,
        position: state.position,
        buffered: state.buffered,
      )) {
        timer.cancel();
        _failOrFallback('decode', phase: 'first_frame');
      }
    });
  }

  /// Handles a player failure once, after the controller's notification
  /// (the handling disposes that controller).
  void _afterNotification(ProtectedVideoController video, String category) {
    video.removeListener(_onVideo);
    scheduleMicrotask(() {
      if (mounted && _video == video) _failOrFallback(category);
    });
  }

  /// D-077: in mode B any failure of the protected playback continues on
  /// the clear copy from the same position; only a refused authorization
  /// is shown. A protected copy that could not be fetched concerns this
  /// video only and is not remembered for the device.
  void _failOrFallback(String category, {String phase = 'streaming'}) {
    final PlaybackAuthorization? auth = _auth;
    final VideoState? state = _video?.value;
    final String? reason = auth != null && !auth.clear && auth.clearDeliveryAvailable
        ? clearFallbackReason(category)
        : null;
    if (reason != null) {
      final Duration at = state?.position ?? Duration.zero;
      if (reason != 'media_unavailable') ClearDeliveryMemory.video = reason;
      reportPlaybackDiagnostic(
        _diagnosticsApi,
        content: _content,
        contentId: _contentId,
        event: 'clear_fallback',
        reason: reason,
        category: category,
        phase: phase,
        code: state?.errorCode,
        drm: true,
      );
      _begin(clearReason: reason, resumeAt: at);
      return;
    }
    _fail(category, clear: (auth?.clear ?? false) || _neutral, phase: phase, code: state?.errorCode);
  }

  void _fail(String category, {bool clear = false, String? phase, int? code, int? httpStatus}) {
    final bool protectedAttempt = !(_auth?.clear ?? true);
    _teardown();
    // One trace per kind of failure: a copy still being prepared retries
    // every 20 s (web).
    if (_reportedFailure != category) {
      _reportedFailure = category;
      reportPlaybackDiagnostic(
        _diagnosticsApi,
        content: _content,
        contentId: _contentId,
        event: 'error_shown',
        category: category,
        phase: phase,
        code: code,
        httpStatus: httpStatus,
        drm: protectedAttempt,
        neutral: clear,
        clear: !protectedAttempt,
      );
    }
    if (mounted) {
      setState(() {
        _stage = _Stage.failed;
        _failure = category;
        _failureClear = clear;
      });
    }
  }

  // Playback ------------------------------------------------------------

  void _onVideo() {
    final ProtectedVideoController? video = _video;
    final PlaybackAuthorization? auth = _auth;
    if (video == null || auth == null) return;
    final VideoState state = video.value;

    if (state.errorCategory != null) {
      return _afterNotification(video, switch (state.errorCategory!) {
        'expired' => 'session_expired',
        'behind_live' => 'delivery',
        final String category => category,
      });
    }

    if (!_durationChecked && state.duration > Duration.zero) {
      _durationChecked = true;
      if (!durationMatches(auth.durationSeconds, state.duration.inMilliseconds / 1000)) {
        return _afterNotification(video, 'decode');
      }
    }

    final int seconds = state.position.inSeconds;
    if (state.phase == 'ended') {
      _save(state.duration.inSeconds, force: true);
    } else if (!state.playing && state.phase == 'ready') {
      _save(seconds, force: true);
    } else if (_reporter?.due(seconds) ?? false) {
      _save(seconds);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save(int seconds, {bool force = false}) async {
    final PlaybackAuthorization? auth = _auth;
    final ProgressReporter? reporter = _reporter;
    final Lesson? lesson = widget.lesson;
    if (auth == null || reporter == null || lesson == null || _saving) return;
    if (auth.progressSession.isEmpty) return;
    if (!force && !reporter.due(seconds)) return;
    if (force && seconds == reporter.lastSaved) return;
    _saving = true;
    reporter.saved(seconds);
    try {
      final Json row = await AppState.instance.learning.saveProgress(
        lesson.id,
        positionSeconds: seconds,
        session: auth.progressSession,
      );
      widget.onProgress?.call(row);
    } on ApiException catch (error) {
      // The progress session expired or was replaced: playback must be
      // re-authorized before anything else is recorded.
      if (error.code == 'PLAYBACK_SESSION_INVALID' && mounted) _fail('session_expired');
    } finally {
      _saving = false;
    }
  }

  void _moveWatermark() {
    _watermarkTimer?.cancel();
    final PlaybackAuthorization? auth = _auth;
    if (auth == null) return;
    setState(() => _spot = _placer.next());
    // The clear copy moves its watermark as often as software DRM (web).
    _watermarkTimer = Timer(
      _placer.interval(softwareFallback: auth.softwareFallback || auth.clear),
      () => mounted ? _moveWatermark() : null,
    );
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_video?.value.playing ?? false)) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _togglePlay() {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    video.value.playing ? video.pause() : video.play();
    _scheduleHide();
  }

  void _skip(int seconds) {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    final Duration target = video.value.position + Duration(seconds: seconds);
    video.seekTo(target < Duration.zero ? Duration.zero : target);
    _scheduleHide();
  }

  Future<void> _openSettings() async {
    final ProtectedVideoController? video = _video;
    if (video == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => _SettingsSheet(
        speed: _speed,
        quality: _quality,
        heights: video.value.heights,
        onSpeed: (double speed) {
          setState(() => _speed = speed);
          video.setSpeed(speed);
        },
        onQuality: (int height) {
          setState(() => _quality = height);
          video.setQuality(height);
        },
      ),
    );
  }

  // UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Widget box = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_stage == _Stage.playing && _auth != null && _video != null)
            ProtectedVideoView(
              // One native view per controller (see LivePlayer).
              key: ObjectKey(_video),
              manifest: _auth!.clear ? _auth!.manifestUrl : _auth!.dashUrl,
              clear: _auth!.clear,
              licenseUrl: _auth!.widevineLicenseUrl,
              token: _auth!.drmToken,
              startSeconds: _start,
              maxHeight: _auth!.clear ? null : _auth!.maxHeight,
              controller: _video!,
            )
          else
            Opacity(
              opacity: _stage == _Stage.idle ? 1 : 0.35,
              child: NovaSceneImage(
                scene: widget.course?.scene ?? widget.replayOf!.scene,
                image: widget.course?.image ?? widget.replayOf!.image,
                icon: widget.course?.icon ?? Icons.movie_rounded,
                iconScale: 0.9,
              ),
            ),
          if (_stage == _Stage.playing) ..._playingLayers(context),
          if (_stage == _Stage.idle) _center(_checkButton(context)),
          if (_stage == _Stage.checking) _center(_checking(context)),
          if (_stage == _Stage.failed) _center(_failed(context)),
          Positioned(
            top: 10,
            left: 10,
            child: ProtectedBadge(clear: _neutral),
          ),
        ],
      ),
    );

    if (widget.fullscreen) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(aspectRatio: 16 / 9, child: box),
    );
  }

  List<Widget> _playingLayers(BuildContext context) {
    final PlaybackAuthorization auth = _auth!;
    final VideoState state = _video!.value;
    final Duration duration = state.duration > Duration.zero
        ? state.duration
        : Duration(milliseconds: (auth.durationSeconds * 1000).round());

    return [
      // The watermark is drawn over the video and the controls, never
      // under them, and ignores touches (web: pointer-events none).
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => IgnorePointer(
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeInOutCubic,
                top: box.maxHeight * _spot.top,
                left: _spot.right ? null : box.maxWidth * _spot.inset,
                right: _spot.right ? box.maxWidth * _spot.inset : null,
                child: PlayerWatermark(
                  name: auth.watermarkName.isNotEmpty
                      ? auth.watermarkName
                      : AppScope.of(context).profile?.fullName ?? '',
                  phone: auth.watermarkPhone.isNotEmpty
                      ? auth.watermarkPhone
                      : AppScope.of(context).profile?.phone ?? '',
                  session: auth.watermarkSession.isEmpty
                      ? _placer.rotationTag
                      : '${auth.watermarkSession}-${_placer.rotationTag}',
                  strong: auth.softwareFallback || auth.clear,
                ),
              ),
            ],
          ),
        ),
      ),
      if (state.phase == 'buffering' || state.phase == 'idle')
        const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
          ),
        ),
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleControls,
          onDoubleTapDown: (TapDownDetails d) => _skip(
            d.localPosition.dx < (context.size?.width ?? 0) / 2 ? -10 : 10,
          ),
        ),
      ),
      AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _controls ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_controls,
          child: _Controls(
            state: state,
            duration: duration,
            fullscreen: widget.fullscreen,
            onPlay: _togglePlay,
            onBack: () => _skip(-10),
            onForward: () => _skip(10),
            onSeek: (Duration d) {
              _video?.seekTo(d);
              _scheduleHide();
            },
            onSettings: _openSettings,
            onFullscreen: widget.onToggleFullscreen,
          ),
        ),
      ),
    ];
  }

  Widget _center(Widget child) => Center(
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      );

  Widget _checkButton(BuildContext context) {
    return PressableScale(
      onTap: _checkAndPlay,
      pressedScale: 0.94,
      semanticLabel: context.tr(_neutral ? 'player.play' : 'player.checkPlay'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              context.tr(_neutral ? 'player.play' : 'player.checkPlay'),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checking(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text(
          context.tr(_phaseKey),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final String category = _failure ?? 'delivery';
    final bool retryable = category != 'ios_blocked' && category != 'security' &&
        category != 'capability' && category != 'access';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          category == 'processing' || category == 'clear_unavailable'
              ? Icons.hourglass_top_rounded
              : Icons.shield_outlined,
          size: 30,
          color: Colors.white,
        ),
        const SizedBox(height: 10),
        Text(
          context.tr(playerFailureKey(category, clear: _failureClear)),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            height: 1.4,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        if (retryable)
          PressableScale(
            onTap: _checkAndPlay,
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
          )
        else
          Text(
            _auth?.supportUrl ?? 'noova.elearning@gmail.com',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
      ],
    );
  }
}

/// String key of a playback failure. On the clear copy the messages never
/// speak of protected media (web `getLocalizedClearFailureMessage`).
String playerFailureKey(String category, {required bool clear}) {
  if (category == 'clear_unavailable' || category == 'access' || category == 'rate') {
    return 'player.err.$category';
  }
  if (!clear) return 'player.err.$category';
  return switch (category) {
    'processing' || 'timeout' || 'session_expired' || 'decode' => 'player.clearErr.$category',
    _ => 'player.clearErr.delivery',
  };
}

class ProtectedBadge extends StatelessWidget {
  const ProtectedBadge({super.key, this.clear = false});

  /// The clear copy (D-070): a personal copy under the identity watermark.
  final bool clear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(clear ? Icons.badge_rounded : Icons.shield_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            context.tr(clear ? 'player.clearBadge' : 'player.protected'),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 10,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full name, full phone and the rotating session reference (D-029).
class PlayerWatermark extends StatelessWidget {
  const PlayerWatermark({
    super.key,
    required this.name,
    required this.phone,
    required this.session,
    required this.strong,
  });

  final String name;
  final String phone;
  final String session;

  /// Stronger contrast under software DRM, as on the web.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: strong ? 0.6 : 0.46),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
          height: 1.35,
          color: Colors.white.withValues(alpha: strong ? 0.9 : 0.78),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, size: 10, color: Colors.white.withValues(alpha: 0.78)),
                const SizedBox(width: 3),
                Text('$phone · $session'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.duration,
    required this.fullscreen,
    required this.onPlay,
    required this.onBack,
    required this.onForward,
    required this.onSeek,
    required this.onSettings,
    required this.onFullscreen,
  });

  final VideoState state;
  final Duration duration;
  final bool fullscreen;
  final VoidCallback onPlay;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSettings;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    final double total = duration.inMilliseconds.toDouble();
    final double position = state.position.inMilliseconds.clamp(0, total).toDouble();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x00000000), Color(0xAA000000)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoundButton(icon: Icons.replay_10_rounded, label: '-10 s', onTap: onBack),
                const SizedBox(width: 22),
                _RoundButton(
                  icon: state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: state.playing ? 'Pause' : 'Play',
                  size: 60,
                  onTap: onPlay,
                ),
                const SizedBox(width: 22),
                _RoundButton(icon: Icons.forward_10_rounded, label: '+10 s', onTap: onForward),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 6,
            bottom: 4,
            child: Row(
              children: [
                Text(
                  '${clockLabel(state.position)} / ${clockLabel(duration)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: NovaColors.accent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: total <= 0 ? 0 : position,
                      max: total <= 0 ? 1 : total,
                      onChanged: total <= 0 ? null : (_) {},
                      onChangeEnd: (double v) => onSeek(Duration(milliseconds: v.round())),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onSettings,
                  tooltip: context.tr('player.settings'),
                  icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                ),
                if (onFullscreen != null)
                  IconButton(
                    onPressed: onFullscreen,
                    tooltip: context.tr('player.fullscreen'),
                    icon: Icon(
                      fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.size = 46});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.9,
      semanticLabel: label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}

/// Speeds and quality, the same choices as the web settings menu.
class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.speed,
    required this.quality,
    required this.heights,
    required this.onSpeed,
    required this.onQuality,
  });

  final double speed;
  final int quality;
  final List<int> heights;
  final ValueChanged<double> onSpeed;
  final ValueChanged<int> onQuality;

  static const List<double> _speeds = <double>[0.75, 1, 1.25, 1.5, 2];

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) => PressableScale(
          onTap: () {
            onTap();
            Navigator.of(context).pop();
          },
          semanticLabel: label,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? NovaColors.ink950 : NovaColors.subtleFill,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              label,
              style: NovaTypography.textTheme.labelMedium!.copyWith(
                color: selected ? Colors.white : NovaColors.textStrong,
              ),
            ),
          ),
        );

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
          Text(context.tr('player.speed'), style: NovaTypography.textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final double s in _speeds)
                chip(s == 1 ? context.tr('player.normal') : '${s}x', s == speed, () => onSpeed(s)),
            ],
          ),
          if (heights.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(context.tr('player.quality'), style: NovaTypography.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(context.tr('player.auto'), quality == 0, () => onQuality(0)),
                for (final int h in heights) chip('${h}p', quality == h, () => onQuality(h)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
