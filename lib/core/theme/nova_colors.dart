import 'package:flutter/material.dart';

import 'nova_dimens.dart';

/// Theme-dependent tones: the website's `hero.css` tokens and their `.dark`
/// values (D-134: the blue family, the status tones, the product card and
/// the bottom bar change in dark mode too, as on the website).
class NovaPalette {
  const NovaPalette({
    required this.paper,
    required this.paperPublic,
    required this.paperCard,
    required this.paperRaised,
    required this.textStrong,
    required this.textBody,
    required this.textMuted,
    required this.borderOnLight,
    required this.lineStrong,
    required this.blueLine,
    required this.accentMist,
    required this.accent,
    required this.accentDeep,
    required this.accentDark,
    required this.live,
    required this.replay,
    required this.quiz,
    required this.danger,
    required this.dangerBg,
    required this.navBar,
    required this.productCard,
    required this.isDark,
  });

  /// The Student space's page (`dashboard.css`; `#101216` in dark mode).
  final Color paper;

  /// Catalogue, detail and cart pages (`--hx-bg`).
  final Color paperPublic;
  final Color paperCard;
  final Color paperRaised;
  final Color textStrong;

  /// `--hx-ink-2`: lead text, card text, counts.
  final Color textBody;
  final Color textMuted;
  final Color borderOnLight;

  /// `--hx-line-strong`: ghost buttons, fields, dashed empty states.
  final Color lineStrong;

  /// `--hx-blue-line`: dashed strips and orbits.
  final Color blueLine;
  final Color accentMist;
  final Color accent;
  final Color accentDeep;
  final Color accentDark;
  final Color live;
  final Color replay;
  final Color quiz;
  final Color danger;
  final Color dangerBg;

  /// The phone bottom bar pill.
  final Color navBar;

  /// The navy catalogue card (`.novaCard`).
  final Color productCard;

  /// Lets hue surfaces flip from pastel tints to deep translucent
  /// washes without every call site branching.
  final bool isDark;

  /// The website's hero tokens (D-125, `hero.css`): page `--hx-bg`, white
  /// surfaces, `--hx-ink` text, `--hx-mute` secondary text.
  static const NovaPalette light = NovaPalette(
    paper: Color(0xFFF3F6FC),
    paperPublic: Color(0xFFF3F6FC),
    paperCard: Color(0xFFFFFFFF),
    paperRaised: Color(0xFFF6F8FD),
    textStrong: Color(0xFF121A33),
    textBody: Color(0xFF46506A),
    textMuted: Color(0xFF6F7892),
    borderOnLight: Color(0x1A121A33),
    lineStrong: Color(0x2E121A33),
    blueLine: Color(0x331F54D6),
    accentMist: Color(0xFFE9F0FF),
    accent: Color(0xFF1F54D6),
    accentDeep: Color(0xFF1846B8),
    accentDark: Color(0xFF10276B),
    live: Color(0xFF1F9A58),
    replay: Color(0xFF2F86DA),
    quiz: Color(0xFFA8740A),
    danger: Color(0xFFCF3434),
    dangerBg: Color(0x1FDC3C3C),
    navBar: Color(0xFF121A33),
    productCard: Color(0xFF141C3A),
    isDark: false,
  );

  /// The website's `.dark` hero tokens; the Student space page is `#101216`
  /// (`dark-mode.css`), the public pages `--hx-bg`.
  static const NovaPalette dark = NovaPalette(
    paper: Color(0xFF101216),
    paperPublic: Color(0xFF0B1126),
    paperCard: Color(0xFF131B36),
    paperRaised: Color(0xFF182143),
    textStrong: Color(0xFFEEF2FF),
    textBody: Color(0xFFB9C3DF),
    textMuted: Color(0xFF8C97B8),
    borderOnLight: Color(0x1AFFFFFF),
    lineStrong: Color(0x2EFFFFFF),
    blueLine: Color(0x477AA0FF),
    accentMist: Color(0x293567EA),
    accent: Color(0xFF3567EA),
    accentDeep: Color(0xFF4A78F0),
    accentDark: Color(0xFF0D1F57),
    live: Color(0xFF3FC47F),
    replay: Color(0xFF5AA8F0),
    quiz: Color(0xFFE2A83A),
    danger: Color(0xFFFF6B6B),
    dangerBg: Color(0x24FF6B6B),
    navBar: Color(0xFF0E1636),
    productCard: Color(0xFF18214A),
    isDark: true,
  );
}

/// The tone a surface carries. The website has no pastel family: a card is
/// the neutral `--hx-surface`, and colour only means something — blue (the
/// default), or a status tone with its `--hx-*-bg` (`.hxSticker--live`,
/// `--danger`, `--quiz`). [mint], [rose] and [butter] are those statuses;
/// every other hue is the blue. No gradients, no coloured shadows (D-134).
enum NovaHue {
  sky,
  lilac,
  peach,

  /// `--hx-live` / `--hx-success`.
  mint,

  /// `--hx-quiz` / `--hx-warning`.
  butter,

