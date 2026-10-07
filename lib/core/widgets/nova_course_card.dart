import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../utils/format_price.dart';
import 'nova_decor.dart';
import 'nova_scene_image.dart';
import 'pressable_scale.dart';
import 'progress_ring.dart';

/// A glass pill over the cover: subject, format, lives, "Owned"…
class CardBadge {
  const CardBadge(this.label, {this.icon, this.tone});

  final String label;
  final IconData? icon;

  /// Solid fill instead of glass — reserved for state (discount, owned).
  final Color? tone;
}

/// The app's one course/offer card, matching the web catalog: the cover
/// runs the whole card, a scrim lifts the text off it, glass badges sit
/// on top, and the title, teacher and price sit at the bottom.
///
/// Used by the home rail (fixed [width]), the Explore grid (expands to
/// its cell) and the teacher page. The cart keeps its own row layout.
class NovaCourseCard extends StatelessWidget {
  const NovaCourseCard({
    super.key,
    required this.title,
    required this.scene,
    this.image,
    this.icon,
    this.badges = const <CardBadge>[],
    this.teacher,
    this.meta,
    this.price,
    this.compareAtPrice,
    this.actionLabel,
    this.footer,
    this.width,
    this.aspectRatio = 1 / 1.08,
    this.fill = false,
    this.heroTag,
    this.progressPercent,
    this.onTap,
    this.compact = false,
  });

  final String title;
  final NovaScene scene;

  /// Poster photo; [scene] is painted when absent or loading.
  final String? image;

  /// Large watermark glyph on the cover.
  final IconData? icon;
  final List<CardBadge> badges;

  /// Shown with a monogram dot under the title.
  final String? teacher;

  /// Replaces the price row when the card is not commercial.
  final String? meta;
  final int? price;
  final int? compareAtPrice;

  /// Overrides the price pill's text ("Open", "Resume"…).
  final String? actionLabel;

  /// Sits between the subline and the action row — an avatar stack of
  /// classmates, for instance.
  final Widget? footer;

  /// Fixed width for horizontal rails; null expands to the parent.
  final double? width;
  final double aspectRatio;

  /// Takes the size its parent gives it (a grid cell) instead of
  /// imposing [aspectRatio].
  final bool fill;
  final Object? heroTag;

  /// Draws completion around the arrow button (enrolled courses).
  final int? progressPercent;
  final VoidCallback? onTap;

  /// Tighter type and spacing, for two-up grids.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Widget card = PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.97,
      semanticLabel: 'Open $title',
      child: _ratio(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NovaDimens.radiusCard),
            boxShadow: NovaDimens.shadowCard,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _cover(),
              // Stickers dress painted scenes; a real poster needs none.
              if (image == null)
                const Positioned.fill(
                  child:
                      NovaDecor(color: Colors.white, opacity: 0.16, seed: 4),
                ),
              // Scrim: transparent at the top, near-solid ink at the
              // bottom so the title always wins over the artwork.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.34, 0.62, 1.0],
                      colors: [
                        Color(0x14090E16),
                        Color(0x40090E16),
                        Color(0xC2090E16),
                        Color(0xF2090E16),
                      ],
                    ),
                  ),
                ),
              ),
              if (badges.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final CardBadge badge in badges)
                        _GlassBadge(badge: badge),
                    ],
                  ),
                ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _bottom(context),
              ),
            ],
          ),
        ),
      ),
    );

    return width == null ? card : SizedBox(width: width, child: card);
  }

  Widget _ratio({required Widget child}) =>
      fill ? child : AspectRatio(aspectRatio: aspectRatio, child: child);

  Widget _cover() {
    final Widget scene = NovaSceneImage(
      scene: this.scene,
      image: image,
      icon: icon,
      iconScale: compact ? 0.9 : 1.15,
      alignment: Alignment.topRight,
    );
    return heroTag == null ? scene : Hero(tag: heroTag!, child: scene);
  }

  Widget _bottom(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'InterDisplay',
            fontWeight: FontWeight.w700,
            fontSize: compact ? 15.5 : 18,
            height: 1.18,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
        ),
        if (teacher != null || meta != null) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              if (teacher != null) ...[
                Icon(
                  Icons.verified_user_rounded,
                  size: compact ? 12 : 13,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  meta ?? teacher!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 11 : 12,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: 10),
          footer!,
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _priceOrAction(context)),
            const SizedBox(width: 8),
            _arrow(),
          ],
        ),
      ],
    );
  }

  Widget _priceOrAction(BuildContext context) {
    if (actionLabel != null) {
      return Text(
        actionLabel!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w800,
          fontSize: compact ? 13 : 14.5,
          color: NovaColors.accentLight,
        ),
      );
    }
    if (price == null) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            formatDaPrice(price!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'InterDisplay',
              fontWeight: FontWeight.w700,
              fontSize: compact ? 15 : 17,
              letterSpacing: -0.4,
              color: Colors.white,
            ),
          ),
        ),
        if (compareAtPrice != null && compareAtPrice! > price! && !compact) ...[
          const SizedBox(width: 6),
          Text(
            formatDaPrice(compareAtPrice!),
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.6),
              decoration: TextDecoration.lineThrough,
              decorationColor: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _arrow() {
    final double size = compact ? 34 : 40;
    final Widget button = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: size * 0.45,
        color: NovaColors.ink950,
      ),
    );

    if (progressPercent == null) return button;
    return SizedBox(
      width: size + 12,
      height: size + 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ProgressRing(
            percent: progressPercent!,
            size: size + 12,
            strokeWidth: 3,
            color: NovaColors.accentLight,
            trackColor: Colors.white.withValues(alpha: 0.24),
          ),
          button,
        ],
      ),
    );
  }
}

class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.badge});

  final CardBadge badge;

  @override
  Widget build(BuildContext context) {
    final bool solid = badge.tone != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? badge.tone : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(100),
        border: solid
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.icon != null) ...[
            Icon(badge.icon, size: 11, color: Colors.white),
            const SizedBox(width: 5),
          ],
          Text(
            badge.label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              height: 1.2,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
