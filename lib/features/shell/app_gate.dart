import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/push/push_host.dart';
import '../../core/state/app_state.dart';
import '../../core/widgets/hero_style.dart';
import '../../data/session_store.dart';
import '../auth/auth_gateway_screen.dart';
import '../auth/change_password_screen.dart';
import '../auth/phone_step_screen.dart';
import '../auth/register_screen.dart';
import '../auth/school_year_screen.dart';
import '../teacher/teacher_shell.dart';
import 'shell_screen.dart';
import 'splash_screen.dart';

/// Root route: shows what the session allows. Signing out, a replaced
/// session or a finished onboarding step swap the root and drop every
/// pushed route, so no screen of the previous state survives.
///
/// D-133: the launch animation plays once while the stored session loads; a
/// Student still signed in goes straight to their space, anyone else to the
/// "I have an account / I'm new" gateway. D-134: the gateway's "continue
/// without an account" opens the Student space read-only for a visitor.
/// D-143: a Teacher changes their temporary password first, then reaches the
/// Teacher shell; tapped system notifications open over either space.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  Object? _lastKey;

  /// The launch animation has been seen once (offline previews skip it).
  bool? _introDone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_introDone != null) return;
    _introDone = AppScope.of(context).api == null;
    if (!_introDone!) {
      Future<void>.delayed(NovaSplash.minimum, () {
        if (mounted) setState(() => _introDone = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final SessionStore session = app.session;
    final bool splash = session.status == SessionStatus.booting || _introDone != true;
    final Object key = splash ? 'splash' : (session.status, session.nextRequiredStep, app.guest);
    if (_lastKey != null && _lastKey != key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      });
    }
    _lastKey = key;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      child: KeyedSubtree(
        key: ValueKey<Object>(key),
        child: splash
            ? const NovaSplash()
            : switch (session.status) {
                SessionStatus.booting => const NovaSplash(),
                SessionStatus.offline => const _Offline(),
                // D-134: "continue without an account" browses read-only.
                SessionStatus.signedOut => app.guest ? const ShellScreen() : const AuthGatewayScreen(),
                SessionStatus.signedIn => switch (session.nextRequiredStep) {
                    'password_change' => const ChangePasswordScreen(),
                    // D-143: no Student step applies to a Teacher.
                    _ when session.isTeacher => const PushHost(child: TeacherShell()),
                    // D-079: an account without a valid mobile, before onboarding.
                    'phone' => const PhoneStepScreen(),
                    'onboarding' => const RegisterScreen(onboarding: true),
                    // D-098: a new school year, level and filière confirmed first.
                    'school_year' => const SchoolYearScreen(),
                    _ => const PushHost(child: ShellScreen()),
                  },
              },
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
        child: Center(
          child: HeroEmpty(
            icon: Icons.wifi_off_rounded,
            title: context.tr('err.network'),
            boxed: false,
            action: NovaButton(
              label: context.tr('common.retry'),
              icon: Icons.refresh_rounded,
              onTap: () => AppScope.of(context).boot(),
            ),
          ),
        ),
      ),
    );
  }
}
