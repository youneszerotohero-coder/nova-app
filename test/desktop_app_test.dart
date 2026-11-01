import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/desktop/desktop_layout.dart';
import 'package:nova_mobile/core/desktop/desktop_navigation.dart';
import 'package:nova_mobile/core/desktop/desktop_scroll.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/utils/player_fullscreen.dart';
import 'package:nova_mobile/core/widgets/hero_style.dart';
import 'package:nova_mobile/core/widgets/motion.dart';
import 'package:nova_mobile/core/widgets/nova_bottom_bar.dart';
import 'package:nova_mobile/core/widgets/nova_side_rail.dart';
import 'package:nova_mobile/core/widgets/pressable_scale.dart';
import 'package:nova_mobile/features/account/dashboard_card.dart';
import 'package:nova_mobile/features/catalog/offers_catalog_screen.dart';
import 'package:nova_mobile/features/catalog/units_catalog_screen.dart';
import 'package:nova_mobile/features/home/home_screen.dart';
import 'package:nova_mobile/features/home/widgets/nova_product_card.dart';
import 'package:nova_mobile/features/learning/lives_screen.dart';
import 'package:nova_mobile/features/learning/my_learning_screen.dart';
import 'package:nova_mobile/main.dart';

import 'fixtures/fixture_app.dart';
import 'nova_font_loader.dart';

