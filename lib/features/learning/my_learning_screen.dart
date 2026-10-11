import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../explore/explore_screen.dart';
import 'learning_widgets.dart';
import 'open_course.dart';

/// "My lessons" tab, the website's My units (D-132): a short "how it works"
/// strip, then one card per Unit with its progress, the next Lesson and one
/// big button that opens it (video, PDF and quiz on one page).
class MyLearningScreen extends StatelessWidget {
  const MyLearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Course> units = app.learning.owned;

    return RefreshIndicator(
      onRefresh: app.learning.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 130),
        children: [
          NovaPageHeader(
            showBack: false,
            kicker: context.tr('units.eyebrow'),
            title: context.tr('units.title'),
            lead: context.tr('units.lead'),
          ),
          const SizedBox(height: 16),
          HowToStrip(
            steps: [
              (icon: Icons.menu_book_outlined, text: context.tr('units.howTo1')),
              (icon: Icons.lightbulb_outline_rounded, text: context.tr('units.howTo2')),
              (icon: Icons.ondemand_video_rounded, text: context.tr('units.howTo3')),
            ],
          ),
          const SizedBox(height: 18),
          if (units.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: HeroEmpty(
                icon: Icons.menu_book_outlined,
                title: context.tr('units.empty'),
                message: context.tr('units.emptyText'),
                action: NovaButton(
                  label: context.tr('units.browse'),
                  chipIcon: Icons.arrow_forward_rounded,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: ExploreScreen()))),
                ),
              ),
            )
          else
            for (int i = 0; i < units.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Entrance(
                  delay: Duration(milliseconds: 60 * i),
                  child: UnitProgressCard(course: units[i], resume: app.learning.resumeLesson(units[i].id)),
                ),
              ),
        ],
      ),
    );
  }
}

/// One Unit of My units (`.unitCard`): cover, progress, "Continue" straight
/// into the next Lesson, and the Lesson list.
class UnitProgressCard extends StatelessWidget {
  const UnitProgressCard({super.key, required this.course, this.resume});

  final Course course;
  final ({int id, String title})? resume;

  @override
  Widget build(BuildContext context) {
    final int percent = course.progressPercent.clamp(0, 100);
    final bool started = percent > 0 || course.completedLessons > 0 || resume != null;

    return PressableScale(
      onTap: () => openOwnedCourse(context, course),
      pressedScale: 0.985,
      semanticLabel: course.title,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NovaSceneImage(scene: course.scene, image: course.image, icon: course.icon),
                  if (percent >= 100)
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: NovaColors.onlineGreen, borderRadius: BorderRadius.circular(100)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, size: 15, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(context.tr('units.completed'), style: NovaTypography.textTheme.labelMedium!.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [course.subject, course.teacher].where((String s) => s.isNotEmpty).join(' · '),
                    style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(course.title, style: NovaTypography.textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  GreenProgress(percent: percent),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.trf('units.lessonsDone', {
                            'done': course.completedLessons.toString(),
                            'total': course.lessonsCount.toString(),
                          }),
                          style: NovaTypography.textTheme.labelMedium!.copyWith(color: NovaColors.textMuted),
                        ),
                      ),
                      Text('‎$percent%', style: NovaTypography.textTheme.labelMedium!.copyWith(color: NovaColors.textMuted)),
                    ],
                  ),
                  if (resume != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.play_arrow_rounded, size: 16, color: NovaColors.accent),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: NovaTypography.textTheme.bodySmall!.copyWith(color: NovaColors.textStrong.withValues(alpha: 0.75)),
                                children: [
                                  TextSpan(text: '${context.tr('units.nextLesson')} '),
                                  TextSpan(text: resume!.title, style: TextStyle(fontWeight: FontWeight.w800, color: NovaColors.textStrong)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: NovaButton(
                          label: started ? context.tr('units.continue') : context.tr('units.start'),
                          variant: NovaButtonVariant.yellow,
                          small: true,
                          expand: true,
                          chipIcon: Icons.play_arrow_rounded,
                          onTap: () => openOwnedCourse(context, course, lessonId: resume?.id),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: NovaButton(
                          label: context.tr('units.allLessons'),
                          variant: NovaButtonVariant.ghost,
                          small: true,
                          expand: true,
                          icon: Icons.format_list_bulleted_rounded,
                          onTap: () => openOwnedCourse(context, course),
                        ),
                      ),
                    ],
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
