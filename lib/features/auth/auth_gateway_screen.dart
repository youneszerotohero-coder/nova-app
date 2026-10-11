import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../shell/student_top_bar.dart';
import 'auth_routes.dart';

/// D-133: the app has no public pages. Signed out, it opens on the website's
/// `/start` question — "I already have an account" or "I'm new here" — with
/// the same wording, then sign-in or registration.
class AuthGatewayScreen extends StatelessWidget {
  const AuthGatewayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroBand(
            radius: const BorderRadius.vertical(bottom: Radius.circular(NovaDimens.radiusHero)),
            padding: EdgeInsets.fromLTRB(18, MediaQuery.paddingOf(context).top + 12, 18, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    _LanguageChips(),
                    Spacer(),
                    NovaLogoBadge(size: 48),
                  ],
                ),
                const SizedBox(height: 26),
                Entrance(child: HeroEyebrow(context.tr('gateway.eyebrow'))),
                const SizedBox(height: 8),
                Entrance(
                  delay: const Duration(milliseconds: 60),
                  child: HeroTitle(context.tr('gateway.title'), size: 33),
                ),
                const SizedBox(height: 8),
                Entrance(
                  delay: const Duration(milliseconds: 120),
                  child: Text(
                    context.tr('gateway.subtitle'),
                    style: NovaTypography.textTheme.bodyLarge!.copyWith(color: Colors.white.withValues(alpha: 0.88)),
                  ),
                ),
                const SizedBox(height: 22),
                Entrance(
                  delay: const Duration(milliseconds: 180),
                  child: _Choice(
                    icon: Icons.how_to_reg_rounded,
                    iconBackground: NovaColors.yellow,
                    iconColor: NovaColors.yellowInk,
                    tag: context.tr('gateway.loginTag'),
                    text: context.tr('gateway.loginText'),
                    button: NovaButton(
                      label: context.tr('gateway.loginCta'),
                      chipIcon: Icons.arrow_forward_rounded,
                      expand: true,
                      onTap: () => openSignIn(context),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Entrance(
                  delay: const Duration(milliseconds: 260),
                  child: _Choice(
                    icon: Icons.person_add_alt_1_rounded,
                    iconBackground: NovaColors.accentMist,
                    iconColor: NovaColors.accent,
                    tag: context.tr('gateway.registerTag'),
                    text: context.tr('gateway.registerText'),
                    button: NovaButton(
                      label: context.tr('gateway.registerCta'),
                      variant: NovaButtonVariant.ghost,
                      chipIcon: Icons.arrow_forward_rounded,
                      expand: true,
                      onTap: () => openRegistration(context),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Entrance(
                  delay: const Duration(milliseconds: 340),
                  child: _PostIt(text: context.tr('gateway.hint')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.tag,
    required this.text,
    required this.button,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String tag;
  final String text;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        boxShadow: const [BoxShadow(offset: Offset(0, 22), blurRadius: 40, spreadRadius: -22, color: Color(0x8C071649))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(tag, style: NovaTypography.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(text, style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!)),
          const SizedBox(height: 16),
          button,
        ],
      ),
    );
  }
}

/// `.hxNote`: the yellow post-it with its strip of tape, slightly tilted.
class _PostIt extends StatelessWidget {
  const _PostIt({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -1.5 * math.pi / 180,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: const BoxDecoration(
              color: NovaColors.postIt,
              boxShadow: [BoxShadow(offset: Offset(0, 16), blurRadius: 30, spreadRadius: -14, color: Color(0x66071649))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFF4A3B0A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontFamily: NovaTypography.display,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      height: 1.4,
                      color: Color(0xFF4A3B0A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -8,
            child: Transform.rotate(
              angle: 3 * math.pi / 180,
              child: Container(width: 64, height: 20, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

/// AR / FR / EN, the website's floating language switch, on the band.
class _LanguageChips extends StatelessWidget {
  const _LanguageChips();

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    const Map<NovaLang, String> labels = <NovaLang, String>{NovaLang.ar: 'ع', NovaLang.fr: 'FR', NovaLang.en: 'EN'};
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry<NovaLang, String> entry in labels.entries)
            PressableScale(
              onTap: () => app.setLang(entry.key),
              semanticLabel: entry.key.label,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 40,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: app.lang == entry.key ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontFamily: NovaTypography.display,
                    fontFamilyFallback: NovaTypography.fallback,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: app.lang == entry.key ? NovaColors.accent : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
