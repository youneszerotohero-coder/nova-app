import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import 'course_detail_screen.dart';

/// One Offer (D-122, owner): its poster shown whole over a blurred copy of
/// itself, so the teacher, the price and the text printed on it stay
/// readable, and its name, type and price in a strip under it. The home
/// carousel shows one per view; Explore and the teacher page list them.
class PackCard extends StatelessWidget {
  const PackCard({super.key, required this.pack, this.onTap});

  final Pack pack;

  /// Defaults to opening the Offer page.
  final VoidCallback? onTap;

  static const double height = 262;
  static const double stripHeight = 72;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: PressableScale(
        onTap: onTap ??
            () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CourseDetailScreen.pack(pack: pack),
                  ),
                ),
        semanticLabel: 'Open pack ${pack.name}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NovaDimens.radiusCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _poster()),
              _strip(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The same poster, blurred and darkened, fills the sides.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: NovaSceneImage(scene: pack.scene, image: pack.image, icon: pack.icon, iconScale: 0.72),
        ),
        const ColoredBox(color: Color(0x8C0A1128)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Hero(
            tag: 'cover-${pack.name}',
            child: NovaSceneImage(
              scene: pack.scene,
              image: pack.image,
              icon: pack.icon,
              iconScale: 0.72,
              fit: BoxFit.contain,
              alignment: Alignment.center,
            ),
          ),
        ),
        if (pack.discountPercent > 0)
          PositionedDirectional(
            top: 10,
            start: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: NovaColors.heartRed,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                formatDiscount(pack.discountPercent),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _strip(BuildContext context) {
    final bool showOld = pack.compareAtPrice > pack.price;
    return Container(
      height: stripHeight,
      color: NovaColors.ink950,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${offerTypeText(context, pack)} · '
                  '${context.trf('detail.coursesStat', {'n': pack.courseCount.toString()})}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showOld)
                Text(
                  formatDaPrice(pack.compareAtPrice),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.55),
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              Text(
                formatDaPrice(pack.price),
                style: const TextStyle(
                  fontFamily: 'InterDisplay',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
