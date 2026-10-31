import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/desktop/desktop_layout.dart';
import 'core/desktop/desktop_navigation.dart';
import 'core/desktop/desktop_scroll.dart';
import 'core/security/capture_shield.dart';
import 'core/state/app_state.dart';
import 'core/theme/nova_colors.dart';
import 'core/theme/nova_theme.dart';
import 'core/update/app_update_gate.dart';
import 'core/widgets/notification_banner.dart';
import 'features/account/notifications_screen.dart';
import 'features/messages/chat_notice_host.dart';
import 'features/shell/app_gate.dart';

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  /// Lets the realtime notification banner, which sits above every
  /// route, open a notification like the list does.
  static final GlobalKey<NavigatorState> _navigator =
      GlobalKey<NavigatorState>();

  /// D-188: the PC app's Esc / mouse back button needs the route stack.
  static final DesktopRouteObserver _routes = DesktopRouteObserver();

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
            navigatorObservers: <NavigatorObserver>[_routes],
            debugShowCheckedModeBanner: false,
            // Phones: Flutter's; the PC app: mouse drag, no bounce (D-188).
            scrollBehavior: const NovaScrollBehavior(),
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
              child: DesktopBackKeys(
                navigatorKey: _navigator,
                observer: _routes,
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
                    // D-143: chat messages for another room, above every screen.
                    child: ChatNoticeHost(
                      navigatorKey: _navigator,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
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
  // D-188: smooth mouse-wheel scrolling in the PC app (nothing on phones),
  // and a larger decoded-image cache so pages come back without re-decoding.
  DesktopWheelSmoother.install();
  if (isDesktopApp) PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  // Public catalogue and the stored session load while the splash shows.
  AppState.instance.boot();
  runApp(const NovaApp());
}
