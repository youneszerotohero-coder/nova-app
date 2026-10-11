import 'package:flutter/material.dart';

import '../../../core/i18n/nova_strings.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/utils/format_price.dart';
import '../../../core/widgets/nova_scene_image.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/models.dart';

/// Where an Offer stands for the Student (website `AccountHome`): theirs,
/// or not theirs but every Unit in it already paid for ("covered").
enum OfferOwnership { none, owned, covered }

/// The card's button (`.productSeeMore` / `.productBuyBtn`).
enum CardActionStyle {
  /// White at 10 % on the navy ("See more", "Get it free").
  plain,

  /// Yellow with a blue chip ("Buy now").
  buy,

  /// The near-black button of a card the Student owns ("Open Unit", "My
  /// units": `.enrolledCourseCard .enrolledCourseOpen`).
  owned,
}

/// The website's catalogue card (`.productCard.novaCard`, `catalog.css`;
/// `product-card.tsx`, D-125): a navy frame with the cover in a rounded
/// panel, the yellow badge at the inline start and the white tag (or the
/// owned check mark) at the inline end, the title, then the price or the
/// status line and the action. Used for Units and Offers on Home, the
/// catalogue and the teacher pages.
class NovaProductCard extends StatelessWidget {
  const NovaProductCard({
    super.key,
    required this.title,
    required this.image,
    required this.scene,
    required this.icon,
    required this.onTap,
    required this.action,
    this.actionStyle = CardActionStyle.plain,
    this.actionChip = true,
    this.price,
    this.priceFrom,
    this.priceFree = false,
    this.compareAtPrice,
    this.status,
    this.badge,
    this.badgeIcon,
    this.tag,
    this.liveTag = false,
    this.ownedMark = false,
    this.onAction,
    this.width = 262,
  });

  /// A Unit (`CourseCard`): the "N Live" or "Recorded" tag, "Free" badge,
  /// its price ("In Offers from …" when sold through Offers only) and "See
  /// more" (no chip), or "Get it free". A Unit the Student owns
  /// (`OwnedCourseCard`): "Purchased" (or "Enrolled" for a free Unit) with
  /// the check mark, "Unlocked" and "Open Unit".
  factory NovaProductCard.unit(
    BuildContext context,
    Course course, {
    required VoidCallback onTap,
    VoidCallback? onAction,
    double width = 262,
  }) {
    if (course.owned) {
      return NovaProductCard(
        title: course.title,
        image: course.image,
        scene: course.scene,
        icon: course.icon,
        onTap: onTap,
        onAction: onAction,
        width: width,
        badge: context.tr(course.isFree ? 'card.enrolled' : 'home.purchased'),
        badgeIcon: Icons.check_circle_outline_rounded,
        ownedMark: true,
        status: context.tr('home.unlocked'),
        action: context.tr('home.openUnit'),
        actionStyle: CardActionStyle.owned,
      );
    }
    final bool live = course.plannedLives > 0;
    final bool free = course.isFree;
    final bool getFree = free && course.matchesStudentProfile != false;
    return NovaProductCard(
      title: course.title,
      image: course.image,
      scene: course.scene,
      icon: course.icon,
      onTap: onTap,
      onAction: onAction,
      width: width,
      badge: free ? context.tr('card.freeBadge') : null,
      badgeIcon: Icons.card_giftcard_rounded,
      tag: live ? '${course.plannedLives} ${context.tr('card.live')}' : context.tr('card.recorded'),
      liveTag: live,
      priceFree: free,
      priceFrom: course.packOnly && course.offerPriceFrom != null ? context.tr('card.packsFrom') : null,
      price: free
          ? context.tr('common.free')
          : course.packOnly
              ? (course.offerPriceFrom == null ? context.tr('card.packsOnly') : formatCardPrice(course.offerPriceFrom!))
              : formatCardPrice(course.price),
      action: context.tr(getFree ? 'card.getFree' : 'home.seeMore'),
      // A paid Unit's "See more" has no chip.
      actionChip: getFree,
    );
  }

