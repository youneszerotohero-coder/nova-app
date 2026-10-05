import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_course_card.dart';
import '../../core/widgets/nova_decor.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../data/catalog_store.dart';
import '../../data/models.dart';
import '../../core/state/app_state.dart';
import 'course_detail_screen.dart';
import 'pack_card.dart';

/// Teacher detail, shaped like a profile: colour block, portrait, the
/// numbers behind them, bio, subjects and the courses they teach.
/// Teacher entities stay read-only per the conception.
class TeacherDetailScreen extends StatelessWidget {
  const TeacherDetailScreen({super.key, required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Course> courses = app.courses
        .where((Course c) => c.teacherId == teacher.id)
        .toList();
    // The backend decides which Offers carry this Teacher (D-062).
    final OfferMatches packs = app.catalog
        .offersMatching(OfferFilter(teacherIds: <int>{teacher.id}));
    final int lessons = courses.fold(
      0,
      (int sum, Course course) => sum + course.lessonsCount,
    );
    final int lives = courses.fold(
      0,
      (int sum, Course course) => sum + course.plannedLives,
    );
    final NovaHue hue = NovaHue.of(teacher.subject);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 130),
        children: [
          _TeacherHeader(teacher: teacher, hue: hue),
          const SizedBox(height: 14),
          Center(
            child: Text(
              teacher.name,
              style: NovaTypography.textTheme.displaySmall,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              teacher.subject,
              style: NovaTypography.textTheme.titleSmall!.copyWith(
                color: hue.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: context.tr('stat.courses'),
                    value: courses.length,
                    hue: hue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    label: context.tr('stat.lessons'),
                    value: lessons,
                    hue: hue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    label: context.tr('stat.lives'),
                    value: lives,
                    hue: hue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NovaCard(
              child: Text(
                teacher.bio,
                style: NovaTypography.textTheme.bodyMedium!.copyWith(
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: teacher.subjects.map((String subject) {
                final NovaHue chipHue = NovaHue.of(subject);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: chipHue.surfaceStrong,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    subject,
                    style: NovaTypography.textTheme.labelMedium!.copyWith(
                      color: chipHue.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (courses.isNotEmpty) ...[
            const SizedBox(height: 26),
            _SectionTitle(
              context.trf('teacher.coursesBy', {'name': teacher.name}),
            ),
            const SizedBox(height: 14),
            ...stagger(
              courses
                  .map(
                    (Course course) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: TeacherCourseRow(course: course),
                    ),
                  )
                  .toList(),
            ),
          ],
          ..._packSection(context, packs, app.catalog),
        ],
      ),
    );
  }

  /// The Teacher's packs: a spinner while the backend filters, a retry
  /// on failure, nothing when they are in no pack.
  List<Widget> _packSection(
    BuildContext context,
    OfferMatches packs,
    CatalogStore catalog,
  ) {
    final ApiException? error = packs.error;
    final List<Pack>? found = packs.packs;
    if (found != null && found.isEmpty) return const <Widget>[];

    return <Widget>[
      const SizedBox(height: 26),
      _SectionTitle(context.trf('teacher.packsBy', {'name': teacher.name})),
      const SizedBox(height: 14),
      if (error != null)
        EmptyState(
          icon: Icons.cloud_off_rounded,
          hue: NovaHue.lilac,
          title: context.tr('seg.packs'),
          message: apiErrorText(context, error),
          actionLabel: context.tr('common.retry'),
          onAction: catalog.load,
        )
      else if (found == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        )
      else
        ...stagger(
          found
              .map(
                (Pack pack) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: PackCard(pack: pack),
                ),
              )
              .toList(),
        ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(text, style: NovaTypography.textTheme.headlineSmall),
    );
  }
}

class _TeacherHeader extends StatelessWidget {
  const _TeacherHeader({required this.teacher, required this.hue});

  final Teacher teacher;
  final NovaHue hue;

  static const double _blockHeight = 168;
  static const double _portrait = 96;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;
    final double height = _blockHeight + topInset;

    return SizedBox(
      height: height + _portrait / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: NovaPageHeader.gradient,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(NovaDimens.radiusCardLarge),
                ),
                boxShadow: hue.shadow,
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: NovaDecor(
                      color: Colors.white,
                      opacity: 0.22,
                      seed: 5,
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    top: topInset + 14,
                    child: Row(
                      children: [
                        FrostedIconButton(
                          icon: Icons.arrow_back_rounded,
                          semanticLabel: context.tr('common.back'),
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Sparkle(size: 11),
                              const SizedBox(width: 7),
                              Text(
                                context.tr('teacher.title').toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  letterSpacing: 1.8,
                                  color: Colors.white,
                                ),
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
          ),
          Positioned(
            left: 0,
            right: 0,
            top: height - _portrait / 2,
            child: Center(
              child: Hero(
                tag: 'teacher-${teacher.name}',
                child: Container(
                  width: _portrait + 10,
                  height: _portrait + 10,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: NovaColors.paper,
                    shape: BoxShape.circle,
                    boxShadow: NovaDimens.shadowCard,
                  ),
                  child: ClipOval(
                    child: NovaSceneImage(
                      scene: teacher.scene,
                      image: teacher.photo,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.hue});

  final String label;
  final int value;
  final NovaHue hue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: hue.surface,
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        border: Border.all(color: hue.solid.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          CountUpText(
            value,
            style: TextStyle(
              fontFamily: 'InterDisplay',
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1,
              letterSpacing: -0.8,
              color: NovaColors.textStrong,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: NovaTypography.textTheme.labelSmall!.copyWith(
              color: hue.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// One course on a teacher's page — the same cover card the catalog
/// uses, in its wide form.
class TeacherCourseRow extends StatelessWidget {
  const TeacherCourseRow({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return NovaCourseCard(
      aspectRatio: 16 / 9.4,
      title: course.title,
      scene: course.scene,
      image: course.image,
      icon: course.icon,
      meta: context.trf(
        'detail.lessonsStat',
        {'n': course.lessons.length.toString()},
      ),
      price: course.owned || course.isFree || course.packOnly ? null : course.price,
      compareAtPrice: course.compareAtPrice,
      actionLabel: course.owned
          ? context.tr('common.open')
          : course.packOnly && !course.isFree
              ? packPriceText(context, course)
              : null,
      badges: [
        CardBadge('${course.subject} · ${course.level}'),
        if (course.owned)
          CardBadge(
            context.tr('common.owned'),
            icon: Icons.check_rounded,
            tone: NovaColors.onlineGreen,
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
