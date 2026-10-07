import 'package:flutter/material.dart';

import '../utils/format_price.dart';
import 'nova_scene_image.dart';
import 'pressable_scale.dart';
import 'progress_ring.dart';

/// A small label on the poster: subject, "Owned", a discount…
class CardBadge {
  const CardBadge(this.label, {this.icon, this.tone});

  final String label;
  final IconData? icon;

  /// Solid fill instead of the light tag — reserved for state (discount,
  /// owned).
  final Color? tone;
}

/// The app's one Unit/Offer card, as on the website catalogue (D-111,
/// `product-card.tsx`): a dark frame, the poster in a light 25:23 panel
/// (the recommended upload ratio, so the poster shows whole), then the
/// title, one line of context and the price with its action under a
/// hairline. Nothing is printed over the poster but small tags.
///
/// Used by the home rails (fixed [width], see [heightFor]), the two-up
/// grids ([NovaCardGrid]) of Explore, the teacher page and My learning.
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
    this.width,
    this.heroTag,
    this.progressPercent,
    this.onTap,
    this.compact = true,
  });

  final String title;
  final NovaScene scene;

  /// Poster photo; [scene] is painted when absent or loading.
  final String? image;

  /// Large watermark glyph on a painted scene.
  final IconData? icon;
  final List<CardBadge> badges;

  /// Shown under the title when there is no [meta].
  final String? teacher;

  /// One line of context under the title (year access, lessons…).
  final String? meta;
  final int? price;
  final int? compareAtPrice;

  /// Replaces the price ("Open", "Resume", "In Offers from…").
  final String? actionLabel;

  /// Fixed width for horizontal rails; null expands to the parent.
  final double? width;
  final Object? heroTag;

  /// Draws completion around the arrow (enrolled Units).
  final int? progressPercent;
  final VoidCallback? onTap;

  /// Two-up grids and rails; false for a full-width card.
  final bool compact;

  static const Color _frame = Color(0xFF232325);
  static const Color _panel = Color(0xFFF4F3EF);
  static const Color _mute = Color(0xFF8F8E88);
  static const Color _action = Color(0xFF4FACF0);

  static double _pad(bool compact) => compact ? 8 : 10;
  static double _titleSize(bool compact) => compact ? 13.5 : 15;
  static double _titleBox(bool compact) => compact ? 36 : 41;
  static double _rowHeight(bool compact) => compact ? 32 : 36;
  static const double _metaBox = 16;

  /// The card's height at [width], so a rail can size itself.
  static double heightFor(double width, {bool compact = true}) {
    final double pad = _pad(compact);
    return pad * 2 +
        (width - pad * 2) * 23 / 25 +
        10 +
        _titleBox(compact) +
        4 +
        _metaBox +
        10 +
        1 +
        10 +
        _rowHeight(compact) +
        2;
  }

  @override
  Widget build(BuildContext context) {
    final double pad = _pad(compact);
    final Widget card = PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.97,
      semanticLabel: 'Open $title',
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: _frame,
          borderRadius: BorderRadius.circular(compact ? 20 : 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(aspectRatio: 25 / 23, child: _media()),
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 4 : 6, 10, compact ? 4 : 6, 2),
              child: _body(),
            ),
          ],
        ),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }

  Widget _media() {
    final Widget cover = NovaSceneImage(
      scene: scene,
      image: image,
      icon: icon,
      iconScale: compact ? 0.9 : 1.15,
      alignment: Alignment.center,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 13 : 16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _panel),
          if (heroTag == null) cover else Hero(tag: heroTag!, child: cover),
          if (badges.isNotEmpty)
            PositionedDirectional(
              start: 8,
              end: 8,
              top: 8,
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [for (final CardBadge badge in badges) _Tag(badge: badge)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final double titleSize = _titleSize(compact);
    final String? line = meta ?? teacher;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _titleBox(compact),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: titleSize,
              height: 1.3,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: _metaBox,
          child: Text(
            line ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: compact ? 11 : 12,
              color: _mute,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
        const SizedBox(height: 10),
        SizedBox(
          height: _rowHeight(compact),
          child: Row(
            children: [
              Expanded(child: _priceOrAction()),
              const SizedBox(width: 8),
              _arrow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _priceOrAction() {
    if (actionLabel != null) {
      return Text(
        actionLabel!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11.5 : 13,
          height: 1.2,
          color: _action,
        ),
      );
    }
    if (price == null) return const SizedBox.shrink();
    final bool showOld = compareAtPrice != null && compareAtPrice! > price!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showOld)
          Text(
            formatDaPrice(compareAtPrice!),
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 10.5,
              height: 1.1,
              color: _mute,
              decoration: TextDecoration.lineThrough,
              decorationColor: _mute,
            ),
          ),
        Text(
          formatDaPrice(price!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'InterDisplay',
            fontWeight: FontWeight.w700,
            fontSize: compact ? 14 : 15.5,
            height: 1.15,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _arrow() {
    final double size = compact ? 30 : 34;
    final Widget button = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _action, shape: BoxShape.circle),
      child: Icon(
        Icons.arrow_forward_rounded, // mirrors itself in Arabic
        size: size * 0.5,
        color: const Color(0xFF0B1A2A),
      ),
    );
    if (progressPercent == null) return button;
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ProgressRing(
            percent: progressPercent!,
            size: size + 8,
            strokeWidth: 2.5,
            color: _action,
            trackColor: Colors.white.withValues(alpha: 0.18),
          ),
          button,
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.badge});

  final CardBadge badge;

  @override
  Widget build(BuildContext context) {
    final bool solid = badge.tone != null;
    final Color text = solid ? Colors.white : const Color(0xFF3A3A3C);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: solid ? badge.tone : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.icon != null) ...[
            Icon(badge.icon, size: 11, color: text),
            const SizedBox(width: 4),
          ],
          Text(
            badge.label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
              height: 1.2,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cards two per row, as the website grid on a narrow screen; an odd last
/// card keeps its half width.
class NovaCardGrid extends StatelessWidget {
  const NovaCardGrid({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.spacing = 12,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: spacing),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: children[i]),
                  SizedBox(width: spacing),
                  Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
