import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/api_error_text.dart';
import 'package:nova_mobile/core/api/api_exception.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/account_store.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/account/settings_screen.dart';
import 'package:nova_mobile/features/auth/login_screen.dart';
import 'package:nova_mobile/features/auth/register_screen.dart';
import 'package:nova_mobile/features/auth/school_year_screen.dart';
import 'package:nova_mobile/features/detail/course_detail_screen.dart';
import 'package:nova_mobile/features/shell/app_gate.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';

/// The backend features released after the app's first version, as on
/// the website: codes by SMS or WhatsApp (D-093/D-096), filières per level
/// and the school-year confirmation (D-098), Units sold through Packs only
/// (D-091).

const String _challengeId = '6f1c3c1e-6c2a-4f55-9f43-2a1d7a3e8b10';

/// A code was requested (`202`); `resend_in` kept short for the tests.
const FakeResponse _challenge = FakeResponse(202, <String, Object>{
  'data': <String, Object>{'challenge_id': _challengeId, 'expires_in': 300, 'resend_in': 1},
});

FakeResponse _error(int status, String code, String message, [Object? details]) =>
    FakeResponse(status, <String, Object>{
      'error': <String, Object>{
        'code': code,
        'message': message,
        'details': ?details,
      },
    });

Map<String, Object?> _body(FakeRequest request) =>
    Map<String, Object?>.from(request.data! as Map<dynamic, dynamic>);

FakeRequest _sent(FakeBackend backend, String method, String path) =>
    backend.requests.lastWhere((FakeRequest r) => r.method == method && r.path == path);

AppState _install(
  SessionStore session, {
  ReferenceStore? references,
  CatalogStore? catalog,
  CommerceStore? commerce,
}) {
  final AppState base = installFixtureApp();
  final AppState state = AppState.seeded(
    session: session,
    catalog: catalog ?? base.catalog,
    learning: base.learning,
    commerce: commerce ?? base.commerce,
    account: base.account,
    references: references,
    lang: NovaLang.en,
  );
  AppState.instance = state;
  return state;
}

