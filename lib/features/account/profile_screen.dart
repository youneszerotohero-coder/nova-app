import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../shell/student_top_bar.dart';
import 'notifications_screen.dart';
import 'orders_screen.dart';
import 'settings_screen.dart';
import 'wallet_screen.dart';

/// "Account" tab, as on the website (D-084/D-114/D-133): the band, the
/// Student's school identity (read-only, school-managed), then Orders,
/// Wallet & rewards, Notifications and Settings, and signing out. The
/// statistics the website removed from the account (D-084) are gone here too.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final StudentProfile? student = state.profile;
    if (student == null) return const SizedBox.shrink();
    final String name = '${student.firstName} ${student.lastName}'.trim();

    final List<({IconData icon, String label, String subtitle, WidgetBuilder builder, int badge})> rows = [
      (icon: Icons.receipt_long_outlined, label: context.tr('profile.orders'), subtitle: context.tr('profile.ordersSub'), builder: (_) => const OrdersScreen(), badge: 0),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: context.tr('profile.wallet'),
        subtitle: context.trf('profile.walletSub', {'n': student.points.toString()}),
        builder: (_) => const WalletScreen(),
        badge: 0,
      ),
      (
        icon: Icons.notifications_none_rounded,
        label: context.tr('common.notifications'),
        subtitle: context.trf('profile.notificationsSub', {'n': state.unreadCount.toString()}),
        builder: (_) => const NotificationsScreen(),
        badge: state.unreadCount,
      ),
      (icon: Icons.settings_outlined, label: context.tr('profile.settings'), subtitle: context.tr('profile.settingsSub'), builder: (_) => const SettingsScreen(), badge: 0),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 130),
      children: [
        NovaPageHeader(
          showBack: false,
          kicker: context.tr('account.eyebrow'),
          title: context.tr('account.title'),
          lead: context.tr('account.lead'),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Entrance(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NovaColors.paperCard,
                borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
                border: Border.all(color: NovaColors.borderOnLight),
                boxShadow: NovaDimens.shadowCard,
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(17)),
                    child: Text(
                      StudentTopBar.initialsOf(name),
                      style: NovaTypography.textTheme.titleLarge!.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: NovaTypography.textTheme.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          [student.level, student.track].where((String s) => s.isNotEmpty).join(' · '),
                          style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(100)),
                    child: Text(context.tr('account.schoolManaged'), style: NovaTypography.textTheme.labelSmall!.copyWith(color: NovaColors.yellowInk)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (int i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Entrance(
              delay: Duration(milliseconds: 60 * (i + 1)),
              child: PressableScale(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: rows[i].builder)),
                semanticLabel: rows[i].label,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NovaColors.paperCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: NovaColors.borderOnLight),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(14)),
                        child: Icon(rows[i].icon, size: 22, color: NovaColors.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rows[i].label, style: NovaTypography.textTheme.titleMedium),
                            Text(rows[i].subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!)),
                          ],
                        ),
                      ),
                      if (rows[i].badge > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(100)),
                          child: Text('${rows[i].badge}', style: NovaTypography.textTheme.labelSmall!.copyWith(color: Colors.white)),
                        ),
                      Icon(Icons.chevron_right_rounded, size: 22, color: NovaColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: NovaButton(
            label: context.tr('settings.signOut'),
            variant: NovaButtonVariant.danger,
            icon: Icons.logout_rounded,
            expand: true,
            onTap: () => state.session.logout(),
          ),
        ),
      ],
    );
  }
}
