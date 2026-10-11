import 'package:flutter/material.dart';

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