Future<void> _pump(WidgetTester tester, AppState state, Widget home) async {
  tester.view.physicalSize = const Size(1170, 7000);
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

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, int index, String option) async {
  await tester.tap(find.byType(DropdownButton<int>).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

/// `/levels` with the D-098 `track_ids`: 3AS has filières, 4AM none.
final Map<String, FakeResponse> _references = <String, FakeResponse>{
  'GET /levels': const FakeResponse(200, <String, Object>{
    'data': <Object>[
      <String, Object>{'id': 3, 'code': '3AS', 'name_fr': '3AS', 'name_ar': '3 ثانوي', 'track_ids': <int>[7, 8]},
      <String, Object>{'id': 4, 'code': '1AS', 'name_fr': '1AS', 'name_ar': '1 ثانوي', 'track_ids': <int>[9]},
      <String, Object>{'id': 5, 'code': '4AM', 'name_fr': '4AM', 'name_ar': '4 متوسط', 'track_ids': <int>[]},
    ],
  }),
  'GET /tracks': const FakeResponse(200, <String, Object>{
    'data': <Object>[
      <String, Object>{'id': 7, 'name_fr': 'Sciences expérimentales', 'name_ar': 'علوم تجريبية'},
      <String, Object>{'id': 8, 'name_fr': 'Math technique', 'name_ar': 'تقني رياضي'},
      <String, Object>{'id': 9, 'name_fr': 'Tronc commun sciences et technologie', 'name_ar': 'جذع مشترك علوم وتكنولوجيا'},
    ],
  }),
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

void main() {
  group('forgotten password by code (D-093/D-096)', () {
    testWidgets('phone and channel, code, new password, then sign-in with the number typed',
        (tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/password/forgot': _challenge,
        'POST /auth/password/forgot/verify': const FakeResponse(200, <String, Object>{
          'data': <String, Object>{'reset_token': 'reset-token-1', 'expires_in': 600},
        }),
        'POST /auth/password/forgot/reset': const FakeResponse(204),
      });
      await _pump(tester, _install(SessionStore(fakeApi(backend))), const LoginScreen());

      await _tap(tester, 'Forgot your password?');
      expect(find.text('Enter the phone number of your Student account. We send you a code by SMS or WhatsApp.'),
          findsOneWidget);

      // Any spelling of the mobile; Laravel receives 05XXXXXXXX.
      await tester.enterText(find.byType(TextField).first, '+213 555 12 34 56');
      await _tap(tester, 'WhatsApp');
      await _tap(tester, 'Send the code');

      expect(_body(_sent(backend, 'POST', '/auth/password/forgot')), <String, Object?>{
        'phone': '0555123456',
        'channel': 'whatsapp',
        'lang': 'en',
      });
      expect(find.textContaining('by WhatsApp. It is valid for 5 minutes.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '123456');
      await _tap(tester, 'Verify');
      expect(_body(_sent(backend, 'POST', '/auth/password/forgot/verify')), <String, Object?>{
        'challenge_id': _challengeId,
        'code': '123456',
      });

      // The new password is never the phone number (D-078).
      await tester.enterText(find.byType(TextField).at(0), '0555123456');
      await tester.enterText(find.byType(TextField).at(1), '0555123456');
      await _tap(tester, 'Save the new password');
      expect(find.text('Choose a password different from your phone number.'), findsOneWidget);
      expect(backend.requests.where((FakeRequest r) => r.path == '/auth/password/forgot/reset'), isEmpty);

      await tester.enterText(find.byType(TextField).at(0), 'NovaSecure9!');
      await tester.enterText(find.byType(TextField).at(1), 'NovaSecure9!');
      await _tap(tester, 'Save the new password');

      expect(_body(_sent(backend, 'POST', '/auth/password/forgot/reset')), <String, Object?>{
        'reset_token': 'reset-token-1',
        'password': 'NovaSecure9!',
        'password_confirmation': 'NovaSecure9!',
      });
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Your password was changed. Sign in with your new password.'), findsOneWidget);
      expect(_fieldText(tester, 0), '0555123456');
    });

    testWidgets('a wrong code says how many attempts are left; an expired step starts again',
        (tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/password/forgot': _challenge,
        'POST /auth/password/forgot/verify':
            _error(422, 'OTP_INVALID', 'This code is incorrect.', <String, Object>{'remaining_attempts': 2}),
      });
      await _pump(tester, _install(SessionStore(fakeApi(backend))), const LoginScreen());
      await _tap(tester, 'Forgot your password?');
      await tester.enterText(find.byType(TextField).first, '0555123456');
      await _tap(tester, 'Send the code');
      await tester.enterText(find.byType(TextField).first, '000000');
      await _tap(tester, 'Verify');

      expect(find.text('This code is incorrect. 2 attempt(s) left.'), findsOneWidget);
    });

    testWidgets('code errors are explained in the Student language', (tester) async {
      Future<String> text(Object error, NovaLang lang) async {
        final AppState state = installFixtureApp()..setLang(lang);
        late String value;
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(
              home: Builder(builder: (BuildContext context) {
                value = apiErrorText(context, error);
                return const SizedBox();
              }),
            ),
          ),
        );
        return value;
      }

      const ApiException busy = ApiException(
        status: 429,
        code: 'OTP_TOO_MANY_REQUESTS',
        message: 'Too many code requests.',
        details: <String, Object>{'retry_after': 1800},
      );
      expect(await text(busy, NovaLang.en), 'Too many code requests. Please retry later.');
      expect(await text(busy, NovaLang.ar), 'طلبات رموز كثيرة. أعد المحاولة لاحقاً.');
      expect(
        await text(const ApiException(status: 503, code: 'SMS_SERVICE_UNAVAILABLE', message: ''), NovaLang.fr),
        'Les codes ne peuvent pas être envoyés pour le moment. Réessaie plus tard.',
      );
    });
  });

  group('registration (D-093, D-098)', () {
    Future<FakeBackend> pumpRegister(WidgetTester tester, {required bool verification}) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        ..._references,
        'GET /auth/registration-options': FakeResponse(200, <String, Object>{
          'data': <String, Object>{'phone_verification_required': verification},
        }),
        'POST /auth/register/otp': _challenge,
        'POST /auth/register/otp/verify': const FakeResponse(200, <String, Object>{
          'data': <String, Object>{'verification_token': 'verified-1', 'expires_in': 600},
        }),
        'POST /auth/register': const FakeResponse(201, <String, Object>{'data': <String, Object>{}}),
      });
      await _pump(
        tester,
        _install(SessionStore(fakeApi(backend)), references: ReferenceStore(fakeApi(backend))),
        const RegisterScreen(),
      );
      return backend;
    }

    Future<void> fillForm(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).at(0), 'Ines');
      await tester.enterText(find.byType(TextField).at(1), 'Benali');
      await tester.enterText(find.byType(TextField).at(2), '0555123456');
      await _pick(tester, 0, '3AS');
      await _pick(tester, 1, 'Sciences expérimentales');
      await _pick(tester, 2, 'Alger');
      await _pick(tester, 3, 'Bab Ezzouar');
      final int passwords = find.byType(TextField).evaluate().length;
      await tester.enterText(find.byType(TextField).at(passwords - 2), 'NovaSecure9!');
      await tester.enterText(find.byType(TextField).at(passwords - 1), 'NovaSecure9!');
    }

    testWidgets('the phone is verified by a code before the account is created', (tester) async {
      final FakeBackend backend = await pumpRegister(tester, verification: true);
      await fillForm(tester);

      // Without the code step nothing is created.
      await _tap(tester, 'Create my space');
      expect(find.text('Verify your phone number with the code before creating your account.'), findsOneWidget);
      expect(backend.requests.where((FakeRequest r) => r.path == '/auth/register'), isEmpty);

      await _tap(tester, 'Send the code');
      expect(_body(_sent(backend, 'POST', '/auth/register/otp')), <String, Object?>{
        'phone': '0555123456',
        'channel': 'sms',
        'lang': 'en',
      });
      expect(find.text('A code was sent by SMS to \u20660555123456\u2069. It is valid for 5 minutes.'), findsOneWidget);

      // The code field sits right under the phone.
      await tester.enterText(find.byType(TextField).at(3), '654321');
      await _tap(tester, 'Verify');
      expect(find.text('Phone number verified.'), findsOneWidget);

      await _tap(tester, 'Create my space');
      final Map<String, Object?> register = _body(_sent(backend, 'POST', '/auth/register'));
      expect(register['phone_verification_token'], 'verified-1');
      expect(register['level_id'], 3);
      expect(register['track_id'], 7);
    });

    testWidgets('with the switch off no code is asked', (tester) async {
      final FakeBackend backend = await pumpRegister(tester, verification: false);
      expect(find.text('Verify your phone number'), findsNothing);
      await fillForm(tester);
      await _tap(tester, 'Create my space');

      final Map<String, Object?> register = _body(_sent(backend, 'POST', '/auth/register'));
      expect(register.containsKey('phone_verification_token'), isFalse);
      expect(backend.requests.where((FakeRequest r) => r.path == '/auth/register/otp'), isEmpty);
    });

    testWidgets('each level offers its own filières; a level without filière takes none',
        (tester) async {
      await pumpRegister(tester, verification: false);

      await _pick(tester, 0, '1AS');
      await tester.tap(find.byType(DropdownButton<int>).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Tronc commun sciences et technologie'), findsWidgets);
      expect(find.text('Sciences expérimentales'), findsNothing);
      await tester.tap(find.text('Tronc commun sciences et technologie').last);
      await tester.pumpAndSettle();

      // Another level drops a filière that is not its own.
      await _pick(tester, 0, '4AM');
      expect(find.text('Tronc commun sciences et technologie'), findsNothing);
      expect(find.text('Not required for this level'), findsOneWidget);
    });
  });

  testWidgets('a new school year asks the Student to confirm level and filière (D-098)',
      (tester) async {
    Map<String, Object?> user(String? step) => <String, Object?>{
          'id': 9,
          'role': 'student',
          'phone': '0555123456',
          'next_required_step': step,
          'student': <String, Object?>{
            'first_name': 'Ines',
            'last_name': 'Benali',
            'level': <String, Object>{'id': 3, 'name_fr': '3AS', 'name_ar': '3 ثانوي'},
            'track': <String, Object>{'id': 7, 'name_fr': 'Sciences expérimentales', 'name_ar': 'علوم تجريبية'},
          },
        };
    final FakeBackend backend = FakeBackend(<String, FakeResponse>{
      ..._references,
      'PUT /auth/school-year': _error(422, 'VALIDATION_FAILED', 'The given data was invalid.',
          <String, Object>{'track_id': <String>['The selected track does not belong to the selected level.']}),
    });
    final SessionStore session = SessionStore.seeded(
      StudentProfile.fromUser(user('school_year')),
      api: fakeApi(backend),
      user: user('school_year'),
    );
    await _pump(tester, _install(session, references: ReferenceStore(fakeApi(backend))), const AppGate());

    expect(find.byType(SchoolYearScreen), findsOneWidget);
    expect(find.text('Confirm your year and track'), findsOneWidget);
    // The current level and filière are preselected.
    expect(find.text('Sciences expérimentales'), findsOneWidget);

    await _pick(tester, 0, '4AM');
    await _tap(tester, 'Confirm');
    expect(_body(_sent(backend, 'PUT', '/auth/school-year')), <String, Object?>{
      'level_id': 5,
      'track_id': null,
    });
    expect(find.text('The selected track does not belong to the selected level.'), findsOneWidget);
  });

  testWidgets('Settings changes the password with a code sent to the Student (D-093)',
      (tester) async {
    final Map<String, Object?> user = <String, Object?>{
      'id': 9,
      'role': 'student',
      'phone': '0555123456',
      'next_required_step': null,
      'student': <String, Object?>{'first_name': 'Ines', 'last_name': 'Benali'},
    };
    final FakeBackend backend = FakeBackend(<String, FakeResponse>{
      'POST /auth/password/otp': _challenge,
      'PUT /auth/password': FakeResponse(200, <String, Object?>{'data': user}),
    });
    final SessionStore session = SessionStore.seeded(
      StudentProfile.fromUser(user),
      api: fakeApi(backend),
      user: user,
    );
    await _pump(tester, _install(session), const SettingsScreen());

    await _tap(tester, 'Send me a code');
    expect(_body(_sent(backend, 'POST', '/auth/password/otp')), <String, Object?>{
      'channel': 'sms',
      'lang': 'en',
    });

    await tester.enterText(find.byType(TextField).at(0), '246810');
    await tester.enterText(find.byType(TextField).at(1), 'NovaSecure9!');
    await tester.enterText(find.byType(TextField).at(2), 'NovaSecure9!');
    await _tap(tester, 'Change the password');

    expect(_body(_sent(backend, 'PUT', '/auth/password')), <String, Object?>{
      'challenge_id': _challengeId,
      'code': '246810',
      'password': 'NovaSecure9!',
      'password_confirmation': 'NovaSecure9!',
    });
    expect(find.text('Your password was changed. Your other devices were signed out.'), findsOneWidget);
    expect(session.signedIn, isTrue);
  });

  testWidgets('Settings deletes the account after the password is confirmed (D-118)', (tester) async {
    final Map<String, Object?> user = <String, Object?>{
      'id': 9,
      'role': 'student',
      'phone': '0555123456',
      'next_required_step': null,
      'student': <String, Object?>{'first_name': 'Ines', 'last_name': 'Benali'},
    };
    final FakeBackend backend = FakeBackend(<String, FakeResponse>{}, sequences: <String, List<FakeResponse>>{
      'DELETE /auth/account': <FakeResponse>[
        _error(422, 'VALIDATION_FAILED', 'The password is incorrect.', <String, Object>{
          'password': <String>['The password is incorrect.'],
        }),
        const FakeResponse(204),
      ],
    });
    final SessionStore session = SessionStore.seeded(
      StudentProfile.fromUser(user),
      api: fakeApi(backend),
      user: user,
    );
    await _pump(tester, _install(session), const SettingsScreen());

    await _tap(tester, 'Delete my account');
    expect(find.textContaining('This cannot be undone'), findsOneWidget);

    await _tap(tester, 'Delete my account permanently');
    expect(find.text('Type your password.'), findsOneWidget);
    expect(backend.requests.where((FakeRequest r) => r.path == '/auth/account'), isEmpty);

    await tester.enterText(find.byType(TextField).last, 'wrong-pass');
    await _tap(tester, 'Delete my account permanently');
    expect(find.text('Wrong password.'), findsOneWidget);
    expect(session.signedIn, isTrue);

    await tester.enterText(find.byType(TextField).last, 'NovaSecure9!');
    await _tap(tester, 'Delete my account permanently');
    expect(_body(_sent(backend, 'DELETE', '/auth/account')), <String, Object?>{'password': 'NovaSecure9!'});
    expect(session.signedIn, isFalse);
    expect(session.endedReason, SessionStore.accountDeleted);
  });

  group('Units sold through Packs only (D-091)', () {
    Map<String, Object?> course(List<Object> offers) => <String, Object?>{
          'id': 40,
          'slug': 'course-40',
          'title': 'Physics — Mechanics',
          'reference_price': '3000.00',
          'is_free': false,
          'individual_purchase_enabled': false,
          'offer_price_from': '2500.00',
          'teacher': const <String, Object>{'id': 2, 'first_name': 'AMIRA', 'last_name': 'PHYS'},
          'subject': const <String, Object>{'id': 3, 'name_fr': 'Physique', 'name_ar': 'فيزياء'},
          'lessons_count': 2,
          'offers': offers,
        };
    const Map<String, Object> annual = <String, Object>{
      'id': 9, 'slug': 'offer-9', 'title': 'Physics — Annual', 'type': 'annual', 'price': '2500.00',
    };
    const Map<String, Object> term = <String, Object>{
      'id': 11, 'slug': 'offer-11', 'title': 'Physics — First Trimester', 'type': 'trimestre', 'price': '4000.00',
    };

    Future<FakeBackend> pumpDetail(WidgetTester tester, List<Object> offers) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /courses/course-40': FakeResponse(200, <String, Object?>{'data': course(offers)}),
        'POST /cart/items': const FakeResponse(200, <String, Object>{
          'data': <Object>[
            <String, Object>{'kind': 'offer', 'id': 11, 'title': 'Physics — First Trimester', 'price': '4000.00'},
          ],
        }),
      });
      final AppState state = _install(
        SessionStore.seeded(HomeData.student),
        catalog: CatalogStore(fakeApi(backend)),
        commerce: CommerceStore(fakeApi(backend)),
      );
      await _pump(
        tester,
        state,
        CourseDetailScreen(course: Course.fromJson(Map<String, dynamic>.of(course(offers)))),
      );
      return backend;
    }

    test('the public payload says how the Unit is sold', () {
      final Course packOnly = Course.fromJson(Map<String, dynamic>.of(course(<Object>[annual, term])));
      expect(packOnly.packOnly, isTrue);
      expect(packOnly.offerPriceFrom, 2500);
      expect(packOnly.cataloguePrice, 2500);
      expect(packOnly.packs.map((CoursePack p) => p.id), <int>[9, 11]);

      final Course noPack = Course.fromJson(<String, dynamic>{
        ...course(const <Object>[]),
        'offer_price_from': null,
      });
      expect(noPack.cataloguePrice, isNull);
    });

    testWidgets('with several Packs the Student picks the one added to the cart', (tester) async {
      final FakeBackend backend = await pumpDetail(tester, <Object>[annual, term]);

      expect(find.text('In Packs from'), findsOneWidget);
      expect(find.text('Sold within 2 Packs'), findsOneWidget);

      await _tap(tester, 'Add the Pack');
      expect(find.text('Choose a Pack'), findsOneWidget);
      expect(backend.requests.where((FakeRequest r) => r.path == '/cart/items'), isEmpty);

      await _tap(tester, 'Physics — First Trimester');
      expect(_body(_sent(backend, 'POST', '/cart/items')), <String, Object?>{'offer_id': 11});
    });

    testWidgets('with one Pack it is added at once; without any nothing is sold', (tester) async {
      final FakeBackend backend = await pumpDetail(tester, <Object>[term]);
      expect(find.text('Sold within the Pack Physics — First Trimester'), findsOneWidget);

      await _tap(tester, 'Add the Pack');
      expect(find.text('Choose a Pack'), findsNothing);
      expect(_body(_sent(backend, 'POST', '/cart/items')), <String, Object?>{'offer_id': 11});
    });

    testWidgets('without a Pack on sale the Unit cannot be bought', (tester) async {
      await pumpDetail(tester, const <Object>[]);
      expect(find.text('Available through offers only'), findsOneWidget);
      expect(find.text('Add the Pack'), findsNothing);
      expect(find.text('Buy now'), findsNothing);
    });
  });
}
