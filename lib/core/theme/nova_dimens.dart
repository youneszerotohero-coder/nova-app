import 'package:flutter/material.dart';

/// Shared metrics: the generous radii, spacing rhythm and soft shadows
/// of the visual direction.
abstract final class NovaDimens {
  // Screen and section rhythm.
  static const double screenPadding = 20;
  static const double sectionGap = 30;
  static const double itemGap = 12;

  // Corner radii.
  static const double radiusCard = 28;
  static const double radiusCardLarge = 36;
  static const double radiusHero = 34;
  static const double radiusTile = 24;
  static const double radiusInner = 22;
  static const double radiusChip = 100;

  // Controls.
  static const double circleButtonSize = 52;
  static const double avatarSize = 44;
  static const double bottomBarHeight = 68;

  static const List<BoxShadow> shadowCard = [
    BoxShadow(
      offset: Offset(0, 18),
      blurRadius: 40,
      spreadRadius: -18,
      color: Color(0x2E0A1128),
    ),
  ];

  static const List<BoxShadow> shadowFloating = [
    BoxShadow(
      offset: Offset(0, 16),
      blurRadius: 32,
      spreadRadius: -10,
      color: Color(0x400A1128),
    ),
  ];

  static const List<BoxShadow> shadowAccent = [
    BoxShadow(
      offset: Offset(0, 10),
      blurRadius: 24,
      spreadRadius: -6,
      color: Color(0x552B87F7),
    ),
  ];

  /// Barely-there lift for pastel cards, which carry their own
  /// hue-tinted glow via `NovaHue.shadow`.
  static const List<BoxShadow> shadowSoft = [
    BoxShadow(
      offset: Offset(0, 12),
      blurRadius: 30,
      spreadRadius: -14,
      color: Color(0x1E0A1128),
    ),
  ];

  static ShapeBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radiusCard),
  );

  static ShapeBorder pillShape = const StadiumBorder();
}
