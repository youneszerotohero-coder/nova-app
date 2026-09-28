import 'package:flutter/material.dart';

import 'nova_colors.dart';
import 'nova_typography.dart';

/// Pushed-page transition: the arriving page slides in from the reading
/// end while the page it covers drifts a quarter the other way.
///
/// Translation only, on purpose: fading or scaling whole pages makes the
/// GPU composite both screens off-screen on every frame, which stuttered
/// on the average Android phones Students use (owner test, 2026-09-27).
class NovaPageTransitionsBuilder extends PageTransitionsBuilder {
  const NovaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Arabic reads right to left: pages arrive from the left.
    final double direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.fastOutSlowIn.flipped,
    );
    final Animation<double> covered = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.fastOutSlowIn.flipped,
    );

    return SlideTransition(
      position: Tween<Offset>(begin: Offset(direction, 0), end: Offset.zero).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset.zero, end: Offset(-0.25 * direction, 0)).animate(covered),
        // The page's own layers stay cached while it moves.
        child: RepaintBoundary(child: child),
      ),
    );
  }
}

/// Builds the Nova MaterialApp themes on top of the raw tokens.
/// The single [current] theme reads the active palette, which the app
/// swaps when dark mode toggles — light and dark are the same builder.
abstract final class NovaTheme {
  static ThemeData get current => _base(NovaColors.paper, NovaColors.textStrong);

  /// Kept for existing call sites; resolves against the active palette.
  static ThemeData get light => current;
  static ThemeData get dark => _base(NovaColors.ink950, NovaColors.textOnDark);

  static ThemeData _base(Color scaffold, Color foreground) {
    final ColorScheme scheme = ColorScheme.light(
      primary: NovaColors.ink900,
      onPrimary: NovaColors.textOnDark,
      secondary: NovaColors.accent,
      onSecondary: Colors.white,
      surface: scaffold,
      onSurface: foreground,
      error: NovaColors.heartRed,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: NovaTypography.textTheme,
      splashFactory: InkSparkle.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      iconTheme: IconThemeData(color: NovaColors.textStrong, size: 22),
      dividerTheme: DividerThemeData(color: NovaColors.borderOnLight),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: NovaPageTransitionsBuilder(),
          TargetPlatform.iOS: NovaPageTransitionsBuilder(),
          TargetPlatform.windows: NovaPageTransitionsBuilder(),
        },
      ),
    );
  }
}
