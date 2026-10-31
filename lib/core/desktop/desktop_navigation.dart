import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_layout.dart';

/// D-188, PC app: a pushed page appears with a short fade (≤ 150 ms) instead
/// of the phone's slide, centred in the desktop content column.
class DesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const DesktopPageTransitionsBuilder();

  @override
  Duration get transitionDuration => DesktopMetrics.pageTransition;

  @override
  Duration get reverseTransitionDuration => DesktopMetrics.pageTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The root page (the shells, sign-in) lays itself out; pushed pages sit
    // in the centred column.
    final Widget page = route.isFirst ? child : DesktopFrame(child: child);
    // `Opacity`, not `FadeTransition`: at full opacity it adds no layer, so
    // a settled page paints exactly as without a transition (the PC video
    // hole clears the window's pixels, never a cached opacity layer).
    return AnimatedBuilder(
      animation: animation,
      child: page,
      builder: (BuildContext context, Widget? page) => Opacity(opacity: animation.value, child: page),
    );
  }
}

/// Keeps the root navigator's route stack, so a key press knows whether the
/// top route is a page that can go back.
class DesktopRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  Route<dynamic>? get top => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final int index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
  }
}

/// D-188, PC app: Esc and the mouse's back button go back from a pushed page
/// (as the page's Back pill, so a page that guards its exit, like a
/// full-screen player, handles it). Dialogs and sheets keep Flutter's own Esc;
/// Esc while typing in a field does nothing.
class DesktopBackKeys extends StatefulWidget {
  const DesktopBackKeys({super.key, required this.navigatorKey, required this.observer, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final DesktopRouteObserver observer;
  final Widget child;

  @override
  State<DesktopBackKeys> createState() => _DesktopBackKeysState();
}

class _DesktopBackKeysState extends State<DesktopBackKeys> {
  @override
  void initState() {
    super.initState();
    if (isDesktopApp) HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    if (isDesktopApp) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    return _back();
  }

  /// Pops the top route when it is a pushed page (not the root, a dialog or
  /// a sheet, which handle Esc themselves).
  bool _back() {
    final Route<dynamic>? top = widget.observer.top;
    final NavigatorState? navigator = widget.navigatorKey.currentState;
    if (navigator == null || top is! PageRoute || top.isFirst || !top.isCurrent) return false;
    navigator.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) return widget.child;
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if (event.kind == PointerDeviceKind.mouse && event.buttons & kBackMouseButton != 0) _back();
      },
      child: widget.child,
    );
  }
}
