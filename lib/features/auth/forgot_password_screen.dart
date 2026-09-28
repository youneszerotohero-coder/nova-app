import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/nova_colors.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';

/// Forgot password — informational only: resets are school-managed.
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: context.tr('auth.resetTitle'),
      kicker: context.tr('auth.contactSchool'),
      watermark: Icons.support_agent_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          Text(
            context.tr('auth.resetBody'),
            style: NovaTypography.textTheme.bodyMedium!.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          NovaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int n = 1; n <= 4; n++)
                  _step('$n', context.tr('auth.resetStep$n')),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PressableScale(
            onTap: () => _emailSchool(context),
            semanticLabel: context.tr('auth.emailUs'),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NovaColors.ink950,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                context.tr('auth.emailUs'),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: NovaColors.textOnDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const String _schoolEmail = 'noova.elearning@gmail.com';

  /// Opens the phone's mail app; without one, the address is shown.
  Future<void> _emailSchool(BuildContext context) async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'mailto', path: _schoolEmail));
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      novaToast(context, context.tr('auth.noMailApp'),
          icon: Icons.mail_outline_rounded);
    }
  }

  Widget _step(String number, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: NovaHue.lilac.gradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(label, style: NovaTypography.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
