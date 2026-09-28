import 'package:flutter/material.dart';

import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_dimens.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/widgets/hue_card.dart';
import '../../../core/widgets/monogram_avatar.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/models.dart';

/// Teacher profile pill in the horizontal "Our teachers" rail: a
/// haloed portrait, the subject they own, and an arrow in their hue.
class TeacherCard extends StatelessWidget {
  const TeacherCard({super.key, required this.teacher, this.onTap});

  final Teacher teacher;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final NovaHue hue = NovaHue.of(teacher.subject);

    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Open teacher ${teacher.name}',
      child: Container(
        width: 256,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusChip),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowSoft,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hue.surface,
                border: Border.all(
                  color: hue.solid.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: MonogramAvatar(
                label: teacher.name,
                photo: teacher.photo,
                size: 46,
                showRing: false,
                colors: teacher.scene.colors.sublist(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    teacher.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTypography.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    teacher.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTypography.textTheme.bodySmall!.copyWith(
                      color: hue.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Decorative: the whole pill is the tap target.
            RoundArrowButton(
              icon: Icons.arrow_outward_rounded,
              size: 36,
              background: hue.surfaceStrong,
              foreground: hue.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

