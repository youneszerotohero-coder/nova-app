import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../shell/student_top_bar.dart';
import 'learning_widgets.dart';
import 'lesson_screen.dart';

/// A Unit, as on the website (D-132): its progress and where to continue,
/// how a Lesson works, then every Lesson as a big row. A Lesson opens on one
/// page with its video, its PDF and its quiz. A past Live is a Lesson too.
class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key, required Course this.course}) : notifier = null;

  /// Shares the Course with its Lesson pages, so their progress shows here.
  const LearnScreen.of(ValueNotifier<Course> this.notifier, {super.key}) : course = null;

  final Course? course;
  final ValueNotifier<Course>? notifier;

  /// Where to continue, as `/me/dashboard` chooses it: the unfinished Lesson
  /// with the furthest resume point, else the first not finished, else the first.
  static int resumeIndex(List<Lesson> lessons) {
    if (lessons.isEmpty) return -1;
    int best = -1;
    for (int i = 0; i < lessons.length; i++) {
      final Lesson lesson = lessons[i];
      if (lesson.completed || lesson.resumeSeconds <= 0) continue;
      if (best == -1 || lesson.resumeSeconds > lessons[best].resumeSeconds) best = i;
    }
    if (best != -1) return best;
    final int firstOpen = lessons.indexWhere((Lesson l) => !l.completed);
    return firstOpen == -1 ? 0 : firstOpen;
  }

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  late final ValueNotifier<Course> _course = widget.notifier ?? ValueNotifier<Course>(widget.course!);

  @override
  void dispose() {
    if (widget.notifier == null) _course.dispose();
    super.dispose();
  }

  void _open(int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LessonScreen(course: _course, index: index)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<Course>(
        valueListenable: _course,
        builder: (BuildContext context, Course course, _) {
          final List<Lesson> lessons = course.lessons;
          final int resume = LearnScreen.resumeIndex(lessons);
          final bool started = lessons.any((Lesson l) => l.completed || l.watched > 0);
          final bool rtl = Directionality.of(context) == TextDirection.rtl;
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const StudentTopBar(showBack: true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Entrance(
                  child: HeroBand(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HeroEyebrow([course.subject, course.teacher].where((String s) => s.isNotEmpty).join(' · ')),
                        const SizedBox(height: 6),
                        HeroTitle(course.title, size: 30, maxLines: 3),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('unit.lead'),
                          style: NovaTypography.textTheme.bodyLarge!.copyWith(color: Colors.white.withValues(alpha: 0.86)),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            PercentRing(
                              percent: course.progressPercent.clamp(0, 100),
                              size: 64,
                              color: NovaColors.yellow,
                              track: Colors.white.withValues(alpha: 0.22),
                              textColor: Colors.white,
                              stroke: 6,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.trf('units.lessonsDone', {
                                  'done': course.completedLessons.toString(),
                                  'total': lessons.length.toString(),
                                }),
                                style: NovaTypography.textTheme.titleMedium!.copyWith(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        if (resume >= 0) ...[
                          const SizedBox(height: 16),
                          NovaButton(
                            label: started
                                ? context.trf('unit.resume', {'title': lessons[resume].title})
                                : context.tr('unit.startFirst'),
                            variant: NovaButtonVariant.yellow,
                            expand: true,
                            chipIcon: Icons.play_arrow_rounded,
                            onTap: () => _open(resume),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              HowToStrip(
                steps: [
                  (icon: Icons.lightbulb_outline_rounded, text: context.tr('unit.howTo1')),
                  (icon: Icons.ondemand_video_rounded, text: context.tr('unit.howTo2')),
                  (icon: Icons.description_outlined, text: context.tr('unit.howTo3')),
                ],
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(context.tr('unit.lessons'), style: NovaTypography.textTheme.headlineMedium),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(100)),
                      child: Text('${lessons.length}', style: NovaTypography.textTheme.labelLarge!.copyWith(color: NovaColors.accent)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (lessons.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: HeroEmpty(icon: Icons.video_library_outlined, title: context.tr('unit.noLessons'), message: context.tr('unit.noLessonsText')),
                )
              else
                for (int i = 0; i < lessons.length; i++)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Entrance(
                      delay: Duration(milliseconds: 35 * i),
                      child: LessonRow(
                        number: i + 1,
                        lesson: lessons[i],
                        next: i == resume && !lessons[i].completed,
                        started: started,
                        rtl: rtl,
                        onTap: () => _open(i),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// A Lesson of the Unit (`.unitLesson`): its number (a tick once complete, a
/// ring while started), its title and what it holds, "Continue here" on the
/// Lesson to continue.
class LessonRow extends StatelessWidget {
  const LessonRow({
    super.key,
    required this.number,
    required this.lesson,
    required this.next,
    required this.started,
    required this.rtl,
    required this.onTap,
  });

  final int number;
  final Lesson lesson;
  final bool next;
  final bool started;
  final bool rtl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool done = lesson.completed;
    final int watched = done ? 0 : lesson.watched.clamp(0, 99);
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: lesson.title,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: next ? Color.alphaBlend(NovaColors.yellow.withValues(alpha: 0.14), NovaColors.paperCard) : NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
          border: Border.all(color: next ? NovaColors.yellow : NovaColors.borderOnLight, width: 1.5),
          boxShadow: NovaDimens.shadowCard,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done
                    ? NovaColors.onlineGreen.withValues(alpha: 0.16)
                    : next
                        ? NovaColors.yellow
                        : NovaColors.accentMist,
                borderRadius: BorderRadius.circular(15),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 26, color: NovaColors.onlineGreen)
                  : watched > 0
                      ? PercentRing(percent: watched, size: 42, stroke: 4)
                      : Text(
                          '$number',
                          style: NovaTypography.textTheme.headlineSmall!.copyWith(color: next ? NovaColors.yellowInk : NovaColors.accent),
                        ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.titleMedium!.copyWith(fontSize: 17)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      HeroChip(
                        icon: Icons.ondemand_video_rounded,
                        label: lesson.minutes > 0
                            ? context.trf('unit.minutes', {'n': lesson.minutes.toString()})
                            : context.tr('lesson.durationPending'),
                      ),
                      if (lesson.hasPdf)
                        HeroChip(icon: Icons.description_outlined, label: 'PDF', color: NovaColors.heartRed, background: NovaColors.heartRed.withValues(alpha: 0.1)),
                      if (lesson.hasQuiz)
                        HeroChip(icon: Icons.help_outline_rounded, label: context.tr('learn.rowQuiz'), color: NovaColors.badgeOrange, background: NovaColors.yellow.withValues(alpha: 0.28)),
                      if (lesson.fromLive)
                        HeroChip(icon: Icons.sensors_rounded, label: context.tr('unit.fromLive'), color: const Color(0xFF2F86DA), background: const Color(0x2E4FACF0)),
                      if (done)
                        HeroChip(icon: Icons.check_circle_outline_rounded, label: context.tr('lesson.completed'), color: NovaColors.onlineGreen, background: NovaColors.onlineGreen.withValues(alpha: 0.14)),
                    ],
                  ),
                  if (next) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(100)),
                      child: Text(
                        started ? context.tr('unit.continueHere') : context.tr('unit.startHere'),
                        style: NovaTypography.textTheme.labelMedium!.copyWith(color: NovaColors.yellowInk),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 22, color: NovaColors.accent),
          ],
        ),
      ),
    );
  }
}
