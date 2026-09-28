import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_course_card.dart';
import '../../core/widgets/nova_decor.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/nova_segment.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../../core/state/app_state.dart';
import 'open_course.dart';
import 'live_room_screen.dart';

/// "My courses" tab: the shared header block, the Courses / Lives
/// switch, then either the enrolled cover cards with their live
/// progress or the lives calendar (live now / upcoming / replays).
class MyLearningScreen extends StatefulWidget {
  const MyLearningScreen({super.key, this.initialSegment = 0});

  final int initialSegment;

  @override
  State<MyLearningScreen> createState() => _MyLearningScreenState();
}

class _MyLearningScreenState extends State<MyLearningScreen> {
  late int _segment = widget.initialSegment;
  int _liveFilter = 0;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Course> enrolled = app.learning.owned;
    final int lessons = enrolled.fold(
      0,
      (int sum, Course course) => sum + course.lessonsCount,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 130),
      children: [
        NovaPageHeader(
          title: context.tr('tab.myCourses'),
          kicker: '${context.tr('learning.title')} · '
              '${context.trf('learning.lessonsCount', {'n': lessons.toString()})}',
          watermark: Icons.school_rounded,
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: NovaSegment(
            expand: false,
            selected: _segment,
            onChanged: (int i) => setState(() => _segment = i),
            items: [
              SegmentItem(
                icon: Icons.menu_book_rounded,
                label: context.trf(
                  'learning.videosCount',
                  {'n': lessons.toString()},
                ),
              ),
              SegmentItem(
                icon: Icons.podcasts_rounded,
                label: context.trf(
                  'learning.livesCount',
                  {'n': app.learning.lives.length.toString()},
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> a) =>
              FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: _segment == 0
              ? _Courses(key: const ValueKey<int>(0), courses: enrolled)
              : _Lives(
                  key: const ValueKey<int>(1),
                  filter: _liveFilter,
                  onFilter: (int i) => setState(() => _liveFilter = i),
                ),
        ),
      ],
    );
  }
}

class _Courses extends StatelessWidget {
  const _Courses({super.key, required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return EmptyState(
        icon: Icons.play_lesson_rounded,
        hue: NovaHue.mint,
        title: context.tr('learning.noCourses'),
        message: context.tr('learning.noCoursesMsg'),
      );
    }

    return Column(
      children: stagger(
        [
          for (int i = 0; i < courses.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: _EnrolledCard(course: courses[i]),
            ),
        ],
      ),
    );
  }
}

/// An enrolled course: the shared cover card, with the classmates on
/// it and completion drawn around the arrow.
class _EnrolledCard extends StatelessWidget {
  const _EnrolledCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final bool complete = course.progressPercent >= 100;

    return NovaCourseCard(
      aspectRatio: 16 / 10.8,
      heroTag: 'cover-${course.title}',
      title: course.title,
      scene: course.scene,
      image: course.image,
      icon: course.icon,
      meta: context.trf('learning.lessonsOf', {
        'a': course.completedLessons.toString(),
        'b': course.lessonsCount.toString(),
        'teacher': course.teacher,
      }),
      actionLabel: complete
          ? context.tr('learning.completedYear')
          : context.tr('learning.resume'),
      progressPercent: course.progressPercent,
      badges: [
        CardBadge(course.subject),
        if (complete)
          CardBadge(
            context.tr('common.owned'),
            icon: Icons.verified_rounded,
            tone: NovaColors.onlineGreen,
          ),
      ],
      onTap: () => openOwnedCourse(context, course),
    );
  }
}

class _Lives extends StatelessWidget {
  const _Lives({super.key, required this.filter, required this.onFilter});

  static const List<String> _liveFilterKeys = [
    'learning.all',
    'learning.liveNow',
    'learning.upcoming',
    'learning.replays',
  ];

  final int filter;
  final ValueChanged<int> onFilter;

  @override
  Widget build(BuildContext context) {
    final List<LiveSession> sessions = AppScope.of(context).learning.lives.where(
      (LiveSession live) {
        return switch (filter) {
          1 => live.status == LiveStatus.live,
          2 => live.status == LiveStatus.scheduled,
          3 => live.status == LiveStatus.replay,
          _ => true,
        };
      },
    ).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 42,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _liveFilterKeys.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, int index) {
              final bool active = index == filter;
              return PressableScale(
                onTap: () => onFilter(index),
                pressedScale: 0.94,
                semanticLabel: context.tr(_liveFilterKeys[index]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        active ? NovaColors.ink950 : NovaColors.subtleFill,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: active
                          ? NovaColors.ink950
                          : NovaColors.borderOnLight,
                    ),
                  ),
                  child: Text(
                    context.tr(_liveFilterKeys[index]),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: active
                          ? NovaColors.textOnDark
                          : NovaColors.textStrong,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (sessions.isEmpty)
          EmptyState(
            icon: Icons.podcasts_rounded,
            title: context.tr('learning.nothingFiltered'),
            message: context.tr('learning.nothingFilteredMsg'),
          )
        else
          ...stagger(
            sessions
                .map(
                  (LiveSession live) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: LiveTicketCard(live: live),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

/// Big live ticket card: status badge, attendees, title, CTA.
class LiveTicketCard extends StatelessWidget {
  const LiveTicketCard({super.key, required this.live});

  final LiveSession live;

  @override
  Widget build(BuildContext context) {
    final bool isLive = live.status == LiveStatus.live;
    final bool isReplay = live.status == LiveStatus.replay;

    final (String badge, IconData actionIcon) = switch (live.status) {
      LiveStatus.live => ('LIVE', Icons.play_arrow_rounded),
      LiveStatus.scheduled => (
          live.scheduledLabel ?? context.tr('learning.upcoming'),
          Icons.notifications_rounded,
        ),
      LiveStatus.replay => (
          context.tr('live.replayBadge'),
          Icons.play_arrow_rounded,
        ),
    };

    return PressableScale(
      onTap: () {
        if (isLive || isReplay) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LiveRoomScreen(live: live),
            ),
          );
        } else {
          novaToast(
            context,
            context.tr('learning.reminderSet'),
            icon: Icons.notifications_active_rounded,
          );
        }
      },
      semanticLabel: live.title,
      child: Container(
        height: 184,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NovaDimens.radiusHero),
          boxShadow: NovaDimens.shadowSoft,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NovaSceneImage(scene: live.scene, image: live.image),
            const Positioned.fill(
              child: NovaDecor(color: Colors.white, opacity: 0.2, seed: 6),
            ),
            // Bottom scrim so the title always wins over the artwork.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.42, 1],
                    colors: [Colors.transparent, Color(0x99131F3A)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: _LiveBadge(status: live.status, label: badge),
            ),
            if (isLive)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${live.attendees}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live.course.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          live.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'InterDisplay',
                            fontWeight: FontWeight.w700,
                            fontSize: 19,
                            height: 1.15,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      RoundArrowButton(icon: actionIcon, size: 46),
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

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.status, required this.label});

  final LiveStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bool isLive = status == LiveStatus.live;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color:
            isLive ? NovaColors.heartRed : Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Pulse(
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.6,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
