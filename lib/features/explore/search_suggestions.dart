import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';

/// The dropdown under the Explore search field: the packs and courses
/// matching what the Student is typing, each opening its page directly.
class SearchSuggestions extends StatelessWidget {
  const SearchSuggestions({
    super.key,
    required this.packs,
    required this.courses,
    required this.maxHeight,
    required this.onPack,
    required this.onCourse,
  });

  final List<Pack> packs;
  final List<Course> courses;
  final double maxHeight;
  final ValueChanged<Pack> onPack;
  final ValueChanged<Course> onCourse;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      if (packs.isNotEmpty) _SectionLabel(context.tr('seg.packs')),
      for (final Pack pack in packs)
        _SuggestionRow(
          title: pack.name,
          subtitle: context.trf(
            'detail.coursesStat',
            {'n': pack.courseCount.toString()},
          ),
          trailing: formatDaPrice(pack.price),
          scene: pack.scene,
          image: pack.image,
          icon: pack.icon,
          semanticLabel: 'Suggestion pack ${pack.name}',
          onTap: () => onPack(pack),
        ),
      if (courses.isNotEmpty) _SectionLabel(context.tr('seg.courses')),
      for (final Course course in courses)
        _SuggestionRow(
          title: course.title,
          subtitle: <String>[course.subject, course.teacher]
              .where((String part) => part.isNotEmpty)
              .join(' · '),
          trailing: course.owned
              ? context.tr('common.owned')
              : course.isFree
                  ? context.tr('common.free')
                  : formatDaPrice(course.price),
          scene: course.scene,
          image: course.image,
          icon: course.icon,
          semanticLabel: 'Suggestion course ${course.title}',
          onTap: () => onCourse(course),
        ),
    ];

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        border: Border.all(color: NovaColors.borderOnLight),
        boxShadow: NovaDimens.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      // The overlay sits above the page's Material: text needs its own.
      child: Material(
        type: MaterialType.transparency,
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 20,
                      color: NovaColors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('explore.noSuggestion'),
                        style: NovaTypography.muted(
                          NovaTypography.textTheme.bodyMedium!,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                children: rows,
              ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
      child: Text(
        label,
        style: NovaTypography.textTheme.labelMedium!.copyWith(
          color: NovaColors.textMuted,
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.scene,
    required this.image,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final NovaScene scene;
  final String? image;
  final IconData? icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 50,
                height: 50,
                child: NovaSceneImage(
                  scene: scene,
                  image: image,
                  icon: icon,
                  iconScale: 0.45,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTypography.textTheme.titleSmall,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTypography.muted(
                        NovaTypography.textTheme.bodySmall!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              trailing,
              style: NovaTypography.textTheme.labelMedium!.copyWith(
                color: NovaColors.accentDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: NovaColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
