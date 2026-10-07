import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/api_error_text.dart';
import 'package:nova_mobile/core/api/api_exception.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/utils/phone.dart';
import 'package:nova_mobile/data/account_store.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/auth/change_password_screen.dart';
import 'package:nova_mobile/features/auth/login_screen.dart';
import 'package:nova_mobile/features/auth/phone_step_screen.dart';
import 'package:nova_mobile/features/auth/register_screen.dart';
import 'package:nova_mobile/features/shell/app_gate.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';

/// D-078 / D-079 on the Student app, as on the website: one account per
/// phone number, any spelling of that number, passwords not the phone.

const String _phoneInvalid =
    'Enter a valid mobile number: 05, 06 or 07 followed by 8 digits.';
const String _phoneStrict =
    'The number must have exactly 10 digits and start with 05, 06 or 07: digits only, '
    'no spaces or letters.';
const String _phoneTaken =
    'An account already exists with this phone number. If it is yours, sign in with this '
    'number instead of creating a new account (if you never chose a password for it, your '
    'password is your phone number). If it belongs to a family member, register with your '
    'own mobile number. Forgot your password? Use “Forgot your password?” on the sign-in '
    'screen to receive a code by SMS or WhatsApp.';

/// The backend's error envelope (`ApiExceptionRenderer`).
FakeResponse _error(int status, String code, String message, [Object? details]) =>
    FakeResponse(status, <String, Object>{
      'error': <String, Object>{
        'code': code,
        'message': message,
        'details': ?details,
      },
    });

/// The registration reference lists (`GET /levels`, `/wilayas`…).
final Map<String, FakeResponse> _references = <String, FakeResponse>{
  'GET /levels': const FakeResponse(200, <String, Object>{
    'data': <Object>[
      <String, Object>{'id': 2, 'code': '2AS', 'name_fr': '2AS', 'name_ar': '2 ثانوي'},
    ],
  }),
  'GET /tracks': const FakeResponse(200, <String, Object>{'data': <Object>[]}),
  'GET /wilayas': const FakeResponse(200, <String, Object>{
    'data': <Object>[
      <String, Object>{'id': 16, 'name_fr': 'Alger', 'name_ar': 'الجزائر'},
    ],
  }),
  'GET /wilayas/16/communes': const FakeResponse(200, <String, Object>{
    'data': <Object>[
      <String, Object>{'id': 1601, 'name_fr': 'Bab Ezzouar', 'name_ar': 'باب الزوار'},
    ],
  }),
};

/// Chooses [option] in the register form's [index]th picker.
Future<void> _pick(WidgetTester tester, int index, String option) async {
  await tester.tap(find.byType(DropdownButton<int>).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The fixture app with [session] in place of the seeded one (English).
AppState _install(SessionStore session, {ReferenceStore? references}) {
  final AppState base = installFixtureApp();
  final AppState state = AppState.seeded(
    session: session,
    catalog: base.catalog,
    learning: base.learning,
    commerce: base.commerce,
    account: base.account,
    references: references,
    lang: NovaLang.en,
  );
  AppState.instance = state;
  return state;
}

Future<void> _pump(WidgetTester tester, AppState state, Widget home) async {
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(theme: NovaTheme.light, home: home),
    ),
  );
  await tester.pumpAndSettle();
}

/// [apiErrorText] for [error] in [lang].
Future<String> _text(WidgetTester tester, Object error, NovaLang lang) async {
  final AppState state = installFixtureApp()..setLang(lang);
  late String text;
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        home: Builder(builder: (BuildContext context) {
          text = apiErrorText(context, error);
          return const SizedBox();
        }),
      ),
    ),
  );
  return text;
}

