import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Baloo Bhaijaan 2 / Geist faces so goldens render the
/// real typography, plus the Material icon font so glyphs appear as
/// icons instead of tofu boxes. Shared by the design-snapshot tests.
Future<void> loadNovaFonts() async {
  const Map<String, List<String>> families = {
    'BalooBhaijaan2': [
      'assets/fonts/BalooBhaijaan2-400.ttf',
      'assets/fonts/BalooBhaijaan2-500.ttf',
      'assets/fonts/BalooBhaijaan2-600.ttf',
      'assets/fonts/BalooBhaijaan2-700.ttf',
      'assets/fonts/BalooBhaijaan2-800.ttf',
    ],
    'Geist': [
      'assets/fonts/Geist-400.ttf',
      'assets/fonts/Geist-500.ttf',
      'assets/fonts/Geist-600.ttf',
      'assets/fonts/Geist-700.ttf',
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
///
/// [looping]: the screen has an animation that never ends (the Student
/// home's live-now pulse), so it cannot "settle": two seconds of frames
/// are pumped instead, which keeps the snapshot deterministic.
Future<void> settleImages(WidgetTester tester, {bool looping = false}) async {
  await tester.runAsync(() async {
    for (final Element element in find.byType(Image).evaluate()) {
      final Image image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  if (looping) {
    await pumpFrames(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

/// Pumps [duration] of frames, 100 ms apart, for screens with a looping
/// animation where `pumpAndSettle` would time out.
Future<void> pumpFrames(WidgetTester tester, [Duration duration = const Duration(seconds: 2)]) async {
  for (int i = 0; i < duration.inMilliseconds ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The day every picture shows: the home band prints today's date, so a
/// golden taken on another day would differ by that one line.
final DateTime goldenDay = DateTime.utc(2026, 10, 11, 9);

/// [testWidgets] on the fixed [goldenDay].
void goldenTestWidgets(String description, WidgetTesterCallback callback) => testWidgets(
      description,
      (WidgetTester tester) => withClock(Clock.fixed(goldenDay), () => callback(tester)),
    );
