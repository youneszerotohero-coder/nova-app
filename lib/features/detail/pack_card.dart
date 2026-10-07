import 'package:flutter/material.dart';

import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/nova_course_card.dart';
import '../../data/models.dart';
import 'course_detail_screen.dart';

/// One Offer card (website `PackCard`), opening the Offer page — the home
/// rail, Explore and the teacher page list Offers with it.
class PackCard extends StatelessWidget {
  const PackCard({super.key, required this.pack, this.width});

  final Pack pack;

  /// Fixed width in a horizontal rail.
  final double? width;

  @override
  Widget build(BuildContext context) {
    return NovaCourseCard(
      width: width,
      heroTag: 'cover-${pack.name}',
      title: pack.name,
      scene: pack.scene,
      image: pack.image,
      icon: pack.icon,
      meta: '${offerTypeText(context, pack)} · ${context.trf('detail.coursesStat', {'n': pack.courseCount.toString()})}',
      price: pack.price,
      compareAtPrice: pack.compareAtPrice,
      badges: [
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