/// D-188 (amends D-164): the PC app is the phone app with a desktop UX —
/// a sidebar, a centred content column, card grids, short page fades, Esc to
/// go back, smooth wheel scrolling — and a black window in captures. Phones
/// keep their layout (the other test files run as Android).
void main() {
  setUpAll(loadNovaFonts);
  setUp(installFixtureApp);

  /// Two seconds of frames: the home's live-now pulse loops, so the app
  /// never "settles" while it shows.
  Future<void> frames(WidgetTester tester, {int count = 20}) async {
    for (int i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NovaApp());
    await frames(tester);
  }

  /// Runs [body] as the PC app; the override is reset inside the test, as
  /// the framework checks it before tear-downs.
  Future<void> asPcApp(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Finder inRail(Finder finder) => find.descendant(of: find.byType(NovaSideRail), matching: finder);
  Finder shown(Type screen) => find.byType(screen).hitTestable();

  group('desktop shell', () {
    testWidgets('a 1440×900 PC window has the sidebar, a centred column and card grids', (tester) => asPcApp(() async {
          await pumpApp(tester, const Size(1440, 900));

          expect(find.byType(NovaSideRail), findsOneWidget);
          expect(find.byType(NovaBottomBar), findsNothing);
          for (final String label in <String>['Home', 'My lessons', 'Live', 'Cart', 'Account']) {
            expect(inRail(find.text(label)), findsOneWidget, reason: label);
          }
          // Compact desktop icons, not the phone's.
          for (final Icon icon in tester.widgetList<Icon>(inRail(find.byType(Icon)))) {
            expect(icon.size, lessThanOrEqualTo(22));
          }
          // D-193: drawn at the desktop scale.
          final Rect rail = tester.getRect(find.byType(NovaSideRail));
          expect(rail.width, closeTo(DesktopMetrics.railWidth * DesktopMetrics.uiScale, 0.01));
          expect(rail.left, 0);
          // D-193: the menu lives in the sidebar (catalogue shortcuts), so
          // the top bar has no menu button.
          expect(inRail(find.text('All courses')), findsOneWidget);
          expect(inRail(find.text('All offers')), findsOneWidget);
          expect(inRail(find.text('Sign out')), findsOneWidget);
          expect(find.bySemanticsLabel('Menu'), findsNothing);

          // The content: beside the sidebar, never wider than the column.
          final Rect home = tester.getRect(find.byType(HomeScreen));
          expect(home.left, greaterThanOrEqualTo(rail.right));
          expect(home.width, lessThanOrEqualTo(DesktopMetrics.contentMaxWidth * DesktopMetrics.uiScale));

          // The Units are a grid: the first cards side by side, not window-wide.
          final List<Rect> cards = tester.widgetList(find.byType(NovaProductCard)).take(2).map((Widget w) => tester.getRect(find.byWidget(w))).toList();
          expect(cards, hasLength(2));
          expect(cards[0].top, closeTo(cards[1].top, 0.5));
          expect(cards[0].width, lessThan(home.width / 2));

          await tester.tap(inRail(find.text('Live')));
          await tester.pump();
          expect(shown(LivesScreen), findsOneWidget);
          expect(shown(HomeScreen), findsNothing);
          await tester.tap(inRail(find.text('My lessons')));
          await tester.pump();
          expect(shown(MyLearningScreen), findsOneWidget);
        }));

    testWidgets('a pushed page fades in within 150 ms beside the sidebar, and Esc or the mouse back button go back', (tester) => asPcApp(() async {
          await pumpApp(tester, const Size(1440, 900));

          await tester.tap(find.text('See the Offers'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          final BuildContext page = tester.element(find.byType(OffersCatalogScreen));
          expect(ModalRoute.of(page)!.animation!.status, AnimationStatus.completed);
          // D-193: the page opens beside the sidebar, which stays.
          final Rect rail = tester.getRect(find.byType(NovaSideRail));
          final Rect rect = tester.getRect(find.byType(OffersCatalogScreen));
          expect(find.byType(NovaSideRail).hitTestable(), findsOneWidget);
          expect(rect.left, closeTo(rail.right, 0.01));
          expect(rect.right, closeTo(1440, 0.01));

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.byType(OffersCatalogScreen), findsNothing);
          expect(shown(HomeScreen), findsOneWidget);
          // Esc on the root does nothing.
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump(const Duration(milliseconds: 150));
          expect(shown(HomeScreen), findsOneWidget);

          await tester.tap(find.text('See the Offers'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.byType(OffersCatalogScreen), findsOneWidget);
          final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
          await mouse.down(const Offset(700, 450));
          await mouse.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.byType(OffersCatalogScreen), findsNothing);
        }));

    testWidgets('D-193: the sidebar opens the catalogue beside itself, a tab closes it, full screen hides the sidebar', (tester) => asPcApp(() async {
          await pumpApp(tester, const Size(1440, 900));

          await tester.tap(inRail(find.text('All courses')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(shown(UnitsCatalogScreen), findsOneWidget);
          expect(find.byType(NovaSideRail).hitTestable(), findsOneWidget);

          await tester.tap(inRail(find.text('All offers')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          // The sidebar replaces the open page instead of stacking pages.
          expect(find.byType(UnitsCatalogScreen), findsNothing);
          expect(shown(OffersCatalogScreen), findsOneWidget);

          await tester.tap(inRail(find.text('Live')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.byType(OffersCatalogScreen), findsNothing);
          expect(shown(LivesScreen), findsOneWidget);

          playerFullscreen.value = true;
          await tester.pump();
          expect(find.byType(NovaSideRail), findsNothing);
          playerFullscreen.value = false;
          await tester.pump();
          expect(find.byType(NovaSideRail), findsOneWidget);
          expect(shown(LivesScreen), findsOneWidget);
        }));

    testWidgets('D-193: a full-width button stays at most 440 px wide in the PC app, not on phones', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Future<double> width() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 1200, child: NovaButton(label: 'Open', expand: true, onTap: () {})),
          ),
        ));
        return tester.getSize(find.byType(PressableScale)).width;
      }

      expect(await width(), 1200);
      await asPcApp(() async => expect(await width(), NovaButton.desktopMaxWidth));
    });

    testWidgets('D-193: a signed-in Student\'s phone menu has the catalogue shortcuts', (tester) async {
      await pumpApp(tester, const Size(390, 844));
      await tester.tap(find.bySemanticsLabel('Menu'));
      await frames(tester, count: 8);
      expect(find.text('All courses'), findsOneWidget);
      expect(find.text('All offers'), findsOneWidget);
      await tester.tap(find.text('All courses'));
      await frames(tester, count: 8);
      expect(find.byType(UnitsCatalogScreen), findsOneWidget);
    });

    testWidgets('D-193: the PC Account tab lays its cards in two columns', (tester) => asPcApp(() async {
          await pumpApp(tester, const Size(1440, 900));
          await tester.tap(inRail(find.text('Account')));
          await frames(tester, count: 6);
          final List<Rect> cards =
              tester.widgetList(find.byType(DashboardCard)).map((Widget w) => tester.getRect(find.byWidget(w))).toList();
          expect(cards.length, greaterThanOrEqualTo(4));
          final Set<double> lefts = cards.map((Rect r) => r.left.roundToDouble()).toSet();
          expect(lefts, hasLength(2));
        }));

    testWidgets('a PC window narrowed to a phone width keeps the bottom bar', (tester) => asPcApp(() async {
          await pumpApp(tester, const Size(700, 900));
          expect(find.byType(NovaBottomBar), findsOneWidget);
          expect(find.byType(NovaSideRail), findsNothing);
        }));

    testWidgets('a phone is unchanged: bottom bar, no sidebar, no desktop column', (tester) async {
      await pumpApp(tester, const Size(390, 844));
      expect(find.byType(NovaBottomBar), findsOneWidget);
      expect(find.byType(NovaSideRail), findsNothing);
      expect(find.byType(DesktopFrame), findsNothing);
      expect(isDesktopApp, isFalse);
    });

    testWidgets('the shell keeps a tab\'s state when the window crosses the desktop width', (tester) => asPcApp(() async {
          await pumpApp(tester, const Size(1440, 900));
          await tester.tap(inRail(find.text('Live')));
          await tester.pump();
          final State<StatefulWidget> before = tester.state(find.byType(LivesScreen));

          tester.view.physicalSize = const Size(700, 900);
          await tester.pump();
          expect(find.byType(NovaBottomBar), findsOneWidget);
          expect(find.byType(NovaSideRail), findsNothing);
          expect(identical(tester.state(find.byType(LivesScreen)), before), isTrue);
          expect(shown(LivesScreen), findsOneWidget);
        }));
  });

  group('desktop page transitions and motion', () {
    test('phones keep their slide; the PC app fades pages in 150 ms at most', () {
      final Map<TargetPlatform, PageTransitionsBuilder> builders = NovaTheme.current.pageTransitionsTheme.builders;
      expect(builders[TargetPlatform.android], isA<NovaPageTransitionsBuilder>());
      expect(builders[TargetPlatform.iOS], isA<NovaPageTransitionsBuilder>());
      for (final TargetPlatform desktop in <TargetPlatform>[TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS]) {
        final PageTransitionsBuilder builder = builders[desktop]!;
        expect(builder, isA<DesktopPageTransitionsBuilder>());
        expect(builder.transitionDuration, lessThanOrEqualTo(const Duration(milliseconds: 150)));
        expect(builder.reverseTransitionDuration, lessThanOrEqualTo(const Duration(milliseconds: 150)));
      }
    });

    testWidgets('entrances and count-ups play on phones, not in the PC app', (tester) async {
      Future<void> pump() => tester.pumpWidget(
            const MaterialApp(
              home: Column(children: [Entrance(child: Text('card')), CountUpText(42)]),
            ),
          );

      await pump();
      expect(find.descendant(of: find.byType(Entrance), matching: find.byType(FadeTransition)), findsOneWidget);
      expect(find.text('42'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);

      await asPcApp(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await pump();
        expect(find.descendant(of: find.byType(Entrance), matching: find.byType(FadeTransition)), findsNothing);
        expect(find.text('42'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    });
  });

  group('desktop scrolling', () {
    test('the PC app drags with the mouse and never bounces; phones keep Flutter\'s behaviour', () {
      const NovaScrollBehavior behavior = NovaScrollBehavior();
      expect(behavior.dragDevices, isNot(contains(PointerDeviceKind.mouse)));
      expect(behavior.dragDevices, const MaterialScrollBehavior().dragDevices);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect(behavior.dragDevices, containsAll(<PointerDeviceKind>[PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.touch]));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('in the PC app a list scrolls by mouse drag without bouncing', (tester) => asPcApp(() async {
          final ScrollController controller = ScrollController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              scrollBehavior: const NovaScrollBehavior(),
              home: ListView.builder(controller: controller, itemCount: 100, itemBuilder: (_, int i) => SizedBox(height: 50, child: Text('row $i'))),
            ),
          );
          expect(controller.position.physics, isA<ClampingScrollPhysics>());
          await tester.drag(find.text('row 3'), const Offset(0, -300), kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          expect(controller.offset, greaterThan(200));
          // Past the top: clamped, no bounce.
          await tester.drag(find.text('row 8'), const Offset(0, 900), kind: PointerDeviceKind.mouse);
          await tester.pump();
          expect(controller.offset, 0);
        }));

    group('wheel smoother', () {
      ui.PointerData wheel(double dy, {double dx = 0}) => ui.PointerData(
            viewId: 0,
            kind: ui.PointerDeviceKind.mouse,
            signalKind: ui.PointerSignalKind.scroll,
            physicalX: 400,
            physicalY: 300,
            scrollDeltaX: dx,
            scrollDeltaY: dy,
          );

      test('a notch is spread over several frames, 1.25 × its size in logical pixels', () {
        final List<ui.PointerData> sent = <ui.PointerData>[];
        final DesktopWheelSmoother smoother = DesktopWheelSmoother(
          (ui.PointerDataPacket packet) => sent.addAll(packet.data),
          devicePixelRatio: (_) => 1.5,
        );
        smoother.handle(ui.PointerDataPacket(data: <ui.PointerData>[wheel(100)]));
        expect(sent, isEmpty, reason: 'nothing jumps at once');

        int frames = 0;
        while (smoother.active) {
          smoother.tick(Duration(microseconds: 16667 * frames));
          frames++;
          expect(frames, lessThan(30));
        }
        expect(frames, inInclusiveRange(4, 14), reason: 'about 60–230 ms');
        expect(sent.length, greaterThan(3));
        expect(sent.first.scrollDeltaY / 1.5, lessThan(125 * 0.5));
        final double logical = sent.fold<double>(0, (double sum, ui.PointerData d) => sum + d.scrollDeltaY) / 1.5;
        expect(logical, closeTo(125, 0.01));
        for (final ui.PointerData data in sent) {
          expect(data.signalKind, ui.PointerSignalKind.scroll);
          expect(data.physicalX, 400);
          expect(data.physicalY, 300);
        }
      });

      test('a notch the other way cancels the rest; other pointer events pass at once', () {
        final List<ui.PointerData> sent = <ui.PointerData>[];
        final DesktopWheelSmoother smoother = DesktopWheelSmoother(
          (ui.PointerDataPacket packet) => sent.addAll(packet.data),
          devicePixelRatio: (_) => 1,
        );
        smoother.handle(ui.PointerDataPacket(data: <ui.PointerData>[wheel(100)]));
        smoother.tick(Duration.zero);
        smoother.handle(ui.PointerDataPacket(data: <ui.PointerData>[wheel(-100)]));
        sent.clear();
        int frames = 0;
        while (smoother.active && frames < 30) {
          smoother.tick(Duration(microseconds: 16667 * ++frames));
        }
        expect(sent.fold<double>(0, (double sum, ui.PointerData d) => sum + d.scrollDeltaY), closeTo(-125, 0.01));

        sent.clear();
        const ui.PointerData move = ui.PointerData(viewId: 0, change: ui.PointerChange.hover, kind: ui.PointerDeviceKind.mouse, physicalX: 10);
        const ui.PointerData trackpad = ui.PointerData(viewId: 0, change: ui.PointerChange.panZoomUpdate, kind: ui.PointerDeviceKind.trackpad, panDeltaY: 30);
        smoother.handle(const ui.PointerDataPacket(data: <ui.PointerData>[move, trackpad]));
        expect(sent, hasLength(2));
        expect(smoother.active, isFalse);
      });
    });
  });

  group('capture protection (Windows runner)', () {
    test('the NOVA windows are black in captures (WDA_MONITOR), never excluded (D-188)', () {
      final String protect = File('windows/runner/capture_exclusion.cpp').readAsStringSync();
      expect(protect, contains('SetWindowDisplayAffinity(window, WDA_MONITOR)'));
      expect(protect, isNot(contains('WDA_EXCLUDEFROMCAPTURE')));
      // The app window, before its first frame, and every video window.
      expect(File('windows/runner/win32_window.cpp').readAsStringSync(), contains('ProtectFromCapture(window);'));
      expect(File('windows/runner/protected_player.cpp').readAsStringSync(), contains('ProtectFromCapture(window_);'));
    });
  });
}
