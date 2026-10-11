import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/main.dart';

import 'fixtures/fixture_app.dart';

import 'nova_font_loader.dart';

/// Generates design-snapshot goldens of the Student home (D-133) at a phone
/// viewport, then the menu, Explore and its filters reached from it. Run with:
///   flutter test --update-goldens
void main() {
  setUpAll(loadNovaFonts);
  setUp(installFixtureApp);

  goldenTestWidgets('home page design snapshots', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NovaApp());
    // The live-now pulse loops: frames, not settle.
    await pumpFrames(tester);
    await settleImages(tester, looping: true);

    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/home_top.png'),
    );

    // Swipe up like a user to reveal the Units and Offers rails.
    await tester.dragFrom(const Offset(195, 600), const Offset(0, -760));
    await settleImages(tester, looping: true);
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/home_bottom.png'),
    );

    // Back to the top: the top bar owns the menu trigger.
    await tester.dragFrom(const Offset(195, 600), const Offset(0, 1200));
    await pumpFrames(tester);

    await tester.tap(find.bySemanticsLabel('Menu'));
    await pumpFrames(tester);
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/menu_open.png'),
    );

    await tester.tap(find.bySemanticsLabel('Close'));
    await pumpFrames(tester);

    // Search and filtering live on Explore, opened from "See the Offers".
    await tester.tap(find.text('See the Offers'));
    await settleImages(tester, looping: true);
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/explore_top.png'),
    );

    await tester.tap(find.bySemanticsLabel('Filters'));
    await pumpFrames(tester);
    await expectLater(
      find.byType(NovaApp),
      matchesGoldenFile('goldens/filter_sheet.png'),
    );
  });
}