  /// An Offer (`PackCard`): "Save x %", its price and the crossed former
  /// total, "Buy now". [ownership] gives the Home's variants
  /// (`OwnedPackCard`): "Purchased" + check mark + "Active", or "Units
  /// already yours"; both lead to My units.
  factory NovaProductCard.offer(
    BuildContext context,
    Pack pack, {
    required VoidCallback onTap,
    VoidCallback? onAction,
    double width = 262,
    OfferOwnership ownership = OfferOwnership.none,
  }) {
    if (ownership != OfferOwnership.none) {
      final bool held = ownership == OfferOwnership.owned;
      return NovaProductCard(
        title: pack.name,
        image: pack.image,
        scene: pack.scene,
        icon: pack.icon,
        onTap: onTap,
        onAction: onAction,
        width: width,
        badge: context.tr(held ? 'home.purchased' : 'card.coursesOwned'),
        badgeIcon: Icons.check_circle_outline_rounded,
        ownedMark: held,
        status: held ? context.tr('card.active') : '',
        action: context.tr('menu.myUnits'),
        actionStyle: CardActionStyle.owned,
      );
    }
    return NovaProductCard(
      title: pack.name,
      image: pack.image,
      scene: pack.scene,
      icon: pack.icon,
      onTap: onTap,
      onAction: onAction,
      width: width,
      badge: pack.discountPercent > 0 ? context.trf('card.saving', {'percent': '${pack.discountPercent}'}) : null,
      badgeIcon: Icons.trending_up_rounded,
      price: pack.price == 0 ? context.tr('common.free') : formatCardPrice(pack.price),
      compareAtPrice: pack.compareAtPrice > pack.price ? formatCardPrice(pack.compareAtPrice) : null,
      action: context.tr('home.buyNow'),
      actionStyle: CardActionStyle.buy,
    );
  }

  /// The website's price (`formatPrice`), the same as everywhere in the app.
  static String formatCardPrice(int amount) => formatDaPrice(amount);

  // `.productCard.novaCard` tokens (`--nc-*`).
  static const Color _ink = Color(0xFFF6F5F1);
  static const Color _soft = Color(0xFFC4CBE0);
  static const Color _mute = Color(0xFF8E97B5);
  static const Color _line = Color(0x1AFFFFFF);

  final String title;
  final String? image;
  final NovaScene scene;
  final IconData icon;
  final VoidCallback onTap;
  final String action;
  final CardActionStyle actionStyle;

  /// The round arrow chip after the label.
  final bool actionChip;
  final String? price;

  /// The small line above the price ("In Offers from").
  final String? priceFrom;

  /// The price is "Free" (green).
  final bool priceFree;
  final String? compareAtPrice;

  /// Shown instead of a price ("Unlocked", "Active"), with a green dot; an
  /// empty string leaves the place empty.
  final String? status;

  /// The yellow badge at the inline start.
  final String? badge;
  final IconData? badgeIcon;

  /// The white tag at the inline end ("Recorded", "4 Live").
  final String? tag;

  /// The tag counts Lives: a pulsing red dot leads it.
  final bool liveTag;

  /// The round check mark of a card the Student owns, at the inline end.
  final bool ownedMark;

  /// The button's own action (e.g. "My units" on an owned Offer, whose card
  /// opens the Offer); null: the button opens what the card opens.
  final VoidCallback? onAction;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bool dark = NovaColors.current.isDark;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: title,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NovaColors.ink900,
          // 26 px, 22 px on phones (≤ 560 px).
          borderRadius: BorderRadius.circular(22),
          // The dark theme's inset ring (`0 0 0 1px rgba(255,255,255,.08) inset`).
          border: dark ? Border.all(color: const Color(0x14FFFFFF)) : null,
          boxShadow: dark
              ? const [BoxShadow(offset: Offset(0, 18), blurRadius: 40, spreadRadius: -22, color: Color(0xB3000000))]
              : const [BoxShadow(offset: Offset(0, 20), blurRadius: 40, spreadRadius: -24, color: Color(0x8C10276B))],
        ),
        // The footer sits at the bottom when a row stretches its cards to one
        // height (`margin-top: auto`).
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
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
                        const CustomPaint(painter: _PanelGrid()),
                        NovaSceneImage(scene: scene, image: image, icon: icon, iconScale: 0.8),
                        if (badge != null)
                          PositionedDirectional(top: 12, start: 12, child: _Sticker(label: badge!, icon: badgeIcon, yellow: true)),
                        if (ownedMark)
                          const PositionedDirectional(top: 10, end: 10, child: _OwnedMark())
                        else if (tag != null)
                          PositionedDirectional(top: 12, end: 12, child: _Sticker(label: tag!, live: liveTag)),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: NovaTypography.display,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.35,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(6, 10, 6, 0),
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
              child: Row(
                children: [
                  Expanded(child: price != null ? _priceBlock() : _statusLine()),
                  const SizedBox(width: 10),
                  if (onAction == null)
                    _Action(label: action, style: actionStyle, chip: actionChip)
                  else
                    PressableScale(
                      onTap: onAction,
                      pressedScale: 0.95,
                      semanticLabel: action,
                      child: _Action(label: action, style: actionStyle, chip: actionChip),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceBlock() {
    const TextStyle small = TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: 13.5,
      height: 1.2,
      color: _mute,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (priceFrom != null) ...[Text(priceFrom!, maxLines: 1, overflow: TextOverflow.ellipsis, style: small), const SizedBox(height: 4)],
        Text(
          price!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: NovaTypography.display,
            fontFamilyFallback: NovaTypography.fallback,
            fontWeight: FontWeight.w800,
            fontSize: 19,
            height: 1.1,
            color: priceFree ? const Color(0xFF5FE39A) : _ink,
          ),
        ),
        if (compareAtPrice != null) ...[
          const SizedBox(height: 4),
          Text(
            compareAtPrice!,
            maxLines: 1,
            style: small.copyWith(decoration: TextDecoration.lineThrough, decorationColor: _mute),
          ),
        ],
      ],
    );
  }

  /// `.enrolledCourseMeta`: the green dot and "Unlocked".
  Widget _statusLine() {
    if (status == null || status!.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF3ECF72),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(spreadRadius: 3, color: Color(0x293ECF72))],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            status!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: NovaTypography.body,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.3,
              color: _soft,
            ),
          ),
        ),
      ],
    );
  }
}

