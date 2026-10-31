import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'desktop_layout.dart';

/// The app's scroll behaviour. Phones keep Flutter's (unchanged). D-188, PC
/// app: the mouse drags lists too (horizontal rows have no wheel axis), no
/// bounce or overscroll glow, desktop scrollbars.
class NovaScrollBehavior extends MaterialScrollBehavior {
  const NovaScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => isDesktopApp
      ? const <PointerDeviceKind>{
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.unknown,
        }
      : super.dragDevices;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      isDesktopApp ? const ClampingScrollPhysics() : super.getScrollPhysics(context);

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) =>
      isDesktopApp ? child : super.buildOverscrollIndicator(context, child, details);
}

/// D-188: smooth, faster mouse-wheel scrolling in the PC app.
///
/// Flutter applies a wheel notch as one jump (about 100 physical pixels,
/// fewer logical pixels on a 125–150 % Windows display), which feels slow and
/// jerky on long pages. This spreads each notch over the next frames (an
/// ease-out of about 120 ms) and sizes it in logical pixels, as browsers do.
/// It works under every scrollable at once: it reshapes the wheel events
/// before the framework sees them. Trackpad gestures (pan/zoom events), the
/// touch screen and every other pointer event pass through untouched.
class DesktopWheelSmoother {
  DesktopWheelSmoother(this._forward, {this.gain = 1.25, double Function(int viewId)? devicePixelRatio})
      : _ratio = devicePixelRatio ?? _viewRatio;

  /// The framework's own packet handler.
  final ui.PointerDataPacketCallback _forward;

  /// A notch, in logical pixels, is the wheel's physical delta (about 100
  /// per notch with Windows' 3 lines) times [gain].
  final double gain;
  final double Function(int viewId) _ratio;

  /// Share of the remaining distance (logical pixels) applied per 60 Hz
  /// frame.
  static const double _perFrame = 0.38;

  ui.PointerData? _last;
  double _remainingX = 0;
  double _remainingY = 0;
  Duration? _lastTick;
  bool _scheduled = false;

  static double _viewRatio(int viewId) {
    for (final ui.FlutterView view in ui.PlatformDispatcher.instance.views) {
      if (view.viewId == viewId) return view.devicePixelRatio;
    }
    return 1;
  }

  /// Installs the smoother in front of the framework's handler (PC app
  /// only; after `WidgetsFlutterBinding.ensureInitialized`).
  static void install() {
    if (!isDesktopApp) return;
    final ui.PlatformDispatcher dispatcher = ui.PlatformDispatcher.instance;
    final ui.PointerDataPacketCallback? framework = dispatcher.onPointerDataPacket;
    if (framework == null) return;
    final DesktopWheelSmoother smoother = DesktopWheelSmoother(framework);
    dispatcher.onPointerDataPacket = smoother.handle;
  }

  static bool _isWheel(ui.PointerData data) =>
      data.signalKind == ui.PointerSignalKind.scroll && data.kind == ui.PointerDeviceKind.mouse;

  /// Whether a wheel distance is still being played.
  bool get active => _remainingX.abs() >= 0.5 || _remainingY.abs() >= 0.5;

  void handle(ui.PointerDataPacket packet) {
    if (!packet.data.any(_isWheel)) return _forward(packet);
    final List<ui.PointerData> others = <ui.PointerData>[];
    for (final ui.PointerData data in packet.data) {
      if (!_isWheel(data)) {
        others.add(data);
        continue;
      }
      // The notch's physical size, taken as logical pixels (times the gain).
      _remainingX = _join(_remainingX, data.scrollDeltaX * gain);
      _remainingY = _join(_remainingY, data.scrollDeltaY * gain);
      _last = data;
    }
    if (others.isNotEmpty) _forward(ui.PointerDataPacket(data: others));
    _schedule();
  }

  /// A notch in the other direction cancels what was left of the previous.
  static double _join(double remaining, double delta) {
    if (delta == 0) return remaining;
    if (remaining != 0 && remaining.sign != delta.sign) return delta;
    return remaining + delta;
  }

  void _schedule() {
    if (_scheduled || !active) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
    SchedulerBinding.instance.scheduleFrame();
  }

  void _onFrame(Duration timeStamp) {
    _scheduled = false;
    tick(timeStamp);
    _schedule();
  }

  /// Plays the share of the remaining distance due at [timeStamp].
  void tick(Duration timeStamp) {
    final ui.PointerData? last = _last;
    if (last == null || !active) {
      _lastTick = null;
      return;
    }
    final Duration elapsed = _lastTick == null ? const Duration(milliseconds: 16) : timeStamp - _lastTick!;
    _lastTick = timeStamp;
    final double frames = (elapsed.inMicroseconds / 16667).clamp(0.25, 4.0);
    final double share = 1 - math.pow(1 - _perFrame, frames).toDouble();
    final double dx = _step(_remainingX, share);
    final double dy = _step(_remainingY, share);
    _remainingX -= dx;
    _remainingY -= dy;
    if (!active) {
      _remainingX = 0;
      _remainingY = 0;
      _lastTick = null;
    }
    if (dx == 0 && dy == 0) return;
    _forward(ui.PointerDataPacket(data: <ui.PointerData>[_copy(last, dx, dy)]));
  }

  /// At least one pixel per frame, and the rest once it is small.
  static double _step(double remaining, double share) {
    if (remaining.abs() < 0.5) return 0;
    final double step = remaining * share;
    if (remaining.abs() <= 2 || step.abs() >= remaining.abs()) return remaining;
    return step.abs() < 1 ? remaining.sign : step;
  }

  /// [data] with a new physical delta (the framework divides it by the
  /// view's pixel ratio again).
  ui.PointerData _copy(ui.PointerData data, double logicalDx, double logicalDy) {
    final double ratio = _ratio(data.viewId);
    return ui.PointerData(
      viewId: data.viewId,
      embedderId: data.embedderId,
      timeStamp: data.timeStamp,
      change: data.change,
      kind: data.kind,
      signalKind: data.signalKind,
      device: data.device,
      pointerIdentifier: data.pointerIdentifier,
      physicalX: data.physicalX,
      physicalY: data.physicalY,
      buttons: data.buttons,
      scrollDeltaX: logicalDx * ratio,
      scrollDeltaY: logicalDy * ratio,
    );
  }
}
