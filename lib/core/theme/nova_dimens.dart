import 'package:flutter/material.dart';

/// Shared metrics: the generous radii, spacing rhythm and soft shadows
/// of the visual direction.
abstract final class NovaDimens {
  // Screen and section rhythm.
  static const double screenPadding = 20;
  static const double sectionGap = 30;
  static const double itemGap = 12;

  // Corner radii: the website's `--hx-r-*` (12 / 17 / 24 / 32) and its
  // 26 px product cards.
  static const double radiusSmall = 12;
  static const double radiusControl = 17;
  static const double radiusCard = 26;
  static const double radiusCardLarge = 32;
  static const double radiusHero = 32;
  static const double radiusTile = 24;
  static const double radiusInner = 18;
  static const double radiusChip = 100;

  // Controls.
  static const double circleButtonSize = 52;
  static const double avatarSize = 44;
  static const double bottomBarHeight = 68;

  /// `--hx-shadow`.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(offset: Offset(0, 1), color: Color(0x0A121A33)),
    BoxShadow(
      offset: Offset(0, 18),
      blurRadius: 40,
      spreadRadius: -30,
      color: Color(0x61121A33),
    ),
  ];

  /// `--hx-shadow-lift`.
  static const List<BoxShadow> shadowLift = [
    BoxShadow(offset: Offset(0, 1), color: Color(0x0D121A33)),
    BoxShadow(
      offset: Offset(0, 26),
      blurRadius: 46,
      spreadRadius: -28,
      color: Color(0x73121A33),
    ),
  ];

  /// The website's floating bottom bar shadow.
  static const List<BoxShadow> shadowFloating = [
    BoxShadow(
      offset: Offset(0, 18),
      blurRadius: 40,
      spreadRadius: -12,
      color: Color(0x8C0A1020),
    ),
  ];

  static const List<BoxShadow> shadowAccent = [
    BoxShadow(
      offset: Offset(0, 14),
      blurRadius: 26,
      spreadRadius: -16,
      color: Color(0x8C121A33),
    ),
  ];

  /// Barely-there lift for pastel cards, which carry their own
  /// hue-tinted glow via `NovaHue.shadow`.
  static const List<BoxShadow> shadowSoft = [
    BoxShadow(offset: Offset(0, 1), color: Color(0x0A121A33)),
    BoxShadow(
      offset: Offset(0, 18),
      blurRadius: 40,
      spreadRadius: -30,
      color: Color(0x61121A33),
    ),
  ];

  static ShapeBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radiusCard),
  );

  static ShapeBorder pillShape = const StadiumBorder();
}
