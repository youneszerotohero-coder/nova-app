import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/widgets/success_burst.dart';
import 'package:nova_mobile/core/widgets/nova_scene_image.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/features/account/notifications_screen.dart';
import 'package:nova_mobile/features/account/profile_screen.dart';
import 'package:nova_mobile/features/cart/checkout_screen.dart';
import 'package:nova_mobile/features/detail/course_detail_screen.dart';
import 'package:nova_mobile/features/cart/cart_screen.dart';
import 'package:nova_mobile/features/detail/teacher_detail_screen.dart';
import 'package:nova_mobile/features/explore/explore_screen.dart';
import 'package:nova_mobile/features/home/home_screen.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/features/account/wallet_screen.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/learning/my_learning_screen.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';

import 'nova_font_loader.dart';

/// Design snapshots of the main screens so spacing, hierarchy and the
/// blue direction can be reviewed at a glance. Run with:
///   flutter test --update-goldens test/screens_golden_test.dart
void main() {
  setUpAll(loadNovaFonts);
  setUp(installFixtureApp);

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          theme: NovaTheme.light,
          // Tab screens render inside the shell's Scaffold.
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await settleImages(tester);
  }

  testWidgets('explore screen snapshot', (tester) async {
    await pumpScreen(tester, const ExploreScreen());
    await expectLater(
      find.byType(ExploreScreen),
      matchesGoldenFile('goldens/screen_explore.png'),
    );
  });

  testWidgets('course detail snapshot', (tester) async {
    final Course course = HomeData.popularCourses.first;
    await pumpScreen(tester, CourseDetailScreen(course: course));
    await expectLater(
      find.byType(CourseDetailScreen),
      matchesGoldenFile('goldens/screen_course_detail.png'),
    );
  });

  testWidgets('learn screen snapshot', (tester) async {
    final Course course =
        HomeData.popularCourses.where((Course c) => c.owned).first;
    await pumpScreen(tester, LearnScreen(course: course));
    await expectLater(
      find.byType(LearnScreen),
      matchesGoldenFile('goldens/screen_learn.png'),
    );
  });

  testWidgets('checkout snapshot', (tester) async {
    // The breakdown is the backend's quote, served in production's shape:
    // an Offer with one already-owned Course credited and points applied.
    installFixtureApp(
      commerce: CommerceStore(
        fakeApi(
          FakeBackend(<String, FakeResponse>{
            'POST /checkout/quote': const FakeResponse(200, <String, Object>{
              'data': <String, Object?>{
                'academic_year': '2026/2027',
                'base_amount': '18900.00',
                'overlap_credit': '4200.00',
                'referral_discount': '0.00',
                'promo_discount': '0.00',
                'points_discount': '750.00',
                'final_amount': '13950.00',
                'currency': 'DZD',
                'points_used': 750,
                'points_balance': 750,
                'max_points_usable': 750,
                'points_redemption_enabled': true,
              },
            }),
          }),
        ),
      ),
    );
    await pumpScreen(
      tester,
      const CheckoutScreen(
        item: CartItem(
          id: 'offer:201',
          productKind: 'offer',
          productId: 201,
          title: 'Science Track — Complete Year',
          kind: 'Offer',
          price: 18900,
          compareAtPrice: 18900,
          scene: NovaScene.sunrise,
          icon: Icons.auto_awesome_rounded,
        ),
      ),
    );
    await expectLater(
      find.byType(CheckoutScreen),
      matchesGoldenFile('goldens/screen_checkout.png'),
    );
  });

  testWidgets('profile snapshot', (tester) async {
    await pumpScreen(tester, const ProfileScreen());
    await expectLater(
      find.byType(ProfileScreen),
      matchesGoldenFile('goldens/screen_profile.png'),
    );
  });

  testWidgets('notifications snapshot', (tester) async {
    await pumpScreen(tester, const NotificationsScreen());
    await expectLater(
      find.byType(NotificationsScreen),
      matchesGoldenFile('goldens/screen_notifications.png'),
    );
  });

  testWidgets('my learning snapshot', (tester) async {
    await pumpScreen(tester, const MyLearningScreen());
    await expectLater(
      find.byType(MyLearningScreen),
      matchesGoldenFile('goldens/screen_my_learning.png'),
    );
  });

  testWidgets('wallet snapshot', (tester) async {
    await pumpScreen(tester, const WalletScreen());
    await expectLater(
      find.byType(WalletScreen),
      matchesGoldenFile('goldens/screen_wallet.png'),
    );
  });

  testWidgets('cart snapshot', (tester) async {
    await pumpScreen(tester, const CartScreen());
    await expectLater(
      find.byType(CartScreen),
      matchesGoldenFile('goldens/screen_cart.png'),
    );
  });

  testWidgets('teacher detail snapshot', (tester) async {
    await pumpScreen(
      tester,
      TeacherDetailScreen(teacher: HomeData.teachers.first),
    );
    await expectLater(
      find.byType(TeacherDetailScreen),
      matchesGoldenFile('goldens/screen_teacher.png'),
    );
  });

  testWidgets('home snapshot', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/screen_home.png'),
    );
  });

  testWidgets('success burst mid-flight snapshot', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: NovaTheme.light,
        home: const Scaffold(
          body: Center(child: SuccessBurst(size: 120)),
        ),
      ),
    );
    // Caught while the confetti is still travelling.
    await tester.pump(const Duration(milliseconds: 620));
    await expectLater(
      find.byType(SuccessBurst),
      matchesGoldenFile('goldens/success_burst.png'),
    );
    // Let the controller finish so the test leaves no live timer.
    await tester.pumpAndSettle();
  });
}
