import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/security/capture_shield.dart';
import 'core/state/app_state.dart';
import 'core/theme/nova_colors.dart';
import 'core/theme/nova_theme.dart';
import 'core/update/app_update_gate.dart';
import 'core/widgets/notification_banner.dart';
import 'features/account/notifications_screen.dart';
import 'features/shell/app_gate.dart';

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  /// Lets the realtime notification banner, which sits above every
  /// route, open a notification like the list does.
  static final GlobalKey<NavigatorState> _navigator =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.instance;

    return AppScope(
      state: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (BuildContext context, _) {
          // Keep the static palette in phase with the preference on
          // every rebuild so all color reads resolve to active mode.
          NovaColors.current =
              state.darkMode ? NovaPalette.dark : NovaPalette.light;
          return MaterialApp(
            title: 'NOVA',
            navigatorKey: _navigator,
            debugShowCheckedModeBanner: false,
            theme: NovaTheme.current,
            themeMode: ThemeMode.light,
            locale: state.lang.locale,
            supportedLocales: const [
              Locale('en'),
              Locale('fr'),
              Locale('ar'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // Above every route, so no screen escapes the capture blur;
            // new notifications show over any screen.
            builder: (BuildContext context, Widget? child) => CaptureShield(
              child: AppUpdateGate(
                navigatorKey: _navigator,
                // Store checks only in the real app, not offline previews.
                enabled: state.api != null,
                child: NotificationBannerHost(
                  arrivals: state.account.arrivals,
                  onOpen: (notification) {
                    final NavigatorState? navigator = _navigator.currentState;
                    if (navigator != null) {
                      openNotification(state, navigator, notification);
                    }
                  },
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
            home: const AppGate(),
          );
        },
      ),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Public catalogue and the stored session load while the splash shows.
  AppState.instance.boot();
  runApp(const NovaApp());
}
