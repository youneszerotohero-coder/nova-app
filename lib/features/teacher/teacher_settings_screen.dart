import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/push/push_platform.dart';
import '../../core/push/push_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/widgets/appearance_controls.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../data/session_store.dart';
import '../account/dashboard_card.dart';
import '../shell/student_top_bar.dart';
import 'teacher_top_bar.dart';

/// The Teacher's settings (D-143), in the Student settings' cards: the
/// profile the Admin manages (read-only), the phone's notifications (status
/// and "Enable"), appearance (theme and language) and sign out.
class TeacherSettingsScreen extends StatelessWidget {
  const TeacherSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final bool tab = ShellNav.maybeOf(context) != null;
    final List<Widget> cards = <Widget>[
      _profileCard(context, app),
      _PushCard(push: app.push),
      DashboardCard(title: context.tr('settings.appearance'), child: const AppearanceControls()),
      _signOutCard(context, app),
    ];
    return Scaffold(
      backgroundColor: NovaColors.paper,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: tab ? 130 : 40 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NovaPageHeader(
              kicker: context.tr('teacher.space'),
              title: context.tr('settings.title'),
              lead: context.tr('teacher.settingsLead'),
            ),
            const SizedBox(height: 20),
            for (int i = 0; i < cards.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                child: Entrance(delay: Duration(milliseconds: 50 * i), child: cards[i]),
              ),
            Center(
              child: Text(
                'noova.elearning@gmail.com · © 2026 Nova Learning',
                style: heroText(12.5, color: NovaColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext context, AppState app) {
    final TeacherIdentity? teacher = app.session.teacher;
    final String name = teacher?.fullName ?? app.profile?.fullName ?? '';
    return DashboardCard(
      kicker: context.tr('teacher.profileKicker'),
      title: context.tr('teacher.profileTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                TeacherAvatar(name: name, photoUrl: teacher?.photoUrl, size: 54),
                const SizedBox(width: 12),
                Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: heroLabel(17))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(10)),
                  child: Text(context.tr('teacher.role'), style: heroLabel(13, color: NovaColors.yellowInk)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InfoField(label: context.tr('dash.full_name'), value: name),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            // A phone number reads left to right in Arabic too.
            child: InfoField(label: context.tr('dash.phone'), value: app.profile?.phone ?? '', ltr: true),
          ),
          Text(context.tr('teacher.profileManaged'), style: heroText(13.5, color: NovaColors.textMuted, height: 1.45)),
        ],
      ),
    );
  }

  Widget _signOutCard(BuildContext context, AppState app) {
    return DashboardCard(
      kicker: context.tr('dash.security'),
      title: context.tr('teacher.signOutTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('teacher.signOutSub'), style: heroText(14)),
          const SizedBox(height: 12),
          // The root gate returns to the first screen once the session ends.
          CardRowButton(
            label: context.tr('dash.sign_out'),
            color: NovaColors.heartRed,
            onTap: () => app.session.logout(),
          ),
        ],
      ),
    );
  }
}

/// The phone's notification permission with its "Enable" action.
class _PushCard extends StatelessWidget {
  const _PushCard({required this.push});

  final PushService? push;

  @override
  Widget build(BuildContext context) {
    final PushService? push = this.push;
    if (push == null) return _body(context, null);
    return ListenableBuilder(listenable: push, builder: (BuildContext context, _) => _body(context, push));
  }

  Widget _body(BuildContext context, PushService? push) {
    final bool available = push?.available ?? false;
    final PushPermission permission = push?.permission ?? PushPermission.unknown;
    final bool on = available && permission == PushPermission.granted;
    final String status = !available
        ? 'push.statusUnavailable'
        : switch (permission) {
            PushPermission.granted => 'push.statusOn',
            PushPermission.blocked => 'push.statusBlocked',
            _ => 'push.statusOff',
          };
    return DashboardCard(
      kicker: context.tr('dash.notifications'),
      title: context.tr('teacher.pushTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: on ? NovaColors.liveBg : NovaColors.accentMist,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                  size: 20,
                  color: on ? NovaColors.onlineGreen : NovaColors.accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(child: Text(context.tr(status), style: heroText(14, height: 1.45))),
            ],
          ),
          if (available && !on) ...[
            const SizedBox(height: 14),
            CardRowButton(
              label: context.tr(permission == PushPermission.blocked ? 'push.openSettings' : 'push.enable'),
              color: NovaColors.accent,
              onTap: () => push!.enable(),
            ),
          ],
        ],
      ),
    );
  }
}
