import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../shell/student_top_bar.dart';

/// The head of every auth screen, as on the website's phone sign-in and
/// register pages (`AuthMobileHead` + `.authHeading`): the white bar with the
/// NOVA logo at the start and the "Back" pill at the end, then the blue
/// eyebrow, the title with its circled word and one line under it, on the
/// surface (`.authPanel`).
class AuthHero extends StatelessWidget {
  const AuthHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBack = false,
    this.bottom,
    this.top,
    this.header = true,
  });

  /// `*one word*` is circled by the marker.
  final String title;
  final String subtitle;

  /// Shown under the subtitle.
  final Widget? bottom;

  /// Shown above the eyebrow — the registration steps (`.authSteps`).
  final Widget? top;

  /// Register and reset push on top of sign-in, so they get a back
  /// affordance; a required step (password, phone) has none.
  final bool showBack;

  /// False when the screen places the [AuthHeader] itself (sign-in centres
  /// the form under it).
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header) AuthHeader(showBack: showBack),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (top != null) ...[top!, const SizedBox(height: 24)],
              Entrance(child: HeroEyebrow(context.tr('auth.eyebrow'), onBlue: false)),
              const SizedBox(height: 10),
              Entrance(
                delay: const Duration(milliseconds: 60),
                child: HeroTitle(title, onBlue: false, size: 32),
              ),
              const SizedBox(height: 10),
              Entrance(
                delay: const Duration(milliseconds: 120),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: NovaTypography.body,
                    fontFamilyFallback: NovaTypography.fallback,
                    fontSize: 16,
                    height: 1.6,
                    color: NovaColors.textBody,
                  ),
                ),
              ),
              if (bottom != null) ...[
                const SizedBox(height: 14),
                bottom!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `AuthMobileHead`: the white bar with the logo at the start and the
/// "Back" pill at the end, over a hairline.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 8, 16, 8),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        border: Border(bottom: BorderSide(color: NovaColors.borderOnLight)),
      ),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            const NovaLogoBadge(size: 44),
            const Spacer(),
            if (showBack) const BackPill(),
          ],
        ),
      ),
    );
  }
}

/// The other way in, as the website words it under its form (`.authSwitch`):
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: NovaTypography.body,
              fontFamilyFallback: NovaTypography.fallback,
              fontSize: 16,
              height: 1.5,
              color: NovaColors.textBody,
            ),
            children: [
              TextSpan(text: '${signIn ? context.tr('auth.newHere') : context.tr('auth.haveAccount')} '),
              TextSpan(
                text: signIn ? context.tr('auth.tabRegister') : context.tr('auth.signIn'),
                style: TextStyle(
                  fontFamily: NovaTypography.display,
                  fontFamilyFallback: NovaTypography.fallback,
                  fontWeight: FontWeight.w800,
                  color: NovaColors.accent,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
