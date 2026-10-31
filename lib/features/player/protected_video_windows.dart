part of 'protected_video.dart';

/// The NOVA PC app's player surface (owner decision 2026-10-29).
///
/// Flutter on Windows has no platform views, and a PlayReady picture can
/// never be copied into a Flutter texture. The native side
/// (`windows/runner/protected_player.cpp`) therefore plays the video in its
/// own capture-protected window (black in captures, D-188), directly behind
/// the app window. This widget leaves a transparent hole where the picture
/// must show and tells the native side where the hole is (physical pixels of
/// the Flutter view) after every frame in which it moved. Everything the page draws over the box —
/// the controls, the moving watermark, sheets and dialogs — stays above the
/// video, exactly as with the phones' platform views.
class _WindowsVideoSurface extends StatefulWidget {
  const _WindowsVideoSurface({required this.params, required this.controller});

  final Map<String, Object?> params;
  final ProtectedVideoController controller;

  static const MethodChannel _players = MethodChannel('nova/protected_player');

  @override
  State<_WindowsVideoSurface> createState() => _WindowsVideoSurfaceState();
}

class _WindowsVideoSurfaceState extends State<_WindowsVideoSurface> {
  final GlobalKey _hole = GlobalKey();
  int? _id;
  bool _disposed = false;

  /// The native window is in place: the hole is punched (black until then,
  /// so the desktop never shows through).
  bool _placed = false;
  Rect? _sent;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _create();
    SchedulerBinding.instance.addPostFrameCallback(_afterFrame);
  }

  Future<void> _create() async {
    try {
      final int? id = await _WindowsVideoSurface._players.invokeMethod<int>('create', widget.params);
      if (id == null) return _failed();
      if (_disposed) {
        // Gone before its window existed.
        await MethodChannel('nova/protected_player_$id').invokeMethod<void>('release');
        return;
      }
      _id = id;
      widget.controller._attach(id);
      _report();
    } on PlatformException {
      _failed();
    } on MissingPluginException {
      _failed();
    }
  }

  void _failed() {
    if (_disposed) return;
    widget.controller.value = widget.controller.value.copyWith(errorCategory: 'capability', errorKind: 'other');
  }

  void _afterFrame(Duration _) {
    if (_disposed) return;
    _report();
    SchedulerBinding.instance.addPostFrameCallback(_afterFrame);
  }

  /// Sends the hole's place when it changed; one call at a time, the latest
  /// place wins.
  void _report() {
    if (_disposed || _sending || _id == null) return;
    final RenderObject? box = _hole.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final double ratio = View.of(context).devicePixelRatio;
    final Rect logical = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    final Rect rect = Rect.fromLTRB(
      logical.left * ratio,
      logical.top * ratio,
      logical.right * ratio,
      logical.bottom * ratio,
    );
    final Rect? sent = _sent;
    if (sent != null &&
        (sent.left - rect.left).abs() < 0.5 &&
        (sent.top - rect.top).abs() < 0.5 &&
        (sent.right - rect.right).abs() < 0.5 &&
        (sent.bottom - rect.bottom).abs() < 0.5) {
      return;
    }
    _sent = rect;
    _sending = true;
    widget.controller._setRect(rect, visible: true).then((_) {
      _sending = false;
      if (_disposed) return;
      if (!_placed) setState(() => _placed = true);
      _report();
    }, onError: (Object _) {
      _sending = false;
    });
  }

  @override
  void dispose() {
    // The controller's owner releases the native player (dispose), which
    // keeps its window a moment, until this hole is gone from the screen.
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _VideoHole(key: _hole, punched: _placed);
}

class _VideoHole extends LeafRenderObjectWidget {
  const _VideoHole({super.key, required this.punched});

  final bool punched;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderVideoHole(punched);

  @override
  void updateRenderObject(BuildContext context, _RenderVideoHole renderObject) {
    renderObject.punched = punched;
  }
}

/// Clears its pixels to transparent (the app window composes with per-pixel
/// alpha while a video window exists), so the video window behind shows.
class _RenderVideoHole extends RenderBox {
  _RenderVideoHole(this._punched);

  bool _punched;

  set punched(bool value) {
    if (value == _punched) return;
    _punched = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.biggest.isFinite ? constraints.biggest : constraints.smallest;

  // Its own layer, so the clear never ends up inside a cached picture
  // (raster cache) where it would erase the cache instead of the window.
  @override
  bool get isRepaintBoundary => true;

  // Taps go to the player's own gesture layers above.
  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.setWillChangeHint();
    context.canvas.drawRect(
      offset & size,
      Paint()
        ..color = const Color(0xFF000000)
        ..blendMode = _punched ? BlendMode.clear : BlendMode.srcOver,
    );
  }
}
