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

  static const NovaPalette light = NovaPalette(
    paper: Color(0xFFFFFFFF),
    paperCard: Color(0xFFFFFFFF),
    paperRaised: Color(0xFFFFFFFF),
    textStrong: Color(0xFF0A1128),
    textMuted: Color(0xFF75839E),
    borderOnLight: Color(0x240A1128),
    accentMist: Color(0xFFE4F1FE),
    isDark: false,
  );

  static const NovaPalette dark = NovaPalette(
    paper: Color(0xFF0C1424),
    paperCard: Color(0xFF16233D),
    paperRaised: Color(0xFF1B2A4A),
    textStrong: Color(0xFFEDF2FB),
    textMuted: Color(0xFF8B9AB8),
    borderOnLight: Color(0x14FFFFFF),
    accentMist: Color(0xFF16294A),
    isDark: true,
  );
}

/// The card hue family: every colourful surface in the app resolves
/// through one of these, so a card, its icon tile, its chips and its
/// shadow always agree — and all of them flip together in dark mode.
enum NovaHue {
  sky(Color(0xFF2B87F7), Color(0xFF6FB3FF)),
  lilac(Color(0xFF6C5CE7), Color(0xFF9B8BFF)),
  peach(Color(0xFFF2762E), Color(0xFFFFA76B)),
  mint(Color(0xFF17A673), Color(0xFF55D3A3)),
  butter(Color(0xFFD99A0B), Color(0xFFFFC94D)),
  rose(Color(0xFFE0526A), Color(0xFFFF8CA0)),
  ink(Color(0xFF1A2848), Color(0xFF3C4F7E));

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
      : Color.lerp(solid, const Color(0xFF0A1128), 0.16)!;

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

/// Nova palette sampled from the approved visual direction:
/// white surfaces, deep navy ink, primary blue accent, and the pastel
/// [NovaHue] family that carries the playful card system.
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

  // Light surfaces raised on dark ink (unchanged across modes).
  static const Color ink950 = Color(0xFF131F3A);
  static const Color ink900 = Color(0xFF1A2848);
  static const Color ink800 = Color(0xFF223156);
  static const Color ink700 = Color(0xFF2D3D68);

  // Neutral near-black reserved for the search filter button, which
  // stays black across the blue direction.
  static const Color nearBlack = Color(0xFF121318);

  // Text on dark ink surfaces.
  static const Color textOnDark = Color(0xFFF4F7FD);
  static const Color textMutedOnDark = Color(0xFF97A3C0);

  // Accent (primary blue).
  static const Color accent = Color(0xFF2B87F7);
  static const Color accentLight = Color(0xFF4D9EFF);
  static const Color accentDeep = Color(0xFF1478EF);
  static const Color accentDark = Color(0xFF1B5FD0);
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentLight, accentDeep],
  );

  // Supporting hues.
  static const Color badgeOrange = Color(0xFFF18A50);
  static const Color onlineGreen = Color(0xFF34C759);
  static const Color heartRed = Color(0xFFE5484D);
  static const Color gold = Color(0xFFF2B33D);

  // Hairlines on dark ink.
  static const Color borderOnDark = Color(0x1AFFFFFF);

  // Translucent fills.
  static const Color veilOnImage = Color(0x611D1B1F);
  static const Color veilOnDark = Color(0x24FFFFFF);
}
