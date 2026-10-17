import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/api_exception.dart';
import 'package:nova_mobile/core/api/nova_api.dart';
import 'package:nova_mobile/core/push/firebase_push_platform.dart';
import 'package:nova_mobile/core/push/push_config.dart';
import 'package:nova_mobile/core/push/push_platform.dart';
import 'package:nova_mobile/core/push/push_service.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/account_store.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/account/notifications_screen.dart';
import 'package:nova_mobile/features/auth/change_password_screen.dart';
import 'package:nova_mobile/features/messages/chat_list_screen.dart';
import 'package:nova_mobile/features/messages/chat_room_screen.dart';
import 'package:nova_mobile/features/shell/app_gate.dart';
import 'package:nova_mobile/features/shell/shell_screen.dart';
import 'package:nova_mobile/features/teacher/teacher_settings_screen.dart';
import 'package:nova_mobile/features/teacher/teacher_shell.dart';
import 'package:nova_mobile/features/teacher/teacher_top_bar.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fake_push.dart';
import 'fixtures/fixture_app.dart';

/// `UserResource` of a Teacher (D-143 §3.3).
Map<String, Object?> _teacher({String? step}) => <String, Object?>{
      'id': 41,
      'role': 'teacher',
      'phone': '0661234567',
      'must_change_password': step == 'password_change',
      'next_required_step': step,
      'teacher': <String, Object?>{'id': 5, 'first_name': 'Karim', 'last_name': 'Benali', 'photo_url': null},
    };

Map<String, Object?> _student() => <String, Object?>{
      'id': 9,
      'role': 'student',
      'phone': '0555123456',
      'next_required_step': null,
      'student': <String, Object?>{'id': 3, 'first_name': 'Ines', 'last_name': 'Benali'},
    };

const FakeResponse _noNotifications = FakeResponse(200, <String, Object>{
  'data': <Object>[],
  'unread_count': 0,
  'meta': <String, Object>{'last_page': 1},
});

/// An [AppState] whose every store talks to [api] (nothing seeded), so a
/// test sees each request the app makes.
AppState _networkState(NovaApi api, {PushService? push, SessionStore? session}) {
  final AppState state = AppState.seeded(
    session: session ?? SessionStore(api),
    catalog: CatalogStore(api),
    learning: LearningStore(api),
    commerce: CommerceStore(api),
    account: AccountStore(api),
    push: push,
    lang: NovaLang.en,
  );
  AppState.instance = state;
  return state;
}

/// The fixture state around [session] (seeded stores, no network but the session's).
AppState _install(SessionStore session, {PushService? push}) {
  final AppState base = installFixtureApp();
  final AppState state = AppState.seeded(
    session: session,
    catalog: base.catalog,
    learning: base.learning,
    commerce: base.commerce,
    account: base.account,
    push: push,
    lang: NovaLang.en,
  );
  AppState.instance = state;
  return state;
}

Future<void> _pump(WidgetTester tester, AppState state, Widget home) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: NovaTheme.light, home: home)));
  await tester.pumpAndSettle();
}

/// The Student space pulses (live dot): frames, not settle.
Future<void> _pumpFrames(WidgetTester tester, AppState state, Widget home) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: NovaTheme.light, home: home)));
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets the fake HTTP and the push streams deliver.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

Iterable<String> _paths(FakeBackend backend) => backend.requests.map((FakeRequest r) => '${r.method} ${r.path}');

/// Every endpoint a Teacher account may call (BR-T7) that this app uses.
bool _teacherAllowed(FakeRequest r) =>
    r.path.startsWith('/auth/') || r.path.startsWith('/me/notifications') || r.path.startsWith('/me/devices');

