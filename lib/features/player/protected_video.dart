import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';


/// Device support for protected playback.
enum DrmSupport {
  /// Android with hardware Widevine (L1): strict policy playable.
  hardware,

  /// Android with software Widevine only (L3): playable only when the
  /// server allows software fallback.
  software,

  /// Android without Widevine.
  none,

  /// iPhone/iPad: FairPlay on AVPlayer (D-118), when the server offers it.
  fairplay,

  /// Anything else (tests, desktop).
  unsupported,
}

/// Temporary build switch (owner request 2026-10-06, D-120):
/// `--dart-define=NOVA_CLEAR_ONLY=true` reports no DRM, so the app asks for
/// the clear copy; FLAG_SECURE, the capture guard and the watermark stay.
/// The server still decides: the clear copy is refused in mode A.
const bool clearOnlyBuild = bool.fromEnvironment('NOVA_CLEAR_ONLY');

Future<DrmSupport> detectDrmSupport() async {
  if (kIsWeb || clearOnlyBuild) return DrmSupport.unsupported;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return DrmSupport.fairplay;
    case TargetPlatform.android:
      try {
        final String? level =
            await const MethodChannel('nova/drm').invokeMethod<String>('widevineLevel');
        return switch (level) {
          'L1' => DrmSupport.hardware,
          null => DrmSupport.none,
          _ => DrmSupport.software,
        };
      } on PlatformException {
        return DrmSupport.none;
      } on MissingPluginException {
        return DrmSupport.unsupported;
      }
    default:
      return DrmSupport.unsupported;
  }
}

/// Live state of the native player.
class VideoState {
  const VideoState({
    this.phase = 'idle',
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.heights = const <int>[],
    this.firstFrame = false,
    this.liveOffset,
    this.errorCategory,
    this.errorKind,
    this.errorCode = 0,
    this.licenseStatus = 0,
  });

  /// idle | buffering | ready | ended.
  final String phase;
  final bool playing;
  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// Available video heights (within the server cap), highest first.
  final List<int> heights;

  /// A decoded frame has been shown (web `first_frame`).
  final bool firstFrame;

  /// Distance behind the live edge (Lives only).
  final Duration? liveOffset;

  /// Set when the native player failed (web failure categories).
  final String? errorCategory;

  /// `drm`, `decoder` or `other`: what failed (D-070 fallback reason).
  final String? errorKind;

  /// Native error code (Media3 `PlaybackException.errorCode`, AVFoundation
  /// code on iPhone), telemetry `error_data_code`.
  final int errorCode;

  /// HTTP status of the last licence exchange, telemetry `license_status`.
  final int licenseStatus;

  VideoState copyWith({
    String? phase,
    bool? playing,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    List<int>? heights,
    bool? firstFrame,
    Duration? liveOffset,
    String? errorCategory,
    String? errorKind,
    int? errorCode,
    int? licenseStatus,
  }) =>
      VideoState(
        phase: phase ?? this.phase,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
        heights: heights ?? this.heights,
        firstFrame: firstFrame ?? this.firstFrame,
        liveOffset: liveOffset ?? this.liveOffset,
        errorCategory: errorCategory ?? this.errorCategory,
        errorKind: errorKind ?? this.errorKind,
        errorCode: errorCode ?? this.errorCode,
        licenseStatus: licenseStatus ?? this.licenseStatus,
      );
}

/// Commands and state for one native `ProtectedPlayerView`.
class ProtectedVideoController extends ValueNotifier<VideoState> {
  ProtectedVideoController() : super(const VideoState());

  MethodChannel? _methods;
  StreamSubscription<dynamic>? _events;

