import 'package:flutter/material.dart';

import 'nova_colors.dart';

/// Nova type scale. Inter for UI, Inter Display for large headlines,
/// with the tight tracking the visual direction uses on big type.
abstract final class NovaTypography {
  static const String _sans = 'Inter';
  static const String _display = 'InterDisplay';

  static Color get _strong => NovaColors.textStrong;
  static const Color _onDark = NovaColors.textOnDark;

  /// Rebuilt on every access so the text picks up the active palette.
  static TextTheme get textTheme => TextTheme(
        displayLarge: TextStyle(
            fontFamily: _display,
            fontWeight: FontWeight.w700,
            fontSize: 36,
            height: 1.08,
            letterSpacing: -1.2,
            color: _strong),
        displayMedium: TextStyle(
            fontFamily: _display,
            fontWeight: FontWeight.w700,
            fontSize: 30,
            height: 1.1,
            letterSpacing: -1.0,
            color: _strong),
        displaySmall: TextStyle(
            fontFamily: _display,
            fontWeight: FontWeight.w700,
            fontSize: 26,
            height: 1.12,
            letterSpacing: -0.8,
            color: _strong),
        headlineMedium: TextStyle(
            fontFamily: _display,
            fontWeight: FontWeight.w700,
            fontSize: 22,
            height: 1.15,
            letterSpacing: -0.5,
            color: _strong),
        headlineSmall: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            height: 1.2,
            letterSpacing: -0.4,
            color: _strong),
        titleLarge: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            height: 1.25,
            letterSpacing: -0.3,
            color: _strong),
        titleMedium: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w600,
            fontSize: 15.5,
            height: 1.3,
            letterSpacing: -0.2,
            color: _strong),
        titleSmall: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
            height: 1.3,
            letterSpacing: -0.1,
            color: _strong),
        bodyLarge: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w500,
            fontSize: 15.5,
            height: 1.4,
            color: _strong),
        bodyMedium: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w400,
            fontSize: 14,
            height: 1.4,
            color: _strong),
        bodySmall: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w400,
            fontSize: 12.5,
            height: 1.35,
            color: NovaColors.textMuted),
        labelLarge: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.2,
            letterSpacing: -0.1,
            color: _strong),
        labelMedium: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            height: 1.2,
            color: _strong),
        labelSmall: TextStyle(
            fontFamily: _sans,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            height: 1.2,
            letterSpacing: 0.2,
            color: _strong),
      );

  /// White variants for text sitting on dark ink or on imagery.
  static TextStyle onDark(TextStyle base) =>
      base.copyWith(color: _onDark, shadows: null);

  static TextStyle muted(TextStyle base) =>
      base.copyWith(color: NovaColors.textMuted);
}
