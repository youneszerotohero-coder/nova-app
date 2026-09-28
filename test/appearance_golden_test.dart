import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/features/account/settings_screen.dart';
import 'package:nova_mobile/main.dart';

import 'fixtures/fixture_app.dart';

import 'nova_font_loader.dart';

/// Verifies the dark palette and Arabic RTL rendering end to end.
/// Restores the default light/English preferences afterwards.
void main() {
  setUpAll(loadNovaFonts);
  setUp(installFixtureApp);

  testWidgets('home renders in dark mode with Arabic RTL', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final AppState state = AppState.instance;
    state.setDarkMode(true);
    state.setLang(NovaLang.ar);

    await tester.pumpWidget(const NovaApp());
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/home_dark_ar.png'),
    );

    // Restore defaults so the singleton state doesn't leak into other
    // tests in the same run.
    state.setLang(NovaLang.en);
    state.setDarkMode(false);
  });

  testWidgets('settings screen in dark mode snapshot', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final AppState state = AppState.instance;
    state.setDarkMode(true);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: NovaTheme.current,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_dark.png'),
    );

    state.setDarkMode(false);
  });
}
