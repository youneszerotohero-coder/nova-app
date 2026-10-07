import 'package:flutter/material.dart';

import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/nova_course_card.dart';
import '../../data/models.dart';
import 'course_detail_screen.dart';

/// One Unit card (website `CourseCard`), opening the Unit page — the home
/// rail and Explore list Units with it.
class UnitCard extends StatelessWidget {
  const UnitCard({super.key, required this.course, this.width});

  final Course course;

  /// Fixed width in a horizontal rail.
  final double? width;

  @override
  Widget build(BuildContext context) {
    return NovaCourseCard(
      width: width,
      heroTag: 'cover-${course.title}',
      title: course.title,
      scene: course.scene,
      image: course.image,
      icon: course.icon,
      meta: course.teacher,
      // Free Units are joined, never sold (D-054).
      price: course.isFree || course.packOnly ? null : course.price,
      compareAtPrice: course.compareAtPrice,
      actionLabel: course.owned
          ? context.tr('common.open')
          : course.isFree
              ? context.tr('common.free')
              : course.packOnly
                  ? packPriceText(context, course)
                  : null,
      badges: [
        if (course.owned)
          CardBadge(
            context.tr('common.owned'),
            icon: Icons.check_rounded,
            tone: NovaColors.onlineGreen,
          )
        else if (course.discountPercent > 0)
          CardBadge(
            formatDiscount(course.discountPercent),
            tone: NovaColors.heartRed,
          ),
      ],
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CourseDetailScreen(course: course),
        ),
      ),
    );
  }
}
