import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/session_store.dart';
import '../auth/change_password_screen.dart';
import '../auth/login_screen.dart';
import '../auth/phone_step_screen.dart';
import '../auth/register_screen.dart';
import '../auth/school_year_screen.dart';
import 'shell_screen.dart';

/// Root route: shows what the session allows. Signing out, a replaced
/// session or a finished onboarding step swap the root and drop every
/// pushed route, so no screen of the previous state survives.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  Object? _lastKey;

  @override
  Widget build(BuildContext context) {
    final SessionStore session = AppScope.of(context).session;
    final Object key = (session.status, session.nextRequiredStep);
    if (_lastKey != null && _lastKey != key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      });
    }
    _lastKey = key;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: KeyedSubtree(
        key: ValueKey<Object>(key),
        child: switch (session.status) {
          SessionStatus.booting => const _Splash(),
          SessionStatus.offline => const _Offline(),
          SessionStatus.signedOut => const LoginScreen(),
          SessionStatus.signedIn => switch (session.nextRequiredStep) {
              'password_change' => const ChangePasswordScreen(),
              // D-079: an account without a valid mobile, before onboarding.
              'phone' => const PhoneStepScreen(),
              'onboarding' => const RegisterScreen(onboarding: true),
              // D-098: a new school year, level and filière confirmed first.
              'school_year' => const SchoolYearScreen(),
              _ => const ShellScreen(),
            },
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    // The website's NOVA logo on white, continuing the native launch
    // screen without a flash.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/brand/nova_logo.png',
              width: 168,
              semanticLabel: 'NOVA',
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: NovaColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: NovaColors.textMuted),
              const SizedBox(height: 18),
              Text(
                context.tr('err.network'),
                textAlign: TextAlign.center,
                style: NovaTypography.textTheme.titleMedium,
              ),
              const SizedBox(height: 22),
              PressableScale(
                onTap: () => AppScope.of(context).boot(),
                semanticLabel: 'Retry',
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NovaColors.ink950,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    context.tr('common.retry'),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: NovaColors.textOnDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
