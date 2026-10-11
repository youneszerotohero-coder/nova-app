import 'package:flutter/material.dart';

import 'nova_colors.dart';

/// Nova type scale, the website's (D-125 `hero.css`): Baloo Bhaijaan 2 for
/// titles (`--hx-font`), Geist for Latin text with Baloo for every Arabic
/// glyph (`--hx-font-body`). No negative tracking: it breaks Arabic joins.
abstract final class NovaTypography {
  static const String body = 'Geist';
  static const String display = 'BalooBhaijaan2';

  /// Arabic letters are not in Geist: they come from Baloo, as on the web.
  static const List<String> fallback = <String>[display];

  static Color get _strong => NovaColors.textStrong;
  static const Color _onDark = NovaColors.textOnDark;

  static TextStyle _title(double size, FontWeight weight, double height) => TextStyle(
        fontFamily: display,
        fontFamilyFallback: fallback,
        fontWeight: weight,
        fontSize: size,
        height: height,
        color: _strong,
      );

  static TextStyle _text(double size, FontWeight weight, double height, [Color? color]) => TextStyle(
        fontFamily: body,
        fontFamilyFallback: fallback,
        fontWeight: weight,
        fontSize: size,
        height: height,
        color: color ?? _strong,
      );

  /// Rebuilt on every access so the text picks up the active palette.
  static TextTheme get textTheme => TextTheme(
        displayLarge: _title(36, FontWeight.w800, 1.15),
        displayMedium: _title(30, FontWeight.w800, 1.15),
        displaySmall: _title(26, FontWeight.w800, 1.18),
        headlineMedium: _title(22, FontWeight.w800, 1.2),
        headlineSmall: _title(19, FontWeight.w800, 1.25),
        titleLarge: _title(18, FontWeight.w700, 1.3),
        titleMedium: _title(16, FontWeight.w700, 1.3),
        titleSmall: _title(14.5, FontWeight.w700, 1.3),
        bodyLarge: _text(15.5, FontWeight.w500, 1.5),
        bodyMedium: _text(14.5, FontWeight.w400, 1.5),
        bodySmall: _text(13, FontWeight.w400, 1.45, NovaColors.textMuted),
        labelLarge: _title(15, FontWeight.w700, 1.25),
        labelMedium: _title(13.5, FontWeight.w700, 1.25),
        labelSmall: _title(12, FontWeight.w700, 1.25),
      );

  /// White variants for text sitting on dark ink or on imagery.
  static TextStyle onDark(TextStyle base) =>
      base.copyWith(color: _onDark, shadows: null);

  static TextStyle muted(TextStyle base) =>
      base.copyWith(color: NovaColors.textMuted);
}