/// `.novaCardMedia`: the `#EEF2FB` panel and its 44 px grid, under the cover.
class _PanelGrid extends CustomPainter {
  const _PanelGrid();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEEF2FB));
    final Paint line = Paint()..color = const Color(0x0F1E1E1E);
    for (double x = 43; x < size.width; x += 44) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), line);
    }
    for (double y = 43; y < size.height; y += 44) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
  }

  @override
  bool shouldRepaint(_PanelGrid old) => false;
}

/// `.productSeeMore` / `.productBuyBtn` / `.enrolledCourseOpen`: radius 14,
/// at least 44 px high, the chip (22 px, an arrow) after the label.
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.style, required this.chip});

  final String label;
  final CardActionStyle style;
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color ink, Color chipBg, Color chipInk) = switch (style) {
      CardActionStyle.plain => (const Color(0x1AFFFFFF), NovaProductCard._ink, NovaColors.skyStrong, const Color(0xFF0B1A2A)),
      CardActionStyle.buy => (NovaColors.yellow, NovaColors.yellowInk, NovaColors.accent, Colors.white),
      CardActionStyle.owned => (const Color(0xFF111215), Colors.white, NovaColors.skyStrong, const Color(0xFF0B1A2A)),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: EdgeInsetsDirectional.fromSTEB(16, 4, chip ? 9 : 16, 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              height: 1.2,
              color: ink,
            ),
          ),
          if (chip) ...[
            const SizedBox(width: 7),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: chipBg, shape: BoxShape.circle),
              child: Icon(Icons.arrow_forward_rounded, size: 13, color: chipInk),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.novaCardBadge` (yellow) and `.novaCardTag` (white): 28 px, radius 10,
/// Baloo 800 13.5 px, a small shadow. A Live tag starts with a pulsing dot.
class _Sticker extends StatelessWidget {
  const _Sticker({required this.label, this.icon, this.yellow = false, this.live = false});

  final String label;
  final IconData? icon;
  final bool yellow;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final Color ink = yellow ? NovaColors.yellowInk : const Color(0xFF121A33);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: yellow ? NovaColors.yellow : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(offset: Offset(0, 8), blurRadius: 18, spreadRadius: -10, color: Color(0x990A0E16))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[const _LiveDot(), const SizedBox(width: 6)] else if (icon != null) ...[Icon(icon, size: 13, color: ink), const SizedBox(width: 6)],
          Text(
            label,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              height: 1,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.novaCardTag i`: 7 px `#E5484D`, `livePulse` (1.8 s: 40 % opacity and
/// 88 % size halfway); still when animations are off (reduced motion).
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Widget dot = SizedBox.square(
      dimension: 7,
      child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle)),
    );
    return AnimatedBuilder(
      animation: _pulse,
      builder: (BuildContext context, Widget? child) {
        // 0 → 1 → 0 over the cycle, eased like cubic-bezier(.4, 0, .6, 1).
        final double t = Curves.easeInOut.transform(1 - (2 * _pulse.value - 1).abs());
        return Opacity(opacity: 1 - 0.6 * t, child: Transform.scale(scale: 1 - 0.12 * t, child: child));
      },
      child: dot,
    );
  }
}

/// `.enrolledCourseAccessMark`: a dark glass circle with a sky check.
class _OwnedMark extends StatelessWidget {
  const _OwnedMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xA30F172A),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x4DFFFFFF)),
      ),
      child: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF8FD4FB)),
    );
  }
}
