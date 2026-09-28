import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/activity_chart.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/monogram_avatar.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_decor.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/section_header.dart';
import '../cart/cart_screen.dart';
import '../../data/models.dart';
import '../learning/my_learning_screen.dart';
import 'notifications_screen.dart';
import 'orders_screen.dart';
import 'settings_screen.dart';
import 'wallet_screen.dart';

/// Profile tab: the Student hub, built like a social profile — cover,
/// portrait, identity, the numbers that describe a learner, then
/// badges, this week's activity and the account shortcuts.
///
/// Academic identity stays read-only (school-managed per the
/// conception); "Edit profile" says so rather than pretending.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final StudentProfile? student = state.profile;
    if (student == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.only(bottom: 130),
      children: [
        _ProfileHeader(student: student, unread: state.unreadCount),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _WeekCard(student: student),
        ),
        const SizedBox(height: NovaDimens.sectionGap),
        SectionHeader(title: context.tr('profile.shortcuts')),
        ...stagger(
          _Destination.tiles(
            context,
            [
              _Destination(
                icon: Icons.receipt_long_rounded,
                hue: NovaHue.sky,
                label: context.tr('profile.orders'),
                subtitle: context.tr('profile.ordersSub'),
                builder: (_) => const OrdersScreen(),
              ),
              _Destination(
                icon: Icons.stars_rounded,
                hue: NovaHue.butter,
                label: context.tr('profile.wallet'),
                subtitle: context.trf(
                  'profile.walletSub',
                  {'n': student.points.toString()},
                ),
                builder: (_) => const WalletScreen(),
              ),
              _Destination(
                icon: Icons.notifications_rounded,
                hue: NovaHue.rose,
                label: context.tr('common.notifications'),
                subtitle: context.trf(
                  'profile.notificationsSub',
                  {'n': state.unreadCount.toString()},
                ),
                badge: state.unreadCount,
                builder: (_) => const NotificationsScreen(),
              ),
              _Destination(
                icon: Icons.shopping_bag_outlined,
                hue: NovaHue.peach,
                label: context.tr('tab.cart'),
                subtitle: state.itemCount == 1
                    ? context.tr('profile.cartSubOne')
                    : context.trf(
                        'profile.cartSub',
                        {'n': state.itemCount.toString()},
                      ),
                // Tab screens rely on the shell's Scaffold for their
                // Material; pushed alone they need their own.
                builder: (_) => const Scaffold(body: CartScreen()),
              ),
              _Destination(
                icon: Icons.play_lesson_rounded,
                hue: NovaHue.mint,
                label: context.tr('profile.myLearning'),
                subtitle: context.tr('profile.myLearningSub'),
                builder: (_) => const Scaffold(body: MyLearningScreen()),
              ),
              _Destination(
                icon: Icons.settings_outlined,
                hue: NovaHue.lilac,
                label: context.tr('profile.settings'),
                subtitle: context.tr('profile.settingsSub'),
                builder: (_) => const SettingsScreen(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cover, portrait with its edit button, and the Student's name.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.student, required this.unread});

  final StudentProfile student;
  final int unread;

  static const double _coverHeight = 190;
  static const double _avatarSize = 104;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;

    return Column(
      children: [
        SizedBox(
          height: _coverHeight + topInset + _avatarSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _Cover(height: _coverHeight + topInset, unread: unread),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: _coverHeight + topInset - _avatarSize / 2,
                child: Center(
                  child: _Portrait(student: student, size: _avatarSize),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              student.fullName,
              style: NovaTypography.textTheme.displaySmall,
            ),
            const SizedBox(width: 7),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                gradient: NovaColors.accentGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.height, required this.unread});

  final double height;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: NovaPageHeader.gradient,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(NovaDimens.radiusCardLarge),
        ),
        boxShadow: NovaDimens.shadowCard,
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: NovaDecor(color: Colors.white, opacity: 0.26, seed: 2),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: MediaQuery.paddingOf(context).top + 10,
            child: Row(
              children: [
                // Only when pushed (avatar tap on Home), not as a tab.
                if (ModalRoute.of(context)?.impliesAppBarDismissal ?? false) ...[
                  _FrostedButton(
                    icon: Icons.arrow_back_rounded,
                    semanticLabel: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                ],
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
                      const Sparkle(size: 12),
                      const SizedBox(width: 7),
                      Text(
                        context.tr('profile.verified'),
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
                const Spacer(),
                _FrostedButton(
                  icon: Icons.notifications_none_rounded,
                  badge: unread,
                  semanticLabel: context.tr('common.notifications'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FrostedButton(
                  icon: Icons.settings_outlined,
                  semanticLabel: context.tr('profile.settings'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.student, required this.size});

  final StudentProfile student;
  final double size;

  /// Diameter of the edit button that sits on the portrait's rim.
  static const double _edit = 38;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size + 10,
            height: size + 10,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: NovaColors.paper,
              shape: BoxShape.circle,
              boxShadow: NovaDimens.shadowCard,
            ),
            child: MonogramAvatar(
              label: student.fullName,
              photo: student.photo,
              size: size,
              showRing: false,
              colors: const [Color(0xFF7A67F0), NovaColors.accentDeep],
            ),
          ),
          // Pinned to the lower rim at about 4 o'clock (mirrored in
          // RTL), close enough to read as "edit this picture".
          PositionedDirectional(
            end: -2,
            bottom: 2,
            child: PressableScale(
              onTap: () => novaToast(
                context,
                context.tr('profile.editManaged'),
                icon: Icons.school_rounded,
              ),
              pressedScale: 0.88,
              semanticLabel: context.tr('profile.editProfile'),
              child: Container(
                width: _edit,
                height: _edit,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: NovaColors.accentGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: NovaColors.paper, width: 3.5),
                  boxShadow: NovaDimens.shadowAccent,
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedButton extends StatelessWidget {
  const _FrostedButton({
    required this.icon,
    required this.semanticLabel,
    this.badge = 0,
    this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.9,
      semanticLabel: semanticLabel,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            if (badge > 0)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: NovaColors.badgeOrange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      height: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.student});

  final StudentProfile student;

  @override
  Widget build(BuildContext context) {
    final int total = student.weeklyLessons.fold(0, (int a, int b) => a + b);

    return HueCard(
      hue: NovaHue.peach,
      // No decor here: doodles behind bars fight the data.
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(
                icon: Icons.insights_rounded,
                hue: NovaHue.peach,
                filled: true,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('profile.thisWeek'),
                      style: NovaTypography.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.trf(
                        'profile.weekSummary',
                        {'n': total.toString()},
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTypography.textTheme.bodySmall!.copyWith(
                        color: NovaHue.peach.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Streaks are not provided by the backend (UNSPECIFIED).
              if (student.streakDays > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: NovaColors.ink950,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      size: 14,
                      color: NovaColors.badgeOrange,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${student.streakDays}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: NovaColors.textOnDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          WeeklyBars(
            values: student.weeklyLessons,
            labels: _dayLabels(context, student.weeklyDates),
            hue: NovaHue.peach,
            barHeight: 104,
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.builder,
    required this.hue,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final WidgetBuilder builder;
  final NovaHue hue;
  final int badge;

  /// Builds the destination tiles inside one list of entrance widgets.
  static List<Widget> tiles(
    BuildContext context,
    List<_Destination> destinations,
  ) {
    return destinations.map(
      (_Destination destination) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: _DestinationTile(destination: destination),
        );
      },
    ).toList();
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.destination});

  final _Destination destination;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: destination.builder),
      ),
      semanticLabel: destination.label,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowSoft,
        ),
        child: Row(
          children: [
            IconTile(
              icon: destination.icon,
              hue: destination.hue,
              size: 46,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.label,
                    style: NovaTypography.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTypography.muted(
                      NovaTypography.textTheme.bodySmall!,
                    ),
                  ),
                ],
              ),
            ),
            if (destination.badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  color: NovaColors.accent,
                  borderRadius: BorderRadius.all(Radius.circular(100)),
                ),
                child: Text(
                  '${destination.badge}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: NovaColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Short day names for the activity columns: the weekday of each date
/// the dashboard reported, or Monday to Sunday when there are none.
List<String> _dayLabels(BuildContext context, List<DateTime> dates) {
  final List<String> names = <String>[
    for (final String key in const <String>[
      'day.mon', 'day.tue', 'day.wed', 'day.thu', 'day.fri', 'day.sat', 'day.sun',
    ])
      context.tr(key),
  ];
  if (dates.isEmpty) return names;
  return <String>[for (final DateTime d in dates) names[d.weekday - 1]];
}
