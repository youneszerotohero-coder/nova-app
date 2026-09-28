import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/nova_decor.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/pressable_scale.dart';

/// The brand block every auth screen opens on: gradient, stickers,
/// the wordmark and the headline for this step.
class AuthHero extends StatelessWidget {
  const AuthHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBack = false,
    this.bottom,
  });

  final String title;
  final String subtitle;

  /// Shown under the subtitle — the sign-in / register switch.
  final Widget? bottom;

  /// Register and reset push on top of sign-in, so they get a back
  /// affordance; sign-in itself is the root.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.paddingOf(context).top + 18,
        24,
        30,
      ),
      decoration: BoxDecoration(
        gradient: NovaPageHeader.gradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(NovaDimens.radiusCardLarge),
        ),
        boxShadow: NovaHue.sky.shadow,
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: NovaDecor(color: Colors.white, opacity: 0.26, seed: 1),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (showBack) ...[
                    FrostedIconButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                      size: 40,
                    ),
                    const SizedBox(width: 14),
                  ],
                  Text(
                    'nova',
                    style:
                        NovaTypography.textTheme.displaySmall!.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Sparkle(size: 11),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                title,
                style: NovaTypography.textTheme.displayMedium!.copyWith(
                  color: Colors.white,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: NovaTypography.textTheme.bodyMedium!.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              if (bottom != null) ...[
                const SizedBox(height: 22),
                bottom!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The two ways in, side by side at the top of the sign-in and register
/// screens, so a new Student sees "Create account" without scrolling.
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
    return Container(
      height: 54,
      padding: const EdgeInsets.all(4),
      // A dark track keeps the white label readable over the header's
      // sparkles.
      decoration: BoxDecoration(
        color: const Color(0x590A1128),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              label: context.tr('auth.signIn'),
              icon: Icons.login_rounded,
              active: signIn,
              onTap: signIn ? null : onSwitch,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeTab(
              label: context.tr('auth.tabRegister'),
              icon: Icons.person_add_alt_1_rounded,
              active: !signIn,
              onTap: signIn ? onSwitch : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color ink = active ? NovaColors.accentDeep : Colors.white;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.96,
      semanticLabel: label,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
