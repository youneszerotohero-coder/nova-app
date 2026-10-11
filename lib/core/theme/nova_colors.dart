import 'package:flutter/material.dart';

/// Theme-dependent surface/text tones. Everything outside this class
/// (ink family, accent family, hues, veils) is identical in both modes
/// and stays compile-time constant.
class NovaPalette {
  const NovaPalette({
    required this.paper,
    required this.paperCard,
    required this.paperRaised,
    required this.textStrong,
    required this.textMuted,
    required this.borderOnLight,
    required this.accentMist,
    required this.isDark,
  });

  final Color paper;
  final Color paperCard;
  final Color paperRaised;
  final Color textStrong;
  final Color textMuted;
  final Color borderOnLight;
  final Color accentMist;

  /// Lets hue surfaces flip from pastel tints to deep translucent
  /// washes without every call site branching.
  final bool isDark;

  /// The website's hero tokens (D-125, `hero.css`): page `--hx-bg`, white
  /// surfaces, `--hx-ink` text, `--hx-mute` secondary text.
  static const NovaPalette light = NovaPalette(
    paper: Color(0xFFF3F6FC),
    paperCard: Color(0xFFFFFFFF),
    paperRaised: Color(0xFFF6F8FD),
    textStrong: Color(0xFF121A33),
    textMuted: Color(0xFF6F7892),
    borderOnLight: Color(0x1A121A33),
    accentMist: Color(0xFFE9F0FF),
    isDark: false,
  );

  /// The website's `.dark` hero tokens.
  static const NovaPalette dark = NovaPalette(
    paper: Color(0xFF0B1126),
    paperCard: Color(0xFF131B36),
    paperRaised: Color(0xFF182143),
    textStrong: Color(0xFFEEF2FF),
    textMuted: Color(0xFF8C97B8),
    borderOnLight: Color(0x1AFFFFFF),
    accentMist: Color(0xFF1B2A5C),
    isDark: true,
  );
}

/// The card hue family: every colourful surface in the app resolves
/// through one of these, so a card, its icon tile, its chips and its
/// shadow always agree — and all of them flip together in dark mode.
enum NovaHue {
  // The website's tones (hero.css): royal blue, sky, yellow, live green,
  // quiz amber, danger red, ink. Kept as a family so a card, its icon tile
  // and its chips always agree.
  sky(Color(0xFF1F54D6), Color(0xFF4FACF0)),
  lilac(Color(0xFF2F86DA), Color(0xFF9FD8FF)),
  peach(Color(0xFFA8740A), Color(0xFFFFD54A)),
  mint(Color(0xFF1F9A58), Color(0xFF4FD1A5)),
  butter(Color(0xFFA8740A), Color(0xFFFFD54A)),
  rose(Color(0xFFCF3434), Color(0xFFFF8A8A)),
  ink(Color(0xFF121A33), Color(0xFF2E3A66));

  const NovaHue(this.solid, this.bright);

  /// The saturated hue: icons, numbers, active pills.
  final Color solid;

  /// Its lighter partner, used for gradients and glows.
  final Color bright;

  /// Pastel card fill on light paper, deep wash on dark paper.
  Color get surface => NovaColors.current.isDark
      ? Color.lerp(NovaColors.paperCard, solid, 0.15)!
      : Color.lerp(Colors.white, solid, 0.11)!;

  /// A touch stronger than [surface] — nested tiles inside a hue card.
  Color get surfaceStrong => NovaColors.current.isDark
      ? Color.lerp(NovaColors.paperCard, solid, 0.26)!
      : Color.lerp(Colors.white, solid, 0.2)!;

  /// Readable hue-tinted text/icon colour on [surface].
  Color get onSurface => NovaColors.current.isDark
      ? Color.lerp(solid, Colors.white, 0.55)!
      : Color.lerp(solid, const Color(0xFF121A33), 0.16)!;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bright, solid],
      );

  /// Coloured drop shadow so cards glow in their own hue instead of
  /// all sharing one grey.
  List<BoxShadow> get shadow => [
        BoxShadow(
          offset: const Offset(0, 16),
          blurRadius: 34,
          spreadRadius: -16,
          color: solid.withValues(alpha: NovaColors.current.isDark ? 0.5 : 0.4),
        ),
      ];

  /// Deterministic hue for a piece of content (subject, teacher…), so
  /// the same course keeps the same colour everywhere in the app.
  static NovaHue of(String seed) {
    final int hash = seed.toLowerCase().codeUnits.fold(
          7,
          (int acc, int code) => (acc * 31 + code) & 0xFFFF,
        );
    const List<NovaHue> wheel = [lilac, peach, mint, sky, butter, rose];
    return wheel[hash % wheel.length];
  }
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

  /// Faint neutral wash for inset rows and empty tracks.
  static Color get subtleFill => current.isDark
      ? Colors.white.withValues(alpha: 0.05)
      : const Color(0xFF0A1128).withValues(alpha: 0.04);

  // Dark ink (the website's `--hx-ink` navy): bottom bar, dark buttons,
  // product cards.
  static const Color ink950 = Color(0xFF121A33);
  static const Color ink900 = Color(0xFF141C3A);
  static const Color ink800 = Color(0xFF1E2A50);
  static const Color ink700 = Color(0xFF2E3A66);

  // Neutral near-black reserved for the search filter button.
  static const Color nearBlack = Color(0xFF121A33);

  // Text on dark ink surfaces.
  static const Color textOnDark = Color(0xFFF6F5F1);
  static const Color textMutedOnDark = Color(0xFFC4CBE0);

  // Accent: the website's royal blue (`--hx-blue`).
  static const Color accent = Color(0xFF1F54D6);
  static const Color accentLight = Color(0xFF3F72EA);
  static const Color accentDeep = Color(0xFF1846B8);
  static const Color accentDark = Color(0xFF10276B);
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentLight, accentDeep],
  );

  // The website's yellow marker and its ink (`--hx-yellow`).
  static const Color yellow = Color(0xFFFFD54A);
  static const Color yellowInk = Color(0xFF3A2C00);
  static const Color postIt = Color(0xFFFFE38A);
  static const Color sky = Color(0xFF9FD8FF);
  static const Color skyStrong = Color(0xFF4FACF0);

  // Status tones (`--hx-live`, `--hx-quiz`, `--hx-danger`).
  static const Color badgeOrange = Color(0xFFA8740A);
  static const Color onlineGreen = Color(0xFF1F9A58);
  static const Color heartRed = Color(0xFFCF3434);
  static const Color gold = Color(0xFFFFD54A);

  // Hairlines on dark ink.
  static const Color borderOnDark = Color(0x1AFFFFFF);

  // Translucent fills.
  static const Color veilOnImage = Color(0x61121A33);
  static const Color veilOnDark = Color(0x24FFFFFF);
}
