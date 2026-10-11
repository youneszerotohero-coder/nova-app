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

/// D-133: signed out, the app opens on the website's `/start` question —
/// "I already have an account" or "I'm new here" — with the same wording,
/// then sign-in or registration. D-134: a third choice, "continue without an
/// account", opens the catalogue read-only (App Store 5.1.1(v)).
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
                // `.gatewayHeading`: centred, as on the website.
                Entrance(child: Center(child: HeroEyebrow(context.tr('gateway.eyebrow')))),
                const SizedBox(height: 12),
                Entrance(
                  delay: const Duration(milliseconds: 60),
                  child: HeroTitle(context.tr('gateway.title'), size: 32, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 12),
                Entrance(
                  delay: const Duration(milliseconds: 120),
                  child: Text(
                    context.tr('gateway.subtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: NovaTypography.body,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontSize: 17,
                      height: 1.6,
                      color: Color(0xDBFFFFFF),
                    ),
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
                    button: _ChoiceCta(label: context.tr('gateway.loginCta'), onTap: () => openSignIn(context)),
                  ),
                ),
                const SizedBox(height: 14),
                Entrance(
                  delay: const Duration(milliseconds: 260),
                  child: _Choice(
                    icon: Icons.person_add_alt_1_rounded,
                    iconBackground: const Color(0xFFE9F0FF),
                    iconColor: NovaColors.blue,
                    tag: context.tr('gateway.registerTag'),
                    text: context.tr('gateway.registerText'),
                    button: _ChoiceCta(label: context.tr('gateway.registerCta'), ghost: true, onTap: () => openRegistration(context)),
                  ),
                ),
                const SizedBox(height: 14),
                // D-134 (App Store 5.1.1(v)): browsing needs no account.
                Entrance(
                  delay: const Duration(milliseconds: 340),
                  child: _GuestChoice(onTap: () => AppScope.of(context).browseAsGuest(true)),
                ),
                const SizedBox(height: 22),
                Entrance(
                  delay: const Duration(milliseconds: 420),
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

/// `.gatewayChoice`: a white card (white in dark mode too), its tilted icon
/// tile, the answer, one line and the way in.
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        boxShadow: const [BoxShadow(offset: Offset(0, 30), blurRadius: 60, spreadRadius: -34, color: Color(0xBF061450))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.rotate(
            angle: -6 * math.pi / 180,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(offset: Offset(0, 10), blurRadius: 18, spreadRadius: -12, color: Color(0x800A0E16))],
              ),
              child: Icon(icon, size: 21, color: iconColor),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tag,
            style: const TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 19,
              height: 1.25,
              color: NovaColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              fontFamily: NovaTypography.body,
              fontFamilyFallback: NovaTypography.fallback,
              fontSize: 15.5,
              height: 1.5,
              color: Color(0xFF46506A),
            ),
          ),
          const SizedBox(height: 12),
          button,
        ],
      ),
    );
  }
}

/// `.gatewayChoiceCta`: the blue way in (or the outlined one), the label
/// and its arrow.
class _ChoiceCta extends StatelessWidget {
  const _ChoiceCta({required this.label, required this.onTap, this.ghost = false});

  final String label;
  final VoidCallback onTap;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final Color ink = ghost ? NovaColors.ink : Colors.white;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ghost ? Colors.transparent : NovaColors.blue,
          borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
          border: ghost ? Border.all(color: const Color(0x2E121A33), width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: NovaTypography.display,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: ink,
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.arrow_forward_rounded, size: 18, color: ink),
          ],
        ),
      ),
    );
  }
}

/// The visitor's way in: a glass card on the band whose compass swings
/// while a yellow ring pulses out of it, three times, then rests.
class _GuestChoice extends StatefulWidget {
  const _GuestChoice({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_GuestChoice> createState() => _GuestChoiceState();
}

class _GuestChoiceState extends State<_GuestChoice> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating && _loop.value == 0) {
      // Three turns to catch the eye, then it rests.
      _loop.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: AnimatedBuilder(
              animation: _loop,
              builder: (BuildContext context, Widget? child) {
                final double t = _loop.value;
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: 1 + 0.45 * t,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: NovaColors.yellow.withValues(alpha: 0.9 * (1 - t)), width: 2),
                        ),
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                      child: Transform.rotate(
                        angle: math.sin(t * 2 * math.pi) * 0.35,
                        child: child,
                      ),
                    ),
                  ],
                );
              },
              child: Icon(Icons.explore_rounded, size: 26, color: NovaColors.accent),
            ),
          ),
          const SizedBox(height: 12),
          Text(context.tr('gateway.guestTag'), style: NovaTypography.textTheme.headlineSmall!.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            context.tr('gateway.guestText'),
            style: NovaTypography.textTheme.bodyMedium!.copyWith(color: Colors.white.withValues(alpha: 0.86)),
          ),
          const SizedBox(height: 16),
          NovaButton(
            label: context.tr('gateway.guestCta'),
            variant: NovaButtonVariant.onBlueGhost,
            chipIcon: Icons.arrow_forward_rounded,
            expand: true,
            onTap: widget.onTap,
          ),
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
