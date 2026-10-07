import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/badge_icon_button.dart';
import '../../core/widgets/circle_icon_button.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/section_header.dart';
import '../account/notifications_screen.dart';
import '../account/profile_screen.dart';
import '../detail/course_detail_screen.dart';
import '../detail/teacher_detail_screen.dart';
import '../../core/state/app_state.dart';
import '../../data/models.dart';
import 'widgets/course_card.dart';
import 'widgets/greeting_header.dart';
import 'widgets/pack_banner_carousel.dart';
import 'widgets/teacher_card.dart';

/// Promotional home: greeting, the pack hero slider, the two headline
/// numbers, then the courses and teachers rails. Search and filtering
/// live on Explore.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.onMenuTap,
    this.onExplore,
  });

  /// Opens the app menu; provided by the shell so the drawer overlays
  /// the whole application.
  final VoidCallback? onMenuTap;

  /// Switches the shell to the Explore tab ("See all").
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Course> courses = app.courses;
    final List<Pack> packs = app.catalog.offers;
    final List<Teacher> teachers = app.catalog.teachers;
    final StudentProfile? student = app.profile;

    return RefreshIndicator(
      onRefresh: () => Future.wait(<Future<void>>[
        app.catalog.load(),
        app.refreshAccount(),
      ]),
      child: ListView(
      // Clear the status bar, then a little air above the header.
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 10,
        bottom: 130,
      ),
      children: [
        _Header(onMenuTap: onMenuTap),
        const SizedBox(height: 20),
        GreetingHeader(
          name: student?.firstName ?? '',
          subtitle: context.tr('home.welcome'),
          avatarLabel: student?.fullName ?? '',
          avatarPhoto: student?.photo,
          onAvatarTap: () => Navigator.of(context).push(
            // Profile is a tab screen; pushed outside the shell it needs
            // its own Scaffold (Material) or its text renders unstyled.
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: ProfileScreen()),
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (packs.isNotEmpty)
        PackBannerCarousel(
          packs: packs,
          onPackTap: (Pack pack) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CourseDetailScreen.pack(pack: pack),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.menu_book_rounded,
                  hue: NovaHue.peach,
                  label: context.tr('stat.lessons'),
                  value: student?.lessonsCompleted ?? 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Watch hours are not provided by the backend; owned
                // courses are.
                child: StatTile(
                  icon: Icons.school_rounded,
                  hue: NovaHue.lilac,
                  label: context.tr('stat.courses'),
                  value: app.learning.owned.length,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NovaDimens.sectionGap),
        SectionHeader(
          title: context.tr('home.popular'),
          actionLabel: context.tr('common.seeAll'),
          onAction: onExplore,
        ),
        SizedBox(
          // Extra room under the cards so their shadow is not clipped.
          height: CourseCard.height + 18,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            scrollDirection: Axis.horizontal,
            itemCount: courses.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, int index) => Entrance(
              delay: Duration(milliseconds: 60 * index),
              child: CourseCard(
                course: courses[index],
                index: index,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CourseDetailScreen(course: courses[index]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: context.tr('home.ourTeachers'),

          actionLabel: context.tr('common.seeAll'),
          onAction: onExplore,
        ),
        SizedBox(
          height: 78,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: teachers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, int index) => TeacherCard(
              teacher: teachers[index],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TeacherDetailScreen(teacher: teachers[index]),
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

class _Header extends StatelessWidget {
  const _Header({this.onMenuTap});

  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          CircleIconButton(
            icon: Icons.menu_rounded,
            semanticLabel: 'Menu',
            onTap: onMenuTap,
          ),
          const Spacer(),
          const _Wordmark(),
          const Spacer(),
          BadgeIconButton(
            icon: Icons.notifications_none_rounded,
            count: AppScope.of(context).unreadCount,
            semanticLabel: 'Notifications',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'nova',
          style: NovaTypography.textTheme.headlineMedium!.copyWith(
            color: NovaColors.textStrong,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            gradient: NovaColors.accentGradient,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