  void _attach(int viewId) {
    // A new native view for this controller: the previous one must stop,
    // or its sound goes on behind the new picture (iPhone keeps it alive).
    _events?.cancel();
    _methods?.invokeMethod<void>('release').catchError((Object _) {});
    _methods = MethodChannel('nova/protected_player_$viewId');
    _events = EventChannel('nova/protected_player_$viewId/events')
        .receiveBroadcastStream()
        .listen(_onEvent, onError: (Object _) {
      value = value.copyWith(errorCategory: 'delivery');
    });
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['event']) {
      case 'state':
        value = value.copyWith(phase: '${event['state']}');
      case 'playing':
        value = value.copyWith(playing: event['value'] == true);
      case 'position':
        value = value.copyWith(
          position: Duration(milliseconds: (event['position'] as num).toInt()),
          duration: Duration(milliseconds: (event['duration'] as num).toInt()),
          buffered: Duration(milliseconds: (event['buffered'] as num).toInt()),
          liveOffset: event['liveOffset'] is num && (event['liveOffset'] as num) >= 0
              ? Duration(milliseconds: (event['liveOffset'] as num).toInt())
              : null,
        );
      case 'firstFrame':
        value = value.copyWith(firstFrame: true);
      case 'tracks':
        value = value.copyWith(
          heights: <int>[for (final Object? h in event['heights'] as List) (h as num).toInt()],
        );
      case 'error':
        value = value.copyWith(
          errorCategory: '${event['category']}',
          errorKind: event['kind'] is String ? event['kind'] as String : 'other',
          errorCode: event['code'] is num ? (event['code'] as num).toInt() : 0,
          licenseStatus: event['licenseStatus'] is num ? (event['licenseStatus'] as num).toInt() : 0,
          playing: false,
        );
    }
  }

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    await _methods?.invokeMethod<void>(method, args);
  }

  Future<void> play() => _call('play');
  Future<void> pause() => _call('pause');
  Future<void> seekTo(Duration position) =>
      _call('seekTo', <String, Object>{'ms': position.inMilliseconds});
  Future<void> setSpeed(double speed) => _call('setSpeed', <String, Object>{'speed': speed});

  /// 0 = automatic.
  Future<void> setQuality(int height) => _call('setQuality', <String, Object>{'height': height});
  Future<void> setVolume(double volume) => _call('setVolume', <String, Object>{'volume': volume});
  Future<void> seekToLiveEdge() => _call('seekToLiveEdge');

  /// A renewed Live entitlement for future licence requests.
  Future<void> renewToken(String token) => _call('renewToken', <String, Object>{'token': token});

  @override
  void dispose() {
    _events?.cancel();
    _call('release');
    super.dispose();
  }
}

/// The native player surface. Android: Media3 on a secure SurfaceView,
/// embedded with hybrid composition (a Widevine L1 decoder can only render
/// to a real SurfaceView), for both DRM and the clear copy. iPhone:
/// AVPlayer, FairPlay HLS (D-118) or the clear copy.
class ProtectedVideoView extends StatelessWidget {
  const ProtectedVideoView({
    super.key,
    required this.manifest,
    required this.controller,
    this.licenseUrl = '',
    this.certificateUrl = '',
    this.token = '',
    this.clear = false,
    this.startSeconds = 0,
    this.maxHeight,
    this.live = false,
  });

  final String manifest;
  final String licenseUrl;

  /// FairPlay application certificate (iPhone only).
  final String certificateUrl;
  final String token;

  /// The D-070 clear HLS copy: no DRM, watermark only.
  final bool clear;
  final int startSeconds;
  final int? maxHeight;
  final bool live;
  final ProtectedVideoController controller;

  static const String viewType = 'nova/protected-player';
  static const String iosViewType = 'nova/clear-player';

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?> params = <String, Object?>{
      'manifest': manifest,
      'clear': clear,
      'license': licenseUrl,
      'certificate': certificateUrl,
      'token': token,
      'startMs': startSeconds * 1000,
      'maxHeight': maxHeight,
      'live': live,
    };
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: iosViewType,
        layoutDirection: TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        onPlatformViewCreated: controller._attach,
      );
    }
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (BuildContext context, PlatformViewController view) =>
          AndroidViewSurface(
        controller: view as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (PlatformViewCreationParams create) {
        final AndroidViewController view =
            PlatformViewsService.initExpensiveAndroidView(
          id: create.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => create.onFocusChanged(true),
        );
        view
          ..addOnPlatformViewCreatedListener(create.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(controller._attach)
          ..create();
        return view;
      },
    );
  }
}
