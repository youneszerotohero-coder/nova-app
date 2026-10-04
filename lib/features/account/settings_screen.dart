import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/appearance_controls.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/state/app_state.dart';
import '../../data/models.dart';
import 'password_change_form.dart';

/// Settings: appearance controls (dark mode + language), the
/// school-managed read-only identity, alerts, the password change by
/// code (D-093) and sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _inAppAlerts = true;

  @override
  Widget build(BuildContext context) {
    final StudentProfile? student = AppScope.of(context).profile;
    return PageScaffold(
      title: context.tr('settings.title'),
      kicker: context.tr('profile.settingsSub'),
      watermark: Icons.settings_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          NovaSectionCard(
            icon: Icons.palette_outlined,
            hue: NovaHue.lilac,
            title: context.tr('settings.appearance'),
            child: const AppearanceControls(),
          ),
          const SizedBox(height: 14),
          NovaSectionCard(
            icon: Icons.school_rounded,
            hue: NovaHue.sky,
            title: context.tr('settings.schoolManaged'),
            subtitle: context.tr('settings.managedNote'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: NovaColors.subtleFill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _row(context, 'settings.fullName', student?.fullName ?? ''),
                  _row(context, 'settings.phone', student?.phone ?? ''),
                  _row(context, 'settings.level', student?.level ?? ''),
                  _row(context, 'settings.track', student?.track ?? ''),
                  _row(context, 'settings.wilaya', student?.wilaya ?? ''),
                  _row(context, 'settings.commune', student?.commune ?? ''),
                  _row(
                    context,
                    'settings.referralCode',
                    student?.referralCode ?? '',
                    last: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          NovaCard(
            child: Row(
              children: [
                const IconTile(
                  icon: Icons.notifications_active_rounded,
                  hue: NovaHue.rose,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('settings.inAppAlerts'),
                        style: NovaTypography.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.tr('settings.alertsSub'),
                        style: NovaTypography.muted(
                          NovaTypography.textTheme.bodySmall!,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _inAppAlerts,
                  activeThumbColor: Colors.white,
                  activeTrackColor: NovaColors.accent,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: NovaColors.textMuted.withValues(
                    alpha: 0.35,
                  ),
                  trackOutlineColor: const WidgetStatePropertyAll<Color>(
                    Colors.transparent,
                  ),
                  onChanged: (bool value) =>
                      setState(() => _inAppAlerts = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          NovaSectionCard(
            icon: Icons.lock_outline_rounded,
            hue: NovaHue.mint,
            title: context.tr('settings.security'),
            child: PasswordChangeForm(phone: student?.phone ?? ''),
          ),
          const SizedBox(height: 24),
          PressableScale(
            // The root gate returns to sign-in once the session ends.
            onTap: () => AppScope.of(context).session.logout(),
            semanticLabel: 'Sign out',
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NovaColors.heartRed.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: NovaColors.heartRed.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: NovaColors.heartRed,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    context.tr('settings.signOut'),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: NovaColors.heartRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'noova.elearning@gmail.com · © 2026 Nova Learning',
              style: NovaTypography.muted(NovaTypography.textTheme.labelSmall!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String labelKey,
    String value, {
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(color: NovaColors.borderOnLight),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.tr(labelKey),
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
          Text(
            value,
            style: NovaTypography.textTheme.bodySmall!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
