import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Inter/InterDisplay faces so goldens render the
/// real typography, plus the Material icon font so glyphs appear as
/// icons instead of tofu boxes. Shared by the design-snapshot tests.
Future<void> loadNovaFonts() async {
  const Map<String, List<String>> families = {
    'Inter': [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/Inter-Bold.ttf',
    ],
    'InterDisplay': [
      'assets/fonts/InterDisplay-SemiBold.ttf',
      'assets/fonts/InterDisplay-Bold.ttf',
    ],
    'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
  };

  for (final MapEntry<String, List<String>> family in families.entries) {
    final FontLoader loader = FontLoader(family.key);
    bool any = false;
    for (final String path in family.value) {
      try {
        final ByteData data = await rootBundle.load(path);
        loader.addFont(Future<ByteData>.value(data));
        any = true;
      } catch (_) {
        // The icon font is shipped by the framework rather than by the
        // app, so a missing entry only costs us glyphs in snapshots.
      }
    }
    if (any) await loader.load();
  }
}

/// Decodes every on-screen `Image` for real, so snapshots show the
/// posters and portraits. Image codecs run outside the test's fake
/// clock, hence `runAsync`; call after each pump that reveals images.
Future<void> settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final Element element in find.byType(Image).evaluate()) {
      final Image image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pumpAndSettle();
}