  /// `--hx-danger`.
  rose,
  ink;

  /// The tone: icons, numbers, active pills.
  Color get solid => switch (this) {
        mint => NovaColors.onlineGreen,
        butter => NovaColors.badgeOrange,
        rose => NovaColors.heartRed,
        _ => NovaColors.accent,
      };

  /// Kept for callers of the old gradient partner: the same tone.
  Color get bright => solid;

  /// A card on any hue is the website's neutral surface.
  Color get surface => NovaColors.paperCard;

  /// Icon tiles and chips: the tone's background (`--hx-blue-soft`,
  /// `--hx-live-bg`…).
  Color get surfaceStrong => switch (this) {
        mint => NovaColors.liveBg,
        butter => NovaColors.quizBg,
        rose => NovaColors.dangerBg,
        _ => NovaColors.accentMist,
      };

  /// Text and icons on [surfaceStrong]: the tone itself.
  Color get onSurface => solid;

  /// Flat: the website paints no hue gradients.
  LinearGradient get gradient => LinearGradient(colors: [solid, solid]);

  /// The neutral `--hx-shadow`, whatever the hue.
  List<BoxShadow> get shadow => NovaDimens.shadowCard;

  /// The website gives subjects and teachers no colour of their own: every
  /// seed is the blue (kept so callers stay unchanged).
  static NovaHue of(String seed) => sky;
}

/// Nova palette = the website's hero tokens (D-125, `website-front/src/hero.css`):
/// royal blue, yellow marker, navy ink, light blue-grey page, white cards.
///
/// The theme-dependent tones resolve against [current], which the app
/// swaps when the user toggles dark mode; every screen rebuilds from
/// the app root at that moment.
abstract final class NovaColors {
  /// The active theme-dependent palette. Swap this (and rebuild the
  /// app) when dark mode toggles.
  static NovaPalette current = NovaPalette.light;

  // Theme-dependent tones.
  static Color get paper => current.paper;
  static Color get paperCard => current.paperCard;
  static Color get paperRaised => current.paperRaised;
  static Color get textStrong => current.textStrong;
  static Color get textMuted => current.textMuted;
  static Color get borderOnLight => current.borderOnLight;
  static Color get accentMist => current.accentMist;
  static Color get paperPublic => current.paperPublic;
  static Color get textBody => current.textBody;
  static Color get lineStrong => current.lineStrong;
  static Color get blueLine => current.blueLine;

  /// Faint neutral wash for inset rows and empty tracks.
  static Color get subtleFill => current.isDark
      ? Colors.white.withValues(alpha: 0.05)
      : const Color(0xFF0A1128).withValues(alpha: 0.04);

  // Dark ink (the website's `--hx-ink` navy): bottom bar and product cards
  // change in dark mode; [ink] stays the fixed navy (text on yellow…).
  static const Color ink = Color(0xFF121A33);
  static Color get ink950 => current.navBar;
  static Color get ink900 => current.productCard;
  static const Color ink800 = Color(0xFF1E2A50);
  static const Color ink700 = Color(0xFF2E3A66);

  // Neutral near-black reserved for the search filter button.
  static const Color nearBlack = Color(0xFF121A33);

  // Text on dark ink surfaces.
  static const Color textOnDark = Color(0xFFF6F5F1);
  static const Color textMutedOnDark = Color(0xFFC4CBE0);

  // Accent: the website's royal blue (`--hx-blue`, `#3567EA` in dark
  // mode); [blue] is the light value where the website keeps it fixed.
  static const Color blue = Color(0xFF1F54D6);
  static Color get accent => current.accent;
  static const Color accentLight = Color(0xFF3F72EA);
  static Color get accentDeep => current.accentDeep;
  static Color get accentDark => current.accentDark;
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentLight, Color(0xFF1846B8)],
  );

  // The website's yellow marker and its ink (`--hx-yellow`).
  static const Color yellow = Color(0xFFFFD54A);
  static const Color yellowInk = Color(0xFF3A2C00);
  static const Color postIt = Color(0xFFFFE38A);
  static const Color postItInk = Color(0xFF4A3B0A);
  static const Color sky = Color(0xFF9FD8FF);
  static const Color skyStrong = Color(0xFF4FACF0);

  // Status tones (`--hx-live`, `--hx-quiz`, `--hx-danger`, `--hx-replay`)
  // and their backgrounds (`--hx-*-bg`).
  static Color get badgeOrange => current.quiz;
  static Color get onlineGreen => current.live;
  static Color get heartRed => current.danger;
  static Color get replay => current.replay;
  static const Color liveBg = Color(0x292FBF71);
  static const Color quizBg = Color(0x3DF5B82E);
  static const Color replayBg = Color(0x2E4FACF0);
  static Color get dangerBg => current.dangerBg;
  static const Color gold = Color(0xFFFFD54A);

  // Hairlines on dark ink.
  static const Color borderOnDark = Color(0x1AFFFFFF);

  // Translucent fills.
  static const Color veilOnImage = Color(0x61121A33);
  static const Color veilOnDark = Color(0x24FFFFFF);
}
