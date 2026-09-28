import 'package:flutter/material.dart';

import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/nova_course_card.dart';
import '../../data/models.dart';
import 'course_detail_screen.dart';

/// One pack as a wide cover card, opening the pack page — Explore and
/// the teacher page list packs with it.
class PackCard extends StatelessWidget {
  const PackCard({super.key, required this.pack});

  final Pack pack;

  @override
  Widget build(BuildContext context) {
    return NovaCourseCard(
      aspectRatio: 16 / 10,
      heroTag: 'cover-${pack.name}',
      title: pack.name,
      scene: pack.scene,
      image: pack.image,
      icon: pack.icon,
      meta: context.tr('explore.yearAccess'),
      price: pack.price,
      compareAtPrice: pack.compareAtPrice,
      badges: [
        CardBadge(offerTypeText(context, pack), icon: Icons.layers_rounded),
        CardBadge(
          context.trf(
            'detail.coursesStat',
            {'n': pack.courseCount.toString()},
          ),
        ),
        if (pack.discountPercent > 0)
          CardBadge(
            formatDiscount(pack.discountPercent),
            tone: NovaColors.heartRed,
          ),
      ],
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CourseDetailScreen.pack(pack: pack),
        ),
      ),
    );
  }
}
