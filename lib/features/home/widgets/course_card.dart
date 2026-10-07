import 'package:flutter/material.dart';

import '../../../core/i18n/labels.dart';
import '../../../core/i18n/nova_strings.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_dimens.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/utils/format_price.dart';
import '../../../core/widgets/hue_card.dart';
import '../../../core/widgets/monogram_avatar.dart';
import '../../../core/widgets/nova_scene_image.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../data/models.dart';

/// Course card in the home "Popular courses" rail. Cards alternate
/// between the subject's pastel hue and deep ink so the rail reads as
/// a rhythm rather than a row of identical boxes.
///
/// Every block has a fixed height — the title always reserves two
/// lines — so the card is exactly [height] tall and the rail never
/// stretches it into an empty band under the price.
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.course,
    this.onTap,
    this.index = 0,
  });

  final Course course;
  final VoidCallback? onTap;

  /// Position in the rail — decides the pastel/ink alternation.
  final int index;

  static const double width = 248;
  static const double _padding = 12;
  static const double _coverHeight = 124;
  static const double _titleHeight = 40;
  static const double _teacherHeight = 22;
  static const double _priceHeight = 36;

  /// The card's full height; the rail sizes itself from this. The
  /// trailing 2 is the pastel card's 1px hairline, top and bottom.
  static const double height = _padding +
      _coverHeight +
      10 +
      _titleHeight +
      6 +
      _teacherHeight +
      10 +
      _priceHeight +
      _padding +
      2;

  @override
  Widget build(BuildContext context) {
    final bool dark = index.isOdd;
    final NovaHue hue = dark ? NovaHue.ink : NovaHue.of(course.subject);
    final HueCardStyle style = dark ? HueCardStyle.dark : HueCardStyle.soft;
    final Color foreground = HueCard.foregroundOf(style);
    final Color muted = HueCard.mutedOf(style);

    return SizedBox(
      width: width,
      height: height,
      child: HueCard(
        hue: hue,
        style: style,
        radius: NovaDimens.radiusCard,
        padding: const EdgeInsets.all(_padding),
        onTap: onTap,
        semanticLabel: 'Open course ${course.title}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(NovaDimens.radiusInner),
              child: SizedBox(
                height: _coverHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NovaSceneImage(
                      scene: course.scene,
                      image: course.image,
                      icon: course.icon,
                      iconScale: 0.8,
                    ),
                    // A light top scrim so the chips read on any poster.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [Color(0x59000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: TagChip(
                          course.subject,
                          translucent: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (course.discountPercent > 0 && !course.owned)
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: NovaColors.heartRed,
                              borderRadius: BorderRadius.circular(
                                NovaDimens.radiusChip,
                              ),
                            ),
                            child: Text(
                              formatDiscount(course.discountPercent),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                                height: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: _titleHeight,
                    child: Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTypography.textTheme.titleMedium!.copyWith(
                        color: foreground,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: _teacherHeight,
                    child: Row(
                      children: [
                        MonogramAvatar(
                          label: course.teacher,
                          photo: course.teacherPhoto,
                          size: 22,
                          showRing: false,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            context.trf('common.prof', {'name': course.teacher}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NovaTypography.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: _priceHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: course.owned || course.packOnly
                              ? Text(
                                  // D-091: sold through Packs only.
                                  course.owned
                                      ? context.tr('common.open')
                                      : packPriceText(context, course),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NovaTypography.textTheme.titleMedium!
                                      .copyWith(
                                    color: dark
                                        ? NovaColors.accentLight
                                        : hue.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      formatDaPrice(course.price),
                                      style: NovaTypography
                                          .textTheme.titleLarge!
                                          .copyWith(color: foreground),
                                    ),
                                    if (course.compareAtPrice >
                                        course.price) ...[
                                      const SizedBox(width: 7),
                                      Flexible(
                                        child: Text(
                                          formatDaPrice(course.compareAtPrice),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: NovaTypography
                                              .textTheme.bodySmall
                                              ?.copyWith(
                                            color: muted,
                                            decoration:
                                                TextDecoration.lineThrough,
                                            decorationColor: muted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                        // Decorative: the card itself is the tap target.
                        RoundArrowButton(
                          size: _priceHeight,
                          background: dark ? Colors.white : hue.solid,
                          foreground: dark ? NovaColors.ink950 : Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
