import 'package:flutter/material.dart';

import '../../core/desktop/desktop_layout.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/widgets/appearance_controls.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_toast.dart';
import '../../data/models.dart';
import '../shell/student_top_bar.dart';
import 'dashboard_card.dart';
import 'delete_account_screen.dart';
import 'password_change_form.dart';

/// The website's `/account/settings` (`SettingsView`, `profile.tsx`): the
/// band, then three cards — the school-managed profile (read-only), the
/// notifications, and security with the password change by code (D-093)
/// and sign out. The app adds what the page lacks there: appearance (dark
/// mode + language) and account deletion (D-118), in the same card style.
/// It is the Account tab (no back button) and the top bar's avatar page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _inAppAlerts = true;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final StudentProfile? student = app.profile;
    final bool twoColumns = desktopLayoutOf(context) && MediaQuery.sizeOf(context).width >= 1000;
    // As a tab the floating bottom bar covers the end of the page (none in
    // the PC app's desktop layout).
    final bool tab = ShellNav.maybeOf(context) != null && !desktopLayoutOf(context);
    final List<Widget> cards = <Widget>[
      _profileCard(context, student),
      _notificationsCard(context),
      _securityCard(context, app, student),
      DashboardCard(title: context.tr('settings.appearance'), child: const AppearanceControls()),
      _deleteCard(context),
    ];
    return Scaffold(
      backgroundColor: NovaColors.paper,
      // A short page of forms: built at once (no lazy list), so every card
      // keeps its state while scrolled away.
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: tab ? 130 : 40 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NovaPageHeader(
              kicker: context.tr('dash.settings_eyebrow'),
              title: context.tr('settings.title'),
              lead: context.tr('dash.settings_desc'),
            ),
            const SizedBox(height: 20),
            if (twoColumns)
              // D-193, PC app: the cards in two columns (identity and security
              // on the start side; alerts, appearance, account on the end).
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final List<int> column in const <List<int>>[<int>[0, 2], <int>[1, 3, 4]]) ...[
                      if (column.first != 0) const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final int i in column)
                              Padding(padding: const EdgeInsets.only(bottom: 18), child: cards[i]),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              )
            else
              for (int i = 0; i < cards.length; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                  child: Entrance(delay: Duration(milliseconds: 50 * i), child: cards[i]),
                ),
            Center(
              // D-168: a long press measures this phone's DRM now (hidden
              // support action; the app also does it once per version).
              child: GestureDetector(
                onLongPress: () => _measureNow(context, app),
                child: Text(
                  'noova.elearning@gmail.com · © 2026 Nova Learning',
                  style: heroText(12.5, color: NovaColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The D-168 measurement on demand, with a short technical summary.
  Future<void> _measureNow(BuildContext context, AppState app) async {
    final int? user = app.session.profile?.id;
    if (app.measurement == null || user == null || app.session.isTeacher) return;
    novaToast(context, '…', icon: Icons.memory_rounded);
    final Map<String, dynamic>? sent = await app.measurement!.runNow(user);
    if (!context.mounted) return;
    novaToast(
      context,
      sent == null
          ? '—'
          : <Object?>[
              sent['security_level'] ?? sent['platform'],
              if (sent['max_hdcp'] != null) 'HDCP ${sent['max_hdcp']}',
              'HW ${sent['hardware_test']}${sent['hardware_test_error'] == null ? '' : ' (${sent['hardware_test_error']})'}',
              'SW ${sent['software_test']}${sent['software_test_error'] == null ? '' : ' (${sent['software_test_error']})'}',
              if (sent['integrity_token'] != null) 'PI ✓',
              if (sent['integrity_error_code'] != null) 'PI ${sent['integrity_error_code']}',
            ].join(' · '),
      icon: Icons.memory_rounded,
    );
  }

  /// `.profileSettingsCard`: the avatar block and the identity fields.
  Widget _profileCard(BuildContext context, StudentProfile? student) {
    final String name = student?.fullName ?? '';
    final String academic = <String>[student?.level ?? '', student?.track ?? ''].where((String s) => s.isNotEmpty).join(' · ');
    return DashboardCard(
      kicker: context.tr('dash.student_profile'),
      title: context.tr('dash.personal_info'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `.settingsAvatar`: surface-2, the blue initials tile, the yellow
          // "school managed" chip.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(16)),
                  child: Text(StudentTopBar.initialsOf(name), style: heroLabel(15, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heroLabel(17)),
                      if (academic.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(academic, style: heroText(14, color: NovaColors.textMuted, height: 1.4)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(10)),
                  child: Text(context.tr('dash.school_managed'), style: heroLabel(13, color: NovaColors.yellowInk)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          for (final (String label, String value, bool ltr) in <(String, String, bool)>[
            (context.tr('dash.full_name'), name, false),
            // A phone number reads left to right in Arabic too.
            (context.tr('dash.phone'), student?.phone ?? '', true),
            (context.tr('dash.level'), academic, false),
            (context.tr('dash.wilaya'), student?.wilaya ?? '', false),
            (context.tr('dash.commune'), student?.commune ?? '', false),
            (context.tr('dash.referral_code'), student?.referralCode ?? '', true),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoField(label: label, value: value, ltr: ltr),
            ),
        ],
      ),
    );
  }

  Widget _notificationsCard(BuildContext context) {
    return DashboardCard(
      kicker: context.tr('dash.notifications'),
      title: context.tr('dash.notifications_title'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.notifications_none_rounded, size: 20, color: NovaColors.accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('settings.inAppAlerts'), style: heroLabel(15)),
                const SizedBox(height: 3),
                Text(context.tr('settings.alertsSub'), style: heroText(13.5, color: NovaColors.textMuted, height: 1.45)),
              ],
            ),
          ),
          Switch(
            value: _inAppAlerts,
            activeThumbColor: Colors.white,
            activeTrackColor: NovaColors.accent,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: NovaColors.lineStrong,
            trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
            onChanged: (bool value) => setState(() => _inAppAlerts = value),
          ),
        ],
      ),
    );
  }

  /// `.securityCard`: the security status, the password change and sign out.
  Widget _securityCard(BuildContext context, AppState app, StudentProfile? student) {
    return DashboardCard(
      kicker: context.tr('dash.security'),
      title: context.tr('dash.password_access'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: NovaColors.liveBg, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.check_circle_outline_rounded, size: 19, color: NovaColors.onlineGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('dash.identity_managed_notice'), style: heroLabel(15.5)),
                      const SizedBox(height: 3),
                      Text(context.tr('dash.identity_contact_admin'), style: heroText(14, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PasswordChangeForm(phone: student?.phone ?? ''),
          const SizedBox(height: 14),
          // The root gate returns to sign-in once the session ends.
          CardRowButton(
            label: context.tr('dash.sign_out'),
            color: NovaColors.heartRed,
            onTap: () => app.session.logout(),
          ),
        ],
      ),
    );
  }

  /// D-118 (stores require it): opens the confirmation page.
  Widget _deleteCard(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('deleteAccount.erased'), style: heroText(14)),
          const SizedBox(height: 12),
          CardRowButton(
            label: context.tr('deleteAccount.title'),
            color: NovaColors.heartRed,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
