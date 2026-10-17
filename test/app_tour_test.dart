@Tags(<String>['tour'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/push/push_platform.dart';
import 'package:nova_mobile/core/push/push_service.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_colors.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/chat_store.dart';
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
import 'package:nova_mobile/features/messages/chat_audio.dart';
import 'package:nova_mobile/features/messages/chat_info_screen.dart';
import 'package:nova_mobile/features/messages/chat_list_screen.dart';
import 'package:nova_mobile/features/messages/chat_room_screen.dart';
import 'package:nova_mobile/features/shell/shell_screen.dart';
import 'package:nova_mobile/features/shell/splash_screen.dart';
import 'package:nova_mobile/features/teacher/teacher_shell.dart';
import 'package:nova_mobile/features/auth/change_password_screen.dart';

import 'fixtures/chat_fixtures.dart';
import 'fixtures/fake_api.dart';
import 'fixtures/fake_push.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

/// The app tour in Arabic at phone size (390 × 844), one picture per screen,
/// to review the website look (D-133). Skipped by default (tag `tour`, see
/// dart_test.yaml) and its pictures are not versioned. Render it with:
///   flutter test --run-skipped -t tour --update-goldens test/app_tour_test.dart
void main() {
  setUpAll(loadNovaFonts);

  Future<void> shoot(WidgetTester tester, String name, Widget screen, {bool dark = false, bool scaffold = true, Duration settle = const Duration(milliseconds: 1600), SessionStore? session, PushService? push, double height = 2532, ChatStore? chat, Future<void> Function(WidgetTester tester)? act}) async {
    AppState state = installFixtureApp(lang: NovaLang.ar);
    if (session != null || chat != null || push != null) {
      state = AppState.seeded(
        session: session ?? state.session,
        chat: chat,
        catalog: state.catalog,
        learning: state.learning,
        commerce: state.commerce,
        account: state.account,
        push: push,
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
    if (act != null) await act(tester);
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

  // D-143 group chats: the list, a room with a voice note and a PDF, its info, a recording.
  goldenTestWidgets('tour: messages list', (tester) => shoot(tester, '50_messages_list', const ChatListScreen(), scaffold: false, chat: tourChatStore()));
  goldenTestWidgets('tour: chat room', (tester) => shoot(tester, '51_chat_room', const ChatRoomScreen(roomId: 3), scaffold: false, chat: tourChatStore()));
  goldenTestWidgets('tour: chat info', (tester) => shoot(tester, '52_chat_info', const ChatInfoScreen(roomId: 3), scaffold: false, chat: tourChatStore()));
  goldenTestWidgets('tour: chat info full', (tester) => shoot(tester, '52b_chat_info_full', const ChatInfoScreen(roomId: 3), scaffold: false, chat: tourChatStore(), height: 4200));
  goldenTestWidgets('tour: chat recording', (tester) {
    final FakeRecorder recorder = FakeRecorder();
    final ChatRecorder Function() previous = ChatRecorder.factory;
    ChatRecorder.factory = () => recorder;
    addTearDown(() => ChatRecorder.factory = previous);
    return shoot(tester, '53_chat_recording', const ChatRoomScreen(roomId: 3), scaffold: false, chat: tourChatStore(), act: (WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.mic_rounded));
      for (int i = 0; i < 72; i++) {
        recorder.emit(0.15 + 0.8 * ((i * 7) % 11) / 10 * (i.isEven ? 1 : 0.55));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
  });
  goldenTestWidgets('tour: chat room dark', (tester) => shoot(tester, '96_chat_room_dark', const ChatRoomScreen(roomId: 3), dark: true, scaffold: false, chat: tourChatStore()));

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

  // D-143: the Teacher space (chats seam, settings) and the temporary password step.
  SessionStore teacher({String? step}) {
    final Map<String, Object?> user = <String, Object?>{
      'id': 41,
      'role': 'teacher',
      'phone': '0661234567',
      'next_required_step': step,
      'teacher': <String, Object?>{'id': 5, 'first_name': 'كريم', 'last_name': 'بن علي', 'photo_url': null},
    };
    return SessionStore.seeded(SessionStore.profileOf(user), user: user);
  }

  goldenTestWidgets('tour: teacher chats', (tester) => shoot(tester, '50_teacher_chats', const TeacherShell(), scaffold: false, session: teacher(), chat: tourChatStore()));
  goldenTestWidgets('tour: teacher settings', (tester) async {
    final PushService push = PushService(platform: FakePushPlatform(status: PushPermission.denied), api: null, flags: MemoryPushFlags());
    await push.start();
    await shoot(tester, '51_teacher_settings', const TeacherShell(initialIndex: TeacherShell.settings), scaffold: false, session: teacher(), push: push, height: 4200);
  });
  goldenTestWidgets('tour: teacher password', (tester) => shoot(tester, '52_teacher_password', const ChangePasswordScreen(), scaffold: false, session: teacher(step: 'password_change')));
}
