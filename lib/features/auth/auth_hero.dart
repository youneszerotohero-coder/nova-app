import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../shell/student_top_bar.dart';

/// The head of every auth screen, as on the website's sign-in and register
/// pages: the "Back" pill and the NOVA logo, then the blue eyebrow, the title
/// with its circled word and one line under it, on the page background.
class AuthHero extends StatelessWidget {
  const AuthHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBack = false,
    this.bottom,
  });

  /// `*one word*` is circled by the marker.
  final String title;
  final String subtitle;

  /// Shown under the subtitle — the sign-in / register switch.
  final Widget? bottom;

  /// Register and reset push on top of sign-in, so they get a back
  /// affordance; a required step (password, phone) has none.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 10, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                if (showBack) const BackPill(),
                const Spacer(),
                const NovaLogoBadge(size: 46),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Entrance(child: HeroEyebrow(context.tr('auth.eyebrow'), onBlue: false)),
          const SizedBox(height: 6),
          Entrance(
            delay: const Duration(milliseconds: 60),
            child: HeroTitle(title, onBlue: false, size: 32),
          ),
          const SizedBox(height: 8),
          Entrance(
            delay: const Duration(milliseconds: 120),
            child: Text(subtitle, style: NovaTypography.muted(NovaTypography.textTheme.bodyLarge!)),
          ),
          if (bottom != null) ...[
            const SizedBox(height: 14),
            bottom!,
          ],
        ],
      ),
    );
  }
}

/// The other way in, as the website words it under its form:
/// "New to Nova? **Create an account**" / "Already have an account? **Sign in**".
class AuthModeSwitch extends StatelessWidget {
  const AuthModeSwitch({
    super.key,
    required this.signIn,
    required this.onSwitch,
  });

  /// Which side is the current screen.
  final bool signIn;

  /// Opens the other side.
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onSwitch,
      pressedScale: 0.97,
      semanticLabel: signIn ? context.tr('auth.tabRegister') : context.tr('auth.signIn'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: NovaColors.accentMist,
          borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
        ),
        child: Row(
          children: [
            Icon(signIn ? Icons.person_add_alt_1_rounded : Icons.login_rounded, size: 19, color: NovaColors.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: NovaTypography.textTheme.bodyMedium!.copyWith(color: NovaColors.textStrong),
                  children: [
                    TextSpan(text: '${signIn ? context.tr('auth.newHere') : context.tr('auth.haveAccount')} '),
                    TextSpan(
                      text: signIn ? context.tr('auth.tabRegister') : context.tr('auth.signIn'),
                      style: TextStyle(fontWeight: FontWeight.w800, color: NovaColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
