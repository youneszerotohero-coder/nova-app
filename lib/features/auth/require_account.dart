import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/account_intent.dart';
import '../../core/state/app_state.dart';
import '../../core/widgets/hero_style.dart';
import 'auth_routes.dart';

export '../../core/state/account_intent.dart';

/// App Store guideline 5.1.1(v) (D-127, D-134): a visitor who chose
/// "continue without an account" browses the catalogue; a feature that
/// needs an account (cart, purchase, joining or opening a Unit, My lessons,
/// Live, notifications, account) opens sign-in over the screen. [intent] is
/// carried out once signed in; back without signing in forgets it.
bool requireAccount(BuildContext context, {AccountIntent? intent}) {
  final AppState app = AppScope.of(context);
  if (app.session.signedIn) return true;
  app.pendingIntent = intent;
  openSignIn(context).then((_) {
    if (!app.session.signedIn) app.pendingIntent = null;
  });
  return false;
}

/// A tab that needs an account, for a visitor: what it holds, then
/// "Sign in" and "Create my account".
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.icon, required this.titleKey, required this.intent});

  final IconData icon;
  final String titleKey;
  final AccountIntent intent;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 140),
          child: HeroEmpty(
            icon: icon,
            title: context.tr(titleKey),
            message: context.tr('guest.message'),
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NovaButton(
                  label: context.tr('gateway.loginCta'),
                  chipIcon: Icons.arrow_forward_rounded,
                  expand: true,
                  onTap: () => requireAccount(context, intent: intent),
                ),
                const SizedBox(height: 10),
                NovaButton(
                  label: context.tr('gateway.registerCta'),
                  variant: NovaButtonVariant.ghost,
                  expand: true,
                  onTap: () {
                    app.pendingIntent = intent;
                    openRegistration(context).then((_) {
                      if (!app.session.signedIn) app.pendingIntent = null;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
