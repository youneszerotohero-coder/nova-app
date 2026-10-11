import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'hero_style.dart';
import 'motion.dart';
import 'pressable_scale.dart';

/// How a [HueCard] carries its colour.
enum HueCardStyle {
  /// The website's neutral card (`.hxCard` / `.dashboardCard`).
  soft,

  /// The blue card (`.hxCard--blue`): the band's colours, white text.
  filled,

  /// The navy catalogue card (`.novaCard`).
  dark,
}

/// A card in the website's styles whatever hue it is given (D-134): the
/// neutral surface with its hairline and `--hx-shadow`, the blue card, or
/// the navy card. No pastel fills, gradients or coloured shadows.
class HueCard extends StatelessWidget {
  const HueCard({
    super.key,
    required this.child,
    this.hue = NovaHue.sky,
    this.style = HueCardStyle.soft,
    this.padding = const EdgeInsets.all(18),
    this.radius = NovaDimens.radiusTile,
    this.onTap,
    this.decorSeed,
    this.height,
    this.semanticLabel,
  });

  final Widget child;

  /// Kept for callers; the website's cards carry no hue.
  final NovaHue hue;
  final HueCardStyle style;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Kept for callers; the website's cards carry no doodles.
  final int? decorSeed;
  final double? height;
  final String? semanticLabel;

  /// The text/icon colour that reads on this card's fill.
  static Color foregroundOf(HueCardStyle style) => switch (style) {
        HueCardStyle.soft => NovaColors.textStrong,
        HueCardStyle.filled => Colors.white,
        HueCardStyle.dark => NovaColors.textOnDark,
      };

  /// The quieter second-level colour on the same fill.
  static Color mutedOf(HueCardStyle style) => switch (style) {
        HueCardStyle.soft => NovaColors.textBody,
        HueCardStyle.filled => const Color(0xD6FFFFFF),
        HueCardStyle.dark => NovaColors.textMutedOnDark,
      };

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(radius);
    final BoxDecoration decoration = switch (style) {
      HueCardStyle.soft => BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: corners,
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowCard,
        ),
      HueCardStyle.filled => HeroBandDecoration.of(radius: corners),
      HueCardStyle.dark => BoxDecoration(color: NovaColors.ink900, borderRadius: corners, boxShadow: NovaDimens.shadowCard),
    };
    return PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.98,
      semanticLabel: semanticLabel,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: decoration,
        padding: padding,
        child: child,
      ),
    );
  }
}

/// The rounded-square icon tile (`.hxSticker > i`): `--hx-blue-soft` with
/// the blue glyph, or a status tone on its background ([NovaHue.mint] live,
/// [NovaHue.rose] danger, [NovaHue.butter] quiz).
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.hue = NovaHue.sky,
    this.size = 44,
    this.filled = false,
    this.onDark = false,
  });

  final IconData icon;
  final NovaHue hue;
  final double size;

  /// The solid tile: blue with a white glyph, or yellow with its ink for
  /// [NovaHue.butter] (the website's yellow tiles).
  final bool filled;

  /// On the blue band or a dark card: a frosted white tile.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bool yellow = filled && hue == NovaHue.butter;
    final Color background = onDark
        ? const Color(0x29FFFFFF)
        : filled
            ? (yellow ? NovaColors.yellow : hue.solid)
            : hue.surfaceStrong;
    final Color glyph = onDark
        ? Colors.white
        : filled
            ? (yellow ? NovaColors.yellowInk : Colors.white)
            : hue.solid;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.46, color: glyph),
    );
  }
}

/// A metric on the neutral card: icon tile and label on top, the counted-up
/// number underneath. Two or three fit across a phone.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.hue = NovaHue.sky,
    this.suffix = '',
    this.animate = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final NovaHue hue;
  final String suffix;
  final bool animate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextStyle valueStyle = TextStyle(
      fontFamily: NovaTypography.display,
      fontWeight: FontWeight.w800,
      fontSize: 30,
      height: 1,
      color: NovaColors.textStrong,
    );

    return HueCard(
      onTap: onTap,
      semanticLabel: '$label $value',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      radius: NovaDimens.radiusTile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconTile(icon: icon, hue: hue, size: 34),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaTypography.textTheme.labelMedium!.copyWith(color: NovaColors.textBody),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          animate
              ? CountUpText(value, suffix: suffix, style: valueStyle)
              : Text('$value$suffix', style: valueStyle),
        ],
      ),
    );
  }
}

/// A round arrow button: the surface with an ink glyph, or the blue with a
/// white one when a [gradient] was asked for (the website has no gradients).
class RoundArrowButton extends StatelessWidget {
  const RoundArrowButton({
    super.key,
    this.icon = Icons.arrow_forward_rounded,
    this.size = 44,
    this.background,
    this.foreground,
    this.gradient,
    this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final Color? background;
  final Color? foreground;

  /// Kept for callers: any gradient renders as the flat blue.
  final Gradient? gradient;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool blue = gradient != null;
    return PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.9,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: blue ? NovaColors.accent : (background ?? NovaColors.paperCard),
          shape: BoxShape.circle,
          border: blue || background != null ? null : Border.all(color: NovaColors.borderOnLight),
        ),
        child: Icon(
          icon,
          size: size * 0.42,
          color: foreground ?? (blue ? Colors.white : NovaColors.textStrong),
        ),
      ),
    );
  }
}