String _fieldText(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

void main() {
  group('Algerian mobile numbers (website normalizeAlgerianMobile)', () {
    const Map<String, String?> table = <String, String?>{
      '0555123456': '0555123456',
      '0555 12 34 56': '0555123456',
      ' 06-61-23-45-67 ': '0661234567',
      '+213555123456': '0555123456',
      '+213 555 12 34 56': '0555123456',
      '00213555123456': '0555123456',
      '213555123456': '0555123456',
      '+2130555123456': '0555123456',
      '0213555123456': '0555123456',
      '555123456': '0555123456',
      '771234567': '0771234567',
      '٠٥٥٥١٢٣٤٥٦': '0555123456',
      '+٢١٣ ٦٦١ ٢٣ ٤٥ ٦٧': '0661234567',
      '۰۷۷۱۲۳۴۵۶۷': '0771234567',
      '0455123456': null,
      '0212345678': null,
      '05551234': null,
      '055512345678': null,
      '+33612345678': null,
      'ines': null,
      '': null,
    };
    for (final MapEntry<String, String?> row in table.entries) {
      test('"${row.key}" → ${row.value}', () {
        expect(normalizeAlgerianMobile(row.key), row.value);
      });
    }
  });

  test('a password is the phone in any spelling (website samePhone)', () {
    expect(isSamePhone('0555123456', '0555123456'), isTrue);
    expect(isSamePhone('+213555123456', '0555 12 34 56'), isTrue);
    expect(isSamePhone('555123456', '+213555123456'), isTrue);
    expect(isSamePhone('00213 555 12 34 56', '0555123456'), isTrue);
    expect(isSamePhone('0555123457', '0555123456'), isFalse);
    expect(isSamePhone('NovaSecure9!', '0555123456'), isFalse);
  });

  group('registration', () {
    testWidgets('registration takes exactly 05XXXXXXXX, checked before the server (D-081)',
        (tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{});
      await _pump(tester, _install(SessionStore(fakeApi(backend))), const RegisterScreen());

      // The field keeps digits only, 10 at most.
      await tester.enterText(find.byType(TextField).at(2), '+213 555 12 34 56');
      expect(_fieldText(tester, 2), '2135551234');

      await tester.enterText(find.byType(TextField).at(2), '0455 12 34 56');
      expect(_fieldText(tester, 2), '0455123456');
      await tester.tap(find.text('Next step'));
      await tester.pumpAndSettle();

      expect(find.text(_phoneStrict), findsWidgets);
      expect(backend.requests.where((FakeRequest r) => r.method != 'GET'), isEmpty);
    });

    testWidgets('missing fields and a short password are flagged in Arabic without the server',
        (tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{..._references});
      final AppState state = _install(
        SessionStore(fakeApi(backend)),
        references: ReferenceStore(fakeApi(backend)),
      )..setLang(NovaLang.ar);
      await _pump(tester, state, const RegisterScreen());
      backend.requests.clear();

      await tester.enterText(find.byType(TextField).at(2), '0555 12 34 56');
      await tester.enterText(find.byType(TextField).at(3), 'short');
      // Step 1 (D-122): the names are missing and the password is short.
      await tester.ensureVisible(find.text('الخطوة التالية'));
      await tester.tap(find.text('الخطوة التالية'));
      await tester.pumpAndSettle();

      expect(find.text('تحقق من الحقول المشار إليها.'), findsOneWidget);
      expect(find.text('هذا الحقل مطلوب.'), findsNWidgets(2));
      expect(find.text('الخطوة التالية'), findsOneWidget);
      expect(backend.requests.where((FakeRequest r) => r.path == '/auth/register'), isEmpty);
    });

    testWidgets('409 PHONE_ALREADY_REGISTERED offers to sign in with that number', (tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/register': _error(409, 'PHONE_ALREADY_REGISTERED',
            'An account already exists with this phone number.', <String, Object>{
          'phone': <String>[
            'An account already exists with this phone number. Sign in with this number, '
                'or contact the school if you forgot your password.',
          ],
        }),
      });
      backend.routes.addAll(_references);
      await _pump(
        tester,
        _install(
          SessionStore(fakeApi(backend)),
          references: ReferenceStore(fakeApi(backend)),
        ),
        const LoginScreen(),
      );
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Ines');
      await tester.enterText(find.byType(TextField).at(1), 'Benali');
      await tester.enterText(find.byType(TextField).at(2), '0555123456');
      await tester.enterText(find.byType(TextField).at(3), 'NovaSecure9!');
      await tester.enterText(find.byType(TextField).at(4), 'NovaSecure9!');
      await tester.tap(find.text('Next step'));
      await tester.pumpAndSettle();
      await _pick(tester, 0, '2AS');
      await _pick(tester, 2, 'Alger');
      await _pick(tester, 3, 'Bab Ezzouar');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create my space'));
      await tester.pumpAndSettle();

      // Sent exactly as typed (D-081).
      final FakeRequest register = backend.requests.last;
      expect(register.path, '/auth/register');
      expect((register.data! as Map<String, Object?>)['phone'], '0555123456');
      expect(find.text(_phoneTaken), findsOneWidget);
      expect(find.text('Sign in with this number'), findsOneWidget);

      await tester.tap(find.text('Sign in with this number'));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(_fieldText(tester, 0), '0555123456');
      expect(backend.requests.where((FakeRequest r) => r.path == '/auth/login'), isEmpty);
    });
  });

  testWidgets('the first screen shows sign in and create account without scrolling',
      (tester) async {
    final AppState state = _install(SessionStore(fakeApi(FakeBackend(
      const <String, FakeResponse>{},
    ))));
    // A small phone: 360 × 640.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(theme: NovaTheme.light, home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final Rect createTab = tester.getRect(find.text('Create account'));
    expect(createTab.bottom, lessThan(640));
    expect(find.text('Sign in'), findsNWidgets(2));

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    // The same switch leads back to sign-in.
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);

    // The full-width button under the form opens registration too.
    await tester.ensureVisible(find.text('Create a new account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a new account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  group('phone step (D-079)', () {
    Map<String, Object?> user(String phone, String? step) => <String, Object?>{
          'id': 9,
          'role': 'student',
          'phone': phone,
          'next_required_step': step,
          'student': <String, Object?>{'first_name': 'Ines', 'last_name': 'Benali'},
        };

    testWidgets('an account without a valid mobile enters its own number', (tester) async {
      final FakeBackend backend = FakeBackend(
        <String, FakeResponse>{},
        sequences: <String, List<FakeResponse>>{
          'PUT /auth/phone': <FakeResponse>[
            _error(409, 'PHONE_ALREADY_REGISTERED', 'An account already exists with this phone number.'),
            FakeResponse(200, <String, Object?>{'data': user('0666123456', null)}),
          ],
        },
      );
      final SessionStore session = SessionStore.seeded(
        HomeData.student,
        api: fakeApi(backend),
        user: user('ines@example.com', 'phone'),
      );
      await _pump(tester, _install(session), const AppGate());

      expect(find.byType(PhoneStepScreen), findsOneWidget);
      expect(find.text('Enter your phone number'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('Save my number'));
      await tester.pumpAndSettle();
      expect(find.text(_phoneInvalid), findsOneWidget);
      expect(backend.requests, isEmpty);

      // Taken: theirs (sign out, sign in with it) or a relative's.
      await tester.enterText(find.byType(TextField), '0555 12 34 56');
      await tester.tap(find.text('Save my number'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This number already has a NOVA account.'), findsOneWidget);
      expect(backend.requests.last.data, <String, String>{'phone': '0555 12 34 56'});

      await tester.enterText(find.byType(TextField), '0666123456');
      await tester.tap(find.text('Save my number'));
      await tester.pumpAndSettle();
      expect(backend.requests.last.path, '/auth/phone');
      expect(find.byType(PhoneStepScreen), findsNothing);
      expect(session.nextRequiredStep, isNull);
    });
  });

  test('signing in reloads the catalogue for the Student\'s level (D-083)', () async {
    final FakeBackend backend = FakeBackend(<String, FakeResponse>{
      'GET /auth/me': _error(401, 'UNAUTHENTICATED', 'Unauthenticated.'),
      'POST /auth/login': FakeResponse(200, <String, Object?>{
        'data': <String, Object?>{
          'id': 9,
          'role': 'student',
          'phone': '0555123456',
          'next_required_step': null,
          'student': <String, Object?>{'first_name': 'Ines', 'last_name': 'Benali'},
        },
      }),
      'POST /auth/logout': const FakeResponse(204),
      'GET /courses': const FakeResponse(200, <String, Object?>{'data': <Object>[]}),
      'GET /offers': const FakeResponse(200, <String, Object?>{'data': <Object>[]}),
      'GET /teachers': const FakeResponse(200, <String, Object?>{'data': <Object>[]}),
    });
    final AppState base = installFixtureApp();
    final SessionStore session = SessionStore(fakeApi(backend));
    AppState.seeded(
      session: session,
      catalog: CatalogStore(fakeApi(backend)),
      learning: base.learning,
      commerce: base.commerce,
      account: base.account,
      lang: NovaLang.en,
    );
    int catalogueLoads() =>
        backend.requests.where((FakeRequest r) => r.path == '/courses').length;

    await session.boot();
    expect(session.status, SessionStatus.signedOut);

    await session.login(phone: '0555123456', password: 'NovaSecure9!');
    await pumpEventQueue();
    expect(catalogueLoads(), 1);

    await session.logout();
    await pumpEventQueue();
    expect(catalogueLoads(), 2);
  });

  group('sign-in', () {
    testWidgets('403 DUPLICATE_ACCOUNT_DEACTIVATED names the masked number to use', (tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': _error(403, 'DUPLICATE_ACCOUNT_DEACTIVATED',
            'This account was closed because you already have a NOVA account.', <String, Object>{
          'phone': <String>['05 •• •• •• 30'],
        }),
      });
      await _pump(tester, _install(SessionStore(fakeApi(backend))), const LoginScreen());

      await tester.enterText(find.byType(TextField).at(0), ' 0555 12 34 56 ');
      await tester.enterText(find.byType(TextField).at(1), 'secret123');
      // The button, not the "Sign in" tab above the form.
      await tester.tap(find.text('Sign in').last);
      await tester.pumpAndSettle();

      // What the Student typed (trimmed, as Laravel's TrimStrings would).
      expect(backend.requests.last.data, <String, String>{
        'phone': '0555 12 34 56',
        'password': 'secret123',
      });
      expect(
        find.text(
          'This account was closed because you already have a NOVA account with your '
          'offers. Sign in to that account with your phone number (\u206605 •• •• •• 30\u2069). '
          'If you never chose a password for it, your password is your phone number. '
          'Forgot your password? Use “Forgot your password?” to receive a code by SMS or WhatsApp.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the masked number stays left-to-right inside Arabic', (tester) async {
      const ApiException closed = ApiException(
        status: 403,
        code: 'DUPLICATE_ACCOUNT_DEACTIVATED',
        message: 'This account was closed because you already have a NOVA account.',
        details: <String, Object>{
          'phone': <String>['05 •• •• •• 30'],
        },
      );
      final String arabic = await _text(tester, closed, NovaLang.ar);
      expect(arabic, startsWith('تم إغلاق هذا الحساب'));
      expect(arabic, contains('(\u206605 •• •• •• 30\u2069)'));
    });
  });

  group('password change', () {
    Future<FakeBackend> pumpChange(WidgetTester tester, Map<String, FakeResponse> routes) async {
      final FakeBackend backend = FakeBackend(routes);
      final Map<String, Object?> user = <String, Object?>{
        'id': 7,
        'role': 'student',
        'phone': '0555 12 34 56',
        'next_required_step': 'password_change',
        'student': <String, Object?>{'first_name': 'Ines', 'last_name': 'Benali'},
      };
      final SessionStore session = SessionStore.seeded(
        StudentProfile.fromUser(user),
        api: fakeApi(backend),
        user: user,
      );
      await _pump(tester, _install(session), const ChangePasswordScreen());
      return backend;
    }

    Future<void> submit(WidgetTester tester, String password, String confirmation) async {
      await tester.enterText(find.byType(TextField).at(0), password);
      await tester.enterText(find.byType(TextField).at(1), confirmation);
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
    }

    testWidgets('the phone, a short password and a mismatch are refused locally', (tester) async {
      final FakeBackend backend = await pumpChange(tester, <String, FakeResponse>{});

      await submit(tester, '+213555123456', '+213555123456');
      expect(find.text('Choose a password different from your phone number.'), findsOneWidget);

      await submit(tester, 'short', 'short');
      expect(find.text('Use at least 8 characters.'), findsOneWidget);

      await submit(tester, 'NovaSecure9!', 'NovaSecure8!');
      expect(find.text('The two passwords do not match.'), findsOneWidget);

      expect(backend.requests, isEmpty);
    });

    testWidgets('the server stays authoritative: its field error is shown', (tester) async {
      final FakeBackend backend = await pumpChange(tester, <String, FakeResponse>{
        'POST /auth/change-password': _error(422, 'VALIDATION_FAILED',
            'Choose a password different from the temporary password.', <String, Object>{
          'password': <String>['Choose a password different from the temporary password.'],
        }),
      });

      await submit(tester, 'NovaSecure9!', 'NovaSecure9!');

      expect(backend.requests.last.path, '/auth/change-password');
      expect(find.text('Choose a password different from the temporary password.'), findsOneWidget);
    });
  });

  testWidgets('ALREADY_OWNED_ON_OTHER_ACCOUNT is explained in the Student language', (tester) async {
    final FakeBackend backend = FakeBackend(<String, FakeResponse>{
      'POST /cart/items': _error(422, 'ALREADY_OWNED_ON_OTHER_ACCOUNT',
          'Another NOVA account with your phone number already has access to this. '
          'Sign in to that account instead of paying again.', <String, Object>{
        'product': <String>['Another NOVA account with your phone number already has access to this.'],
      }),
    });
    late ApiException refused;
    await tester.runAsync(() async {
      try {
        await fakeApi(backend).post('/cart/items', <String, int>{'course_id': 101});
      } on ApiException catch (error) {
        refused = error;
      }
    });

    expect(
      await _text(tester, refused, NovaLang.en),
      'Another NOVA account with your phone number already has this. Sign in to that '
      'account with your phone number instead of paying again, or contact the school.',
    );
    expect(
      await _text(tester, refused, NovaLang.fr),
      startsWith('Un autre compte NOVA avec ton numéro de téléphone'),
    );
  });
}