void main() {
  group('Teacher accounts (D-143)', () {
    test('a Teacher signs in on the Student sign-in; their name comes from the account', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _teacher()}),
      });
      final SessionStore session = SessionStore(fakeApi(backend));

      await session.login(phone: '0661234567', password: 'K7P-M4X-Q2R');

      expect(session.signedIn, isTrue);
      expect(session.isTeacher, isTrue);
      expect(session.role, 'teacher');
      expect(session.teacher?.id, 5);
      expect(session.teacher?.fullName, 'Karim Benali');
      expect(session.profile?.fullName, 'Karim Benali');
      expect(backend.requests.any((FakeRequest r) => r.path == '/auth/logout'), isFalse);
    });

    test('an Admin is still refused and signed out; a Student is not a Teacher', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{..._student(), 'role': 'admin'},
        }),
        'POST /auth/logout': const FakeResponse(204),
      });
      final SessionStore session = SessionStore(fakeApi(backend));

      await expectLater(
        session.login(phone: '0555000000', password: 'x'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'STUDENT_ONLY')),
      );
      expect(session.signedIn, isFalse);
      expect(session.isTeacher, isFalse);
      expect(_paths(backend), contains('POST /auth/logout'));

      final SessionStore student = SessionStore(fakeApi(FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _student()}),
      })));
      await student.login(phone: '0555123456', password: 'NovaSecure9!');
      expect(student.isTeacher, isFalse);
      expect(student.teacher, isNull);
    });

    test('a signed-in Teacher loads no Student store, only their notifications', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _teacher()}),
        'GET /me/notifications': _noNotifications,
      });
      final AppState state = _networkState(fakeApi(backend));

      await state.session.login(phone: '0661234567', password: 'NovaSecure9!');
      await _settle();
      // Neither a language change, an account refresh nor a realtime
      // notification reaches a Student endpoint (403 TEACHER_FORBIDDEN).
      state.setLang(NovaLang.fr);
      await state.refreshAccount();
      state.onNotificationCreated(<String, dynamic>{'id': 'n-1', 'type': 'admin_message', 'title': 'Bonjour', 'message': '…'});
      await _settle();

      expect(backend.requests.where((FakeRequest r) => !_teacherAllowed(r)).map((FakeRequest r) => r.path), isEmpty);
      expect(_paths(backend), contains('GET /me/notifications'));
      expect(_paths(backend), isNot(contains('GET /me/points')));
    });

    test('launching with a stored Teacher session skips the catalogue; a Student gets it', () async {
      final FakeBackend teacherBackend = FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _teacher()}),
        'GET /me/notifications': _noNotifications,
      });
      await _networkState(fakeApi(teacherBackend)).boot();
      await _settle();
      expect(teacherBackend.requests.where((FakeRequest r) => !_teacherAllowed(r)).map((FakeRequest r) => r.path), isEmpty);

      final FakeBackend studentBackend = FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _student()}),
      });
      await _networkState(fakeApi(studentBackend)).boot();
      expect(studentBackend.requests.any((FakeRequest r) => r.path.startsWith('/courses')), isTrue);
    });

    testWidgets('the root sends a Teacher to the Teacher shell and a Student to theirs', (tester) async {
      final SessionStore teacher = SessionStore(fakeApi(FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _teacher()}),
      })));
      await tester.runAsync(teacher.boot);
      await _pump(tester, _install(teacher), const AppGate());

      expect(find.byType(TeacherShell), findsOneWidget);
      expect(find.byType(ShellScreen), findsNothing);
      expect(find.byType(ChatListScreen), findsOneWidget);
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Alerts'), findsOneWidget);
      // No catalogue, cart, Lessons nor Lives.
      expect(find.text('Cart'), findsNothing);
      expect(find.text('My lessons'), findsNothing);

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.byType(TeacherSettingsScreen), findsOneWidget);
      // The Teacher bar (photo or initials, name) stands for the Student one.
      expect(find.byType(TeacherTopBar), findsOneWidget);
      expect(find.text('Karim Benali'), findsWidgets);
      expect(find.text('0661234567'), findsOneWidget);
      expect(find.text('Not available in this version of the app.'), findsOneWidget);

      await tester.tap(find.text('Alerts').last);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);

      final SessionStore student = SessionStore(fakeApi(FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _student()}),
      })));
      await tester.runAsync(student.boot);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, _install(student), const AppGate());
      expect(find.byType(ShellScreen), findsOneWidget);
      expect(find.byType(TeacherShell), findsNothing);
    });

    testWidgets('a temporary password is changed first; signing out stays possible', (tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _teacher(step: 'password_change')}),
        'POST /auth/change-password': FakeResponse(200, <String, Object?>{'data': _teacher()}),
      });
      final SessionStore session = SessionStore(fakeApi(backend));
      await tester.runAsync(session.boot);
      await _pump(tester, _install(session), const AppGate());

      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(find.byType(TeacherShell), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'NovaSecure9!');
      await tester.enterText(find.byType(TextField).at(1), 'NovaSecure9!');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();

      expect(backend.requests.last.path, '/auth/change-password');
      expect(find.byType(ChangePasswordScreen), findsNothing);
      expect(find.byType(TeacherShell), findsOneWidget);
    });
  });

  group('Firebase push (D-143)', () {
    test('push is off without the Firebase --dart-defines', () async {
      expect(const PushConfig().optionsFor(TargetPlatform.android), isNull);
      expect(const PushConfig(apiKey: 'k', projectId: 'p', senderId: '1').optionsFor(TargetPlatform.android), isNull);
      const PushConfig full = PushConfig(apiKey: 'k', projectId: 'p', senderId: '1', appIdAndroid: '1:1:android:a', appIdIos: '1:1:ios:b');
      expect(full.optionsFor(TargetPlatform.android)?.appId, '1:1:android:a');
      expect(full.optionsFor(TargetPlatform.iOS)?.appId, '1:1:ios:b');
      // This test build has none: no Firebase platform at all.
      expect(FirebasePushPlatform.fromEnvironment(), isNull);

      final FakeBackend backend = FakeBackend(<String, FakeResponse>{});
      final PushService push = PushService(platform: null, api: fakeApi(backend), flags: MemoryPushFlags());
      expect(await push.start(), isFalse);
      await push.signedIn();
      await push.offerPermission(() async => fail('nothing to explain without push'));
      await push.unregister();
      expect(push.available, isFalse);
      expect(backend.requests, isEmpty);
    });

    test('a Firebase start failure leaves push off', () async {
      final PushService push = PushService(platform: _FailingPlatform(), api: null, flags: MemoryPushFlags());
      expect(await push.start(), isFalse);
      expect(push.available, isFalse);
    });

    test('explained once, then the system asks; the token is registered with its platform and version', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{'POST /me/devices': const FakeResponse(204)});
      final FakePushPlatform platform = FakePushPlatform();
      final MemoryPushFlags flags = MemoryPushFlags();
      final PushService push = PushService(platform: platform, api: fakeApi(backend), flags: flags);

      await push.signedIn();
      // Not allowed yet: nothing is registered before the question.
      expect(_paths(backend), isNot(contains('POST /me/devices')));

      int explained = 0;
      await push.offerPermission(() async {
        explained++;
        return true;
      });

      expect(explained, 1);
      expect(platform.prompts, 1);
      expect(push.permission, PushPermission.granted);
      final FakeRequest sent = backend.requests.lastWhere((FakeRequest r) => r.path == '/me/devices');
      expect(sent.method, 'POST');
      expect(sent.data, <String, String>{'token': 'fcm-token-1', 'platform': 'android', 'app_version': '0.3.0+15'});

      // Once per installation.
      platform.status = PushPermission.denied;
      await push.offerPermission(() async {
        explained++;
        return true;
      });
      expect(explained, 1);
      expect(platform.prompts, 1);
    });

    test('"Not now" shows no system prompt; Settings\' "Enable" asks, then opens the phone settings', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{'POST /me/devices': const FakeResponse(204)});
      final FakePushPlatform platform = FakePushPlatform(answer: PushPermission.blocked);
      final PushService push = PushService(platform: platform, api: fakeApi(backend), flags: MemoryPushFlags());
      await push.signedIn();

      await push.offerPermission(() async => false);
      expect(platform.prompts, 0);

      expect(await push.enable(), PushPermission.blocked);
      expect(platform.prompts, 1);
      expect(platform.settingsOpened, 1);
      expect(backend.requests, isEmpty);

      // Allowed in the phone settings, back in the app.
      platform.status = PushPermission.granted;
      await push.refreshPermission();
      expect(_paths(backend), contains('POST /me/devices'));
    });

    test('already allowed: registered at sign-in without a question; a refreshed token again', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{'POST /me/devices': const FakeResponse(204)});
      final FakePushPlatform platform = FakePushPlatform(status: PushPermission.granted);
      final PushService push = PushService(platform: platform, api: fakeApi(backend), flags: MemoryPushFlags());

      await push.signedIn();
      await push.offerPermission(() async => fail('already allowed'));
      expect(backend.requests.where((FakeRequest r) => r.path == '/me/devices'), hasLength(1));
      expect(push.registeredToken, 'fcm-token-1');

      platform.refreshes.add('fcm-token-9');
      await _settle();
      final List<FakeRequest> sent = backend.requests.where((FakeRequest r) => r.path == '/me/devices').toList();
      expect(sent, hasLength(2));
      expect((sent.last.data! as Map<String, dynamic>)['token'], 'fcm-token-9');
      expect(push.registeredToken, 'fcm-token-9');
    });

    test('no registration before the required steps nor for a visitor', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _teacher(step: 'password_change')}),
        'POST /auth/change-password': FakeResponse(200, <String, Object?>{'data': _teacher()}),
        'POST /me/devices': const FakeResponse(204),
        'GET /me/notifications': _noNotifications,
      });
      final NovaApi api = fakeApi(backend);
      final PushService push = PushService(
        platform: FakePushPlatform(status: PushPermission.granted),
        api: api,
        flags: MemoryPushFlags(),
      );
      final AppState state = _networkState(api, push: push);

      await state.session.login(phone: '0661234567', password: 'K7P-M4X-Q2R');
      await _settle();
      expect(_paths(backend), isNot(contains('POST /me/devices')));

      await state.session.changePassword('NovaSecure9!', 'NovaSecure9!');
      await _settle();
      expect(_paths(backend), contains('POST /me/devices'));
    });

    test('sign-out removes the token from the account before the session ends', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _teacher()}),
        'GET /me/notifications': _noNotifications,
        'POST /me/devices': const FakeResponse(204),
        'DELETE /me/devices': const FakeResponse(204),
        'POST /auth/logout': const FakeResponse(204),
      });
      final NovaApi api = fakeApi(backend);
      final FakePushPlatform platform = FakePushPlatform(status: PushPermission.granted);
      final PushService push = PushService(platform: platform, api: api, flags: MemoryPushFlags());
      final AppState state = _networkState(api, push: push);

      await state.session.login(phone: '0661234567', password: 'NovaSecure9!');
      await _settle();
      expect(push.registeredToken, 'fcm-token-1');

      await state.session.logout();
      await _settle();

      final List<String> order = _paths(backend).toList();
      final int removed = order.indexOf('DELETE /me/devices');
      expect(removed, greaterThanOrEqualTo(0));
      expect(removed, lessThan(order.indexOf('POST /auth/logout')));
      expect(backend.requests[removed].data, <String, String>{'token': 'fcm-token-1'});
      expect(platform.deletes, 1);
      expect(push.registeredToken, isNull);
      expect(state.session.signedIn, isFalse);
    });

    test('a session lost elsewhere deletes the phone token (no request without a session)', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _student()}),
        'POST /me/devices': const FakeResponse(204),
      });
      final NovaApi api = fakeApi(backend);
      final FakePushPlatform platform = FakePushPlatform(status: PushPermission.granted);
      final PushService push = PushService(platform: platform, api: api, flags: MemoryPushFlags());
      final AppState state = _networkState(api, push: push);
      await state.session.login(phone: '0555123456', password: 'NovaSecure9!');
      await _settle();
      expect(push.registeredToken, 'fcm-token-1');

      state.session.replacedElsewhere('another-device');
      await _settle();

      expect(platform.deletes, 1);
      expect(_paths(backend), isNot(contains('DELETE /me/devices')));
    });

    test('in the foreground a chat message is left to the chat; anything else is announced', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _teacher()}),
        'GET /me/notifications': _noNotifications,
      });
      final NovaApi api = fakeApi(backend);
      final FakePushPlatform platform = FakePushPlatform();
      final PushService push = PushService(platform: platform, api: api, flags: MemoryPushFlags());
      final AppState state = _networkState(api, push: push);
      await push.start();
      await state.session.login(phone: '0661234567', password: 'NovaSecure9!');
      await _settle();
      final List<AppNotification> announced = <AppNotification>[];
      final StreamSubscription<AppNotification> listening = state.account.arrivals.listen(announced.add);
      addTearDown(listening.cancel);
      final int listed = backend.requests.where((FakeRequest r) => r.path == '/me/notifications').length;

      platform.foreground.add(const PushPayload(
        data: <String, String>{'type': 'chat_message', 'room_id': '3', 'route': '/chats/3'},
        title: 'Maths 3AS',
        body: 'Karim: Bonsoir',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(announced, isEmpty);
      expect(state.account.notifications, isEmpty);

      platform.foreground.add(const PushPayload(
        data: <String, String>{'type': 'admin_message', 'notification_id': 'n-7', 'route': '/teacher'},
        title: 'NOVA',
        body: 'Réunion demain à 18 h',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(announced.single.id, 'n-7');
      expect(announced.single.body, 'Réunion demain à 18 h');
      await _settle();
      expect(backend.requests.where((FakeRequest r) => r.path == '/me/notifications').length, listed + 1);

      // No database id: the list reloads, nothing is announced.
      platform.foreground.add(const PushPayload(data: <String, String>{'type': 'admin_message'}, title: 'NOVA'));
      await _settle();
      expect(announced, hasLength(1));
      expect(backend.requests.where((FakeRequest r) => r.path == '/me/notifications').length, listed + 2);
    });

    testWidgets('a tapped chat notification opens its chat over the space; another one the notifications', (tester) async {
      final FakePushPlatform platform = FakePushPlatform(status: PushPermission.granted);
      final PushService push = PushService(platform: platform, api: null, flags: MemoryPushFlags());
      final SessionStore session = SessionStore(fakeApi(FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _teacher()}),
      })));
      await tester.runAsync(session.boot);
      final AppState state = _install(session, push: push);
      await push.start();
      await _pump(tester, state, const AppGate());

      platform.opened.add(const PushPayload(data: <String, String>{'type': 'chat_message', 'room_id': '12', 'route': '/chats/12'}));
      // The real chat room shows its loading animation (no chat endpoint here): pump, never settle.
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).roomId, 12);
      expect(find.byType(TeacherShell, skipOffstage: false), findsOneWidget);

      Navigator.of(tester.element(find.byType(ChatRoomScreen))).pop();
      await tester.pumpAndSettle();
      platform.opened.add(const PushPayload(data: <String, String>{'type': 'ccp_approved', 'notification_id': 'n-2'}));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      // Let the explanation timer of the shell run out.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('a tap that launched the app opens once the signed-in space shows', (tester) async {
      final FakePushPlatform platform = FakePushPlatform(status: PushPermission.granted)
        ..launch = const PushPayload(data: <String, String>{'type': 'chat_message', 'room_id': '4'});
      final PushService push = PushService(platform: platform, api: null, flags: MemoryPushFlags());
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _student()}),
      });
      final SessionStore session = SessionStore(fakeApi(backend));
      final AppState state = _install(session, push: push);
      // Firebase reports the launch tap before the session is known.
      await push.start();
      await tester.pump();
      expect(state.pushTaps.pending?.roomId, 4);

      await tester.runAsync(session.boot);
      await _pumpFrames(tester, state, const AppGate());

      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).roomId, 4);
      expect(state.pushTaps.pending, isNull);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the space explains notifications once, a moment after it shows', (tester) async {
      final FakePushPlatform platform = FakePushPlatform();
      final MemoryPushFlags flags = MemoryPushFlags();
      final PushService push = PushService(platform: platform, api: null, flags: flags);
      final SessionStore session = SessionStore(fakeApi(FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _teacher()}),
      })));
      await tester.runAsync(session.boot);
      final AppState state = _install(session, push: push);
      await push.start();
      await push.signedIn();
      await _pump(tester, state, const AppGate());

      expect(find.text('Turn on notifications'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(find.text('Turn on notifications'), findsOneWidget);
      expect(find.text('Get your Students’ messages as soon as they are sent, even when the app is closed.'), findsOneWidget);

      await tester.tap(find.text('Enable notifications'));
      await tester.pumpAndSettle();
      expect(platform.prompts, 1);
      expect(flags.value, isTrue);
      expect(find.text('Turn on notifications'), findsNothing);
    });
  });
}

class _FailingPlatform extends FakePushPlatform {
  @override
  Future<void> initialize() async => throw StateError('No Google services');
}
