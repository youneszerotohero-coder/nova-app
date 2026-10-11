import 'package:flutter/material.dart';

import 'nova_colors.dart';

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

  static bool get _dark => NovaColors.current.isDark;

  /// `--hx-shadow` (its `.dark` value in dark mode).
  static List<BoxShadow> get shadowCard => _dark
      ? const [
          BoxShadow(offset: Offset(0, 1), color: Color(0x08FFFFFF)),
          BoxShadow(offset: Offset(0, 22), blurRadius: 44, spreadRadius: -30, color: Color(0xCC000000)),
        ]
      : const [
          BoxShadow(offset: Offset(0, 1), color: Color(0x0A121A33)),
          BoxShadow(offset: Offset(0, 18), blurRadius: 40, spreadRadius: -30, color: Color(0x61121A33)),
        ];

  /// `--hx-shadow-lift`.
  static List<BoxShadow> get shadowLift => _dark
      ? const [
          BoxShadow(offset: Offset(0, 1), color: Color(0x0AFFFFFF)),
          BoxShadow(offset: Offset(0, 28), blurRadius: 50, spreadRadius: -28, color: Color(0xE6000000)),
        ]
      : const [
          BoxShadow(offset: Offset(0, 1), color: Color(0x0D121A33)),
          BoxShadow(offset: Offset(0, 26), blurRadius: 46, spreadRadius: -28, color: Color(0x73121A33)),
        ];

  /// `--hx-shadow-sticker`: chips, tags and tiles that sit on a surface.
  static List<BoxShadow> get shadowSticker => _dark
      ? const [
          BoxShadow(offset: Offset(0, 1), color: Color(0x0AFFFFFF)),
          BoxShadow(offset: Offset(0, 16), blurRadius: 34, spreadRadius: -16, color: Color(0xB3000000)),
        ]
      : const [
          BoxShadow(offset: Offset(0, 1), color: Color(0x0F0A0E16)),
          BoxShadow(offset: Offset(0, 16), blurRadius: 34, spreadRadius: -16, color: Color(0x660A0E16)),
        ];

  /// The website's floating bottom bar shadow (a faint ring in dark mode).
  static List<BoxShadow> get shadowFloating => _dark
      ? const [
          BoxShadow(spreadRadius: 1, color: Color(0x14FFFFFF)),
          BoxShadow(offset: Offset(0, 18), blurRadius: 40, spreadRadius: -12, color: Color(0xB3000000)),
        ]
      : const [
          BoxShadow(offset: Offset(0, 18), blurRadius: 40, spreadRadius: -12, color: Color(0x8C0A1020)),
        ];

  /// `.hxBtn:hover`.
  static const List<BoxShadow> shadowAccent = [
    BoxShadow(
      offset: Offset(0, 14),
      blurRadius: 26,
      spreadRadius: -16,
      color: Color(0x8C121A33),
    ),
  ];

  /// Kept for existing call sites: the card shadow.
  static List<BoxShadow> get shadowSoft => shadowCard;

  static ShapeBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radiusCard),
  );

  static ShapeBorder pillShape = const StadiumBorder();
}
