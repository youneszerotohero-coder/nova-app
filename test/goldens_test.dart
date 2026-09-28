import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/main.dart';

import 'fixtures/fixture_app.dart';

import 'nova_font_loader.dart';

/// Generates design-snapshot goldens of the home page at a phone
/// viewport. Run with:
///   flutter test --update-goldens
void main() {
  setUpAll(loadNovaFonts);
  setUp(installFixtureApp);

  testWidgets('home page design snapshots', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NovaApp());
    await tester.pumpAndSettle();
    await settleImages(tester);

    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/home_top.png'),
    );

    // Swipe up like a user to reveal the courses and teachers rails.
    await tester.dragFrom(const Offset(195, 600), const Offset(0, -760));
    await tester.pumpAndSettle();
    await settleImages(tester);
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/home_bottom.png'),
    );

    // Back to the top: the header owns the menu trigger.
    await tester.dragFrom(const Offset(195, 600), const Offset(0, 1200));
    await tester.pumpAndSettle();

    // Open the menu and the filter sheet for design snapshots.
    await tester.tap(find.bySemanticsLabel('Menu'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/menu_open.png'),
    );

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    // Search and filtering live on Explore.
    await tester.tap(find.bySemanticsLabel('Explore'));
    await tester.pumpAndSettle();
    await settleImages(tester);
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/explore_top.png'),
    );

    await tester.tap(find.bySemanticsLabel('Filters'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/filter_sheet.png'),
    );
  });
}
