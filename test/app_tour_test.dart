@Tags(<String>['tour'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_colors.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/account/notifications_screen.dart';
import 'package:nova_mobile/features/account/orders_screen.dart';
import 'package:nova_mobile/features/account/settings_screen.dart';
import 'package:nova_mobile/features/account/wallet_screen.dart';
import 'package:nova_mobile/features/auth/login_screen.dart';
import 'package:nova_mobile/features/auth/register_screen.dart';
import 'package:nova_mobile/features/detail/course_detail_screen.dart';
import 'package:nova_mobile/features/detail/teacher_detail_screen.dart';
import 'package:nova_mobile/features/catalog/offers_catalog_screen.dart';
import 'package:nova_mobile/features/catalog/teachers_screen.dart';
import 'package:nova_mobile/features/catalog/units_catalog_screen.dart';
import 'package:nova_mobile/features/auth/auth_gateway_screen.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/learning/lesson_screen.dart';
import 'package:nova_mobile/features/shell/shell_screen.dart';
import 'package:nova_mobile/features/shell/splash_screen.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

/// The app tour in Arabic at phone size (390 × 844), one picture per screen,
/// to review the website look (D-133). Skipped by default (tag `tour`, see
/// dart_test.yaml) and its pictures are not versioned. Render it with:
///   flutter test --run-skipped -t tour --update-goldens test/app_tour_test.dart
void main() {
  setUpAll(loadNovaFonts);

  Future<void> shoot(WidgetTester tester, String name, Widget screen, {bool dark = false, bool scaffold = true, Duration settle = const Duration(milliseconds: 1600), SessionStore? session, double height = 2532}) async {
    AppState state = installFixtureApp(lang: NovaLang.ar);
    if (session != null) {
      state = AppState.seeded(
        session: session,
        catalog: state.catalog,
        learning: state.learning,
        commerce: state.commerce,
        account: state.account,
        lang: NovaLang.ar,
      );
      AppState.instance = state;
    }
    if (dark) state.setDarkMode(true);
    NovaColors.current = dark ? NovaPalette.dark : NovaPalette.light;
    addTearDown(() => NovaColors.current = NovaPalette.light);
    tester.view.physicalSize = Size(1170, height);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NovaTheme.current,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: scaffold ? Scaffold(body: screen) : screen,
        ),
      ),
    );
    await tester.pump(settle);
    // Looping animations (live pulse, splash dots) never settle: decode the
    // images, then let one more beat pass.
    await tester.runAsync(() async {
      for (final Element element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tour/$name.png'));
  }

  Course ownedCourse() => HomeData.popularCourses.where((Course c) => c.owned).first;

  goldenTestWidgets('tour: splash', (tester) => shoot(tester, '00_splash', const NovaSplash(), scaffold: false, settle: const Duration(milliseconds: 1750)));
  goldenTestWidgets('tour: gateway', (tester) => shoot(tester, '01_gateway', const AuthGatewayScreen(), scaffold: false));
  goldenTestWidgets('tour: login', (tester) => shoot(tester, '02_login', const LoginScreen(showBack: true), scaffold: false));
  goldenTestWidgets('tour: register', (tester) => shoot(
        tester,
        '03_register',
        const RegisterScreen(),
        scaffold: false,
        session: SessionStore(fakeApi(FakeBackend(<String, FakeResponse>{
          'GET /auth/registration-options': const FakeResponse(200, <String, Object>{
            'data': <String, Object>{'phone_verification_required': true},
          }),
        }))),
      ));
  goldenTestWidgets('tour: home', (tester) => shoot(tester, '10_home', const ShellScreen(), scaffold: false));
  goldenTestWidgets('tour: my units', (tester) => shoot(tester, '11_my_units', const ShellScreen(initialIndex: ShellScreen.units), scaffold: false));
  goldenTestWidgets('tour: unit', (tester) => shoot(tester, '12_unit', LearnScreen(course: ownedCourse()), scaffold: false));
  goldenTestWidgets('tour: lesson', (tester) => shoot(tester, '13_lesson', LessonScreen(course: ValueNotifier<Course>(ownedCourse()), index: 2), scaffold: false));
  goldenTestWidgets('tour: lesson from live', (tester) => shoot(tester, '13b_lesson_live', LessonScreen(course: ValueNotifier<Course>(ownedCourse()), index: 4), scaffold: false));
  goldenTestWidgets('tour: lives', (tester) => shoot(tester, '14_lives', const ShellScreen(initialIndex: ShellScreen.lives), scaffold: false));
  goldenTestWidgets('tour: units catalogue', (tester) => shoot(tester, '20_units_catalog', const UnitsCatalogScreen(), scaffold: false));
  goldenTestWidgets('tour: unit detail', (tester) => shoot(tester, '21_unit_detail', CourseDetailScreen(course: HomeData.popularCourses.first), scaffold: false));
  goldenTestWidgets('tour: teacher', (tester) => shoot(tester, '22_teacher', TeacherDetailScreen(teacher: HomeData.teachers.first), scaffold: false));
  goldenTestWidgets('tour: cart', (tester) => shoot(tester, '30_cart', const ShellScreen(initialIndex: ShellScreen.cart), scaffold: false));
  goldenTestWidgets('tour: account', (tester) => shoot(tester, '40_account', const ShellScreen(initialIndex: ShellScreen.account), scaffold: false));
  goldenTestWidgets('tour: orders', (tester) => shoot(tester, '41_orders', const OrdersScreen(), scaffold: false));
  goldenTestWidgets('tour: wallet', (tester) => shoot(tester, '42_wallet', const WalletScreen(), scaffold: false));
  goldenTestWidgets('tour: settings', (tester) => shoot(tester, '43_settings', const SettingsScreen(), scaffold: false));
  goldenTestWidgets('tour: notifications', (tester) => shoot(tester, '44_notifications', const NotificationsScreen(), scaffold: false));
  goldenTestWidgets('tour: home dark', (tester) => shoot(tester, '90_home_dark', const ShellScreen(), dark: true, scaffold: false));
  goldenTestWidgets('tour: offers catalogue', (tester) => shoot(tester, '20b_offers_catalog', const OffersCatalogScreen(), scaffold: false));
  goldenTestWidgets('tour: teachers', (tester) => shoot(tester, '23_teachers', const TeachersScreen(), scaffold: false));
  goldenTestWidgets('tour: units catalogue dark', (tester) => shoot(tester, '91_units_catalog_dark', const UnitsCatalogScreen(), dark: true, scaffold: false));
  goldenTestWidgets('tour: cart dark', (tester) => shoot(tester, '92_cart_dark', const ShellScreen(initialIndex: ShellScreen.cart), dark: true, scaffold: false));
  goldenTestWidgets('tour: account dark', (tester) => shoot(tester, '93_account_dark', const ShellScreen(initialIndex: ShellScreen.account), dark: true, scaffold: false));
  goldenTestWidgets('tour: offer detail', (tester) => shoot(tester, '21b_offer_detail', CourseDetailScreen.pack(pack: HomeData.featuredPacks.first), scaffold: false));
  goldenTestWidgets('tour: unit detail dark', (tester) => shoot(tester, '94_unit_detail_dark', CourseDetailScreen(course: HomeData.popularCourses.first), dark: true, scaffold: false));
  goldenTestWidgets('tour: teacher dark', (tester) => shoot(tester, '95_teacher_dark', TeacherDetailScreen(teacher: HomeData.teachers.first), dark: true, scaffold: false));

  // D-134: "continue without an account" — the whole first screen, then a visitor's Home and a tab that asks to sign in.
  Future<SessionStore> signedOut(WidgetTester tester) async {
    final SessionStore session = SessionStore(fakeApi(FakeBackend(<String, FakeResponse>{
      'GET /auth/me': const FakeResponse(401, <String, Object>{
        'error': <String, String>{'code': 'UNAUTHENTICATED', 'message': 'Authentication is required.'},
      }),
    })));
    await tester.runAsync(session.boot);
    return session;
  }

  goldenTestWidgets('tour: gateway full', (tester) => shoot(tester, '04_gateway_full', const AuthGatewayScreen(), scaffold: false, height: 4500));
  goldenTestWidgets('tour: guest home', (tester) async => shoot(tester, '05_guest_home', const ShellScreen(), scaffold: false, session: await signedOut(tester)));
  goldenTestWidgets('tour: guest tab', (tester) async => shoot(tester, '06_guest_lessons', const ShellScreen(initialIndex: ShellScreen.units), scaffold: false, session: await signedOut(tester)));
  goldenTestWidgets('tour: guest unit', (tester) async => shoot(tester, '07_guest_unit', CourseDetailScreen(course: HomeData.popularCourses.first), scaffold: false, session: await signedOut(tester)));
}
