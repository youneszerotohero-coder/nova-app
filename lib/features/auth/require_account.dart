import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/pressable_scale.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// App Store guideline 5.1.1(v) (D-127): browsing needs no account. A
/// feature that does (cart, purchase, my Units, profile, notifications)
/// asks to sign in first; once signed in, the root gate shows the app.
///
/// [purchase] is remembered: once signed in, the item is put in the cart and
/// the cart opens (the purchase goes on). Back without signing in forgets it.
bool requireAccount(BuildContext context, {({String kind, int id})? purchase}) {
  final AppState app = AppScope.of(context);
  if (app.session.signedIn) return true;
  app.pendingPurchase = purchase;
  openSignIn(context).then((_) {
    if (!app.session.signedIn) app.pendingPurchase = null;
  });
  return false;
}

/// Sign-in over the screen the visitor was browsing.
Future<void> openSignIn(BuildContext context, {String? phone}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LoginScreen(showBack: true, initialPhone: phone)),
  );
}

/// Account creation; a number that already has an account comes back to
/// sign-in with that number.
Future<void> openRegistration(BuildContext context) async {
  final String? phone = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(builder: (_) => const RegisterScreen()),
  );
  if (phone != null && context.mounted) await openSignIn(context, phone: phone);
}

/// A tab that needs an account, for a visitor: what it holds, then
/// "Sign in" and "Create an account".
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.icon, required this.titleKey});

  final IconData icon;
  final String titleKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 140),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: NovaColors.accentMist, shape: BoxShape.circle),
                child: Icon(icon, size: 34, color: NovaColors.accentDeep),
              ),
              const SizedBox(height: 20),
              Text(
                context.tr(titleKey),
                textAlign: TextAlign.center,
                style: NovaTypography.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('guest.message'),
                textAlign: TextAlign.center,
                style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
              ),
              const SizedBox(height: 26),
              _Button(
                label: context.tr('auth.signIn'),
                filled: true,
                onTap: () => openSignIn(context),
              ),
              const SizedBox(height: 12),
              _Button(
                label: context.tr('auth.createAccount'),
                filled: false,
                onTap: () => openRegistration(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.filled, required this.onTap});

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: label,
      child: Container(
        height: 54,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? NovaColors.ink950 : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: filled ? null : Border.all(color: NovaColors.ink950.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: filled ? NovaColors.textOnDark : NovaColors.ink950,
          ),
        ),
      ),
    );
  }
}
