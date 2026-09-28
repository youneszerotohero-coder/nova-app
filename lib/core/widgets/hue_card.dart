import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'motion.dart';
import 'nova_decor.dart';
import 'pressable_scale.dart';

/// How a [HueCard] carries its colour.
enum HueCardStyle {
  /// Pastel tint on paper — the everyday card.
  soft,

  /// Saturated gradient — heroes and the one thing per screen that
  /// should shout.
  filled,

  /// Deep navy — premium/featured rows, the counterpoint to pastels.
  dark,
}

/// The card every colourful surface in the app is built from: one hue,
/// one style, optional sticker decor, and a foreground colour that is
/// always readable on the fill it chose.
class HueCard extends StatelessWidget {
  const HueCard({
    super.key,
    required this.child,
    this.hue = NovaHue.sky,
    this.style = HueCardStyle.soft,
    this.padding = const EdgeInsets.all(18),
    this.radius = NovaDimens.radiusCard,
    this.onTap,
    this.decorSeed,
    this.height,
    this.semanticLabel,
  });

  final Widget child;
  final NovaHue hue;
  final HueCardStyle style;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Paints sticker doodles behind the content when set.
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
        HueCardStyle.soft => NovaColors.textMuted,
        HueCardStyle.filled => Colors.white.withValues(alpha: 0.78),
        HueCardStyle.dark => NovaColors.textMutedOnDark,
      };

  @override
  Widget build(BuildContext context) {
    final bool isSoft = style == HueCardStyle.soft;
    final Color decorColor = isSoft ? hue.solid : Colors.white;
    final double decorOpacity = switch (style) {
      HueCardStyle.soft => 0.14,
      HueCardStyle.filled => 0.22,
      HueCardStyle.dark => 0.1,
    };

    return PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.98,
      semanticLabel: semanticLabel,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: switch (style) {
            HueCardStyle.soft => hue.surface,
            HueCardStyle.filled => null,
            HueCardStyle.dark => NovaColors.ink950,
          },
          gradient: style == HueCardStyle.filled ? hue.gradient : null,
          borderRadius: BorderRadius.circular(radius),
          border: isSoft
              ? Border.all(color: hue.solid.withValues(alpha: 0.16))
              : null,
          boxShadow:
              style == HueCardStyle.soft ? NovaDimens.shadowSoft : hue.shadow,
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (decorSeed != null)
              Positioned.fill(
                child: NovaDecor(
                  color: decorColor,
                  opacity: decorOpacity,
                  seed: decorSeed!,
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// The rounded-square icon tile that heads cards, rows and stats.
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

  /// Solid hue fill with a white glyph, instead of the pastel tint.
  final bool filled;

  /// Sitting on a dark or filled card, where the pastel tint would
  /// disappear — renders as a frosted white tile.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color background = onDark
        ? Colors.white.withValues(alpha: 0.16)
        : (filled ? hue.solid : hue.surfaceStrong);
    final Color glyph =
        onDark || filled ? Colors.white : hue.onSurface;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, size: size * 0.46, color: glyph),
    );
  }
}

/// Pastel metric tile: icon + label on top, a big counted-up number
/// underneath. Two or three fit across a phone.
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
      fontFamily: 'InterDisplay',
      fontWeight: FontWeight.w700,
      fontSize: 30,
      height: 1,
      letterSpacing: -1.2,
      color: NovaColors.textStrong,
    );

    return HueCard(
      hue: hue,
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
                  style: NovaTypography.textTheme.labelMedium!.copyWith(
                    color: hue.onSurface,
                  ),
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

/// The circular arrow affordance from the reference cards.
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
  final Gradient? gradient;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.9,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: gradient == null ? (background ?? Colors.white) : null,
          gradient: gradient,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: size * 0.42,
          color: foreground ?? NovaColors.ink950,
        ),
      ),
    );
  }
}
