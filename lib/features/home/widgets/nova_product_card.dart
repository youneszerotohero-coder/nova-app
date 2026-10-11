import 'package:flutter/material.dart';

import '../../../core/i18n/labels.dart';
import '../../../core/i18n/nova_strings.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/utils/format_price.dart';
import '../../../core/widgets/nova_scene_image.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/models.dart';

/// The website's catalogue card (`.productCard.novaCard`, D-125): a navy card
/// with the poster in a rounded panel, its stickers, the title, then the price
/// and the action. Used for Units and Offers on Home, Explore and teacher pages.
class NovaProductCard extends StatelessWidget {
  const NovaProductCard({
    super.key,
    required this.title,
    required this.image,
    required this.scene,
    required this.icon,
    required this.onTap,
    required this.action,
    this.price,
    this.compareAtPrice,
    this.status,
    this.topStart,
    this.topEnd,
    this.width = 262,
  });

  /// A Unit: "4 Lives" sticker, Purchased / Free, its price or "Unlocked".
  factory NovaProductCard.unit(BuildContext context, Course course, {required VoidCallback onTap, double width = 262}) =>
      NovaProductCard(
        title: course.title,
        image: course.image,
        scene: course.scene,
        icon: course.icon,
        onTap: onTap,
        width: width,
        topStart: course.plannedLives > 0 ? _LiveSticker(count: course.plannedLives) : null,
        topEnd: course.owned
            ? _Pill(label: context.tr('home.purchased'), icon: Icons.check_circle_outline_rounded)
            : course.isFree
                ? _Pill(label: context.tr('detail.free'), icon: Icons.card_giftcard_rounded)
                : course.discountPercent > 0
                    ? _Pill(label: formatDiscount(course.discountPercent))
                    : null,
        status: course.owned ? context.tr('home.unlocked') : null,
        price: course.owned || course.isFree
            ? null
            : course.packOnly
                ? packPriceText(context, course)
                : formatDaPrice(course.price),
        compareAtPrice: !course.owned && !course.packOnly && course.compareAtPrice > course.price
            ? formatDaPrice(course.compareAtPrice)
            : null,
        action: course.owned ? context.tr('home.openUnit') : context.tr('home.seeMore'),
      );

  /// An Offer: its saving, its price and "Buy now".
  factory NovaProductCard.offer(BuildContext context, Pack pack, {required VoidCallback onTap, double width = 262}) =>
      NovaProductCard(
        title: pack.name,
        image: pack.image,
        scene: pack.scene,
        icon: pack.icon,
        onTap: onTap,
        width: width,
        topStart: pack.plannedLives > 0 ? _LiveSticker(count: pack.plannedLives) : null,
        topEnd: pack.discountPercent > 0 ? _Pill(label: formatDiscount(pack.discountPercent)) : null,
        price: formatDaPrice(pack.price),
        compareAtPrice: pack.compareAtPrice > pack.price ? formatDaPrice(pack.compareAtPrice) : null,
        action: context.tr('home.buyNow'),
      );

  static const Color background = Color(0xFF141C3A);

  final String title;
  final String? image;
  final NovaScene scene;
  final IconData icon;
  final VoidCallback onTap;
  final String action;
  final String? price;
  final String? compareAtPrice;

  /// Shown instead of a price ("Unlocked"), with a green dot.
  final String? status;
  final Widget? topStart;
  final Widget? topEnd;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bool yellowAction = price != null;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: title,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(offset: Offset(0, 20), blurRadius: 40, spreadRadius: -24, color: Color(0x8C10276B))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 25 / 23,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: const Color(0xFFEEF2FB)),
                    NovaSceneImage(scene: scene, image: image, icon: icon, iconScale: 0.8),
                    if (topStart != null) PositionedDirectional(top: 12, start: 12, child: topStart!),
                    if (topEnd != null) PositionedDirectional(top: 12, end: 12, child: topEnd!),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NovaTypography.textTheme.titleMedium!.copyWith(color: const Color(0xFFF6F5F1), fontSize: 17),
              ),
            ),
            Container(margin: const EdgeInsets.fromLTRB(8, 8, 8, 10), height: 1, color: Colors.white.withValues(alpha: 0.1)),
            Row(
              children: [
                const SizedBox(width: 6),
                Expanded(
                  child: price != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              price!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NovaTypography.textTheme.titleMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            if (compareAtPrice != null)
                              Text(
                                compareAtPrice!,
                                style: NovaTypography.textTheme.bodySmall!.copyWith(
                                  color: const Color(0xFF8E97B5),
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: const Color(0xFF8E97B5),
                                ),
                              ),
                          ],
                        )
                      : Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF2FBF71), shape: BoxShape.circle)),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                status ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NovaTypography.textTheme.bodyMedium!.copyWith(color: const Color(0xFFC4CBE0), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                ),
                _Action(label: action, yellow: yellowAction),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.yellow});

  final String label;
  final bool yellow;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsetsDirectional.fromSTEB(5, 0, 14, 0),
      decoration: BoxDecoration(
        color: yellow ? NovaColors.yellow : const Color(0xFF232C4D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: yellow ? NovaColors.accent : NovaColors.skyStrong, shape: BoxShape.circle),
            child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: yellow ? NovaColors.yellowInk : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// White sticker with a red dot: how many Lives come with the Unit.
class _LiveSticker extends StatelessWidget {
  const _LiveSticker({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            '$count ${context.tr('unit.fromLive')}',
            style: const TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: Color(0xFF121A33),
            ),
          ),
        ],
      ),
    );
  }
}

/// The yellow pill of the website's cards (Purchased, Free, −20 %).
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: NovaColors.yellowInk), const SizedBox(width: 5)],
          Text(
            label,
            style: const TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: NovaColors.yellowInk,
            ),
          ),
        ],
      ),
    );
  }
}
