import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/api_exception.dart';
import 'package:nova_mobile/core/api/nova_api.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/session_store.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/api/$name').readAsStringSync())
        as Map<String, dynamic>;

/// A `UserResource` in the backend's shape (see backend
/// `UserResource.php` / `StudentResource.php`).
Map<String, Object?> _user({String role = 'student', String? step}) =>
    <String, Object?>{
      'id': 7,
      'role': role,
      'phone': '0555123456',
      'next_required_step': step,
      'student': <String, Object?>{
        'first_name': 'Ines',
        'last_name': 'Benali',
        'referral_code': 'ABCDEFGH12345678',
        'level': <String, Object>{'id': 2, 'code': '3AS', 'name_fr': 'Troisième année secondaire', 'name_ar': 'السنة الثالثة ثانوي'},
        'track': null,
        'wilaya': <String, Object>{'id': 16, 'code': '16', 'name_fr': 'Alger', 'name_ar': 'الجزائر'},
        'commune': null,
      },
    };

void main() {
  // Reference names resolve in the app language: pin English (the app
  // itself starts in Arabic).
  setUp(installFixtureApp);

  group('NovaApi (the SPA contract)', () {
    test('writes fetch a CSRF cookie first and echo it decoded', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _user()}),
      });
      final NovaApi api = fakeApi(backend);

      await api.post('/auth/login', <String, String>{'phone': 'x', 'password': 'y'});

      expect(backend.requests.map((FakeRequest r) => '${r.method} ${r.path}'),
          <String>['GET /auth/csrf-cookie', 'POST /auth/login']);
      final FakeRequest login = backend.requests.last;
      expect(login.headers['X-XSRF-TOKEN'], 'eyJpdiI6IkFCQyJ9==');
      expect(login.headers['Accept'], 'application/json');
    });

    test('the CSRF cookie is fetched once, not before every write (D-071)', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /cart/items': const FakeResponse(201, <String, Object?>{'data': <String, Object?>{}}),
      });
      final NovaApi api = fakeApi(backend);

      await api.post('/cart/items', <String, int>{'product_id': 1});
      await api.post('/cart/items', <String, int>{'product_id': 2});

      expect(backend.requests.map((FakeRequest r) => '${r.method} ${r.path}'),
          <String>['GET /auth/csrf-cookie', 'POST /cart/items', 'POST /cart/items']);
      expect(backend.requests.last.headers['X-XSRF-TOKEN'], 'eyJpdiI6IkFCQyJ9==');
    });

    test('a 419 fetches a fresh CSRF cookie and retries once', () async {
      final FakeBackend backend = FakeBackend(
        <String, FakeResponse>{},
        sequences: <String, List<FakeResponse>>{
          'POST /cart/items': <FakeResponse>[
            const FakeResponse(419, <String, Object>{
              'error': <String, String>{'code': 'HTTP_419', 'message': 'CSRF token mismatch.'},
            }),
            const FakeResponse(201, <String, Object?>{'data': <String, Object?>{}}),
          ],
        },
      );
      final NovaApi api = fakeApi(backend);

      await api.post('/cart/items', <String, int>{'product_id': 1});

      expect(backend.requests.map((FakeRequest r) => '${r.method} ${r.path}'), <String>[
        'GET /auth/csrf-cookie',
        'POST /cart/items',
        'GET /auth/csrf-cookie',
        'POST /cart/items',
      ]);
    });

    test('a replaced session is noticed by the /auth/session fallback', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /auth/session': const FakeResponse(200, <String, Object?>{
          'data': <String, Object?>{'session_fingerprint': 'other-device'},
        }),
      });
      final SessionStore session = SessionStore.seeded(
        StudentProfile.fromUser(_user()),
        api: fakeApi(backend),
        user: <String, Object?>{..._user(), 'session_fingerprint': 'this-device'},
      );

      await session.checkSession();

      expect(session.signedIn, isFalse);
      expect(session.endedReason, ApiException.sessionReplaced);
    });

    test('reads send no CSRF round trip', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /courses': FakeResponse(200, _fixture('courses.json')),
      });
      await fakeApi(backend).get('/courses');
      expect(backend.requests.single.path, '/courses');
    });

    test('the error envelope becomes an ApiException with field errors', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/register': const FakeResponse(422, <String, Object>{
          'error': <String, Object>{
            'code': 'VALIDATION_FAILED',
            'message': 'The given data was invalid.',
            'details': <String, Object>{
              'phone': <String>['The phone has already been taken.'],
            },
          },
        }),
      });

      await expectLater(
        fakeApi(backend).post('/auth/register', <String, String>{}),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.status, 'status', 422)
            .having((ApiException e) => e.code, 'code', 'VALIDATION_FAILED')
            .having((ApiException e) => e.fieldErrors['phone'], 'phone',
                'The phone has already been taken.')),
      );
    });

    test('a 401 on an authenticated call reports the lost session', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /cart': const FakeResponse(401, <String, Object>{
          'error': <String, String>{
            'code': 'SESSION_REPLACED',
            'message': 'Signed in on another device.',
          },
        }),
      });
      final NovaApi api = fakeApi(backend);
      ApiException? lost;
      api.onSessionLost = (ApiException e) => lost = e;

      await expectLater(api.get('/cart'), throwsA(isA<ApiException>()));
      expect(lost?.code, ApiException.sessionReplaced);
    });

    test('array filters use Laravel bracket syntax', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /courses': FakeResponse(200, _fixture('courses.json')),
      });
      await fakeApi(backend).get('/courses', query: <String, Object?>{
        'teacher_ids': <int>[1, 4],
        'search': null,
      });
      // Nulls are dropped; lists repeat the bracketed key.
      expect(backend.requests.single.query, 'teacher_ids[]=1&teacher_ids[]=4');
    });
  });

  group('SessionStore', () {
    test('signs in a Student and exposes the onboarding step', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{
          'data': _user(step: 'password_change'),
        }),
      });
      final SessionStore session = SessionStore(fakeApi(backend));

      await session.login(phone: ' 0555123456 ', password: 'secret123');

      expect(session.signedIn, isTrue);
      expect(session.nextRequiredStep, 'password_change');
      expect(session.profile?.fullName, 'Ines Benali');
      expect(session.profile?.wilaya, 'Alger');
      expect(backend.requests.last.data, <String, String>{
        'phone': '0555123456',
        'password': 'secret123',
      });
    });

    test('refuses admin accounts and ends their session', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /auth/login': FakeResponse(200, <String, Object?>{'data': _user(role: 'admin')}),
        'POST /auth/logout': const FakeResponse(204),
      });
      final SessionStore session = SessionStore(fakeApi(backend));

      await expectLater(
        session.login(phone: 'admin', password: 'x'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'STUDENT_ONLY')),
      );
      expect(session.signedIn, isFalse);
      expect(backend.requests.any((FakeRequest r) => r.path == '/auth/logout'), isTrue);
    });

    test('a replaced session signs the Student out and says why', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /auth/me': FakeResponse(200, <String, Object?>{'data': _user()}),
        'GET /cart': const FakeResponse(401, <String, Object>{
          'error': <String, String>{'code': 'SESSION_REPLACED', 'message': '…'},
        }),
      });
      final NovaApi api = fakeApi(backend);
      final SessionStore session = SessionStore(api);
      await session.boot();
      expect(session.signedIn, isTrue);

      await expectLater(api.get('/cart'), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);

      expect(session.status, SessionStatus.signedOut);
      expect(session.endedReason, ApiException.sessionReplaced);
    });
  });

  group('Production response shapes', () {
    test('courses, offers and teachers parse from real /api/v1 payloads', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /courses': FakeResponse(200, _fixture('courses.json')),
        'GET /offers': FakeResponse(200, _fixture('offers.json')),
        'GET /teachers': FakeResponse(200, _fixture('teachers.json')),
      });
      final CatalogStore catalog = CatalogStore(fakeApi(backend));

      await catalog.load();

      expect(catalog.state, LoadState.ready);
      final Course course = catalog.courses.first;
      expect(course.id, 4);
      expect(course.isFree, isTrue);
      expect(course.price, 2500); // "2500.00" decimal string
      expect(course.teacher, 'FARES PHILO');
      expect(course.subject, 'Philosophie'); // name_fr for the English UI
      expect(course.lessonsCount, 2);

      final Pack offer = catalog.offers.firstWhere((Pack p) => p.id == 6);
      expect(offer.price, 2500);
      expect(offer.items.single.courseSlug, 'course-1fares');
      expect(offer.image, startsWith('https://'));
      expect(catalog.teachers, isNotEmpty);
      expect(catalog.teachers.first.subjects, isNotEmpty);

      // Filter options: both catalogues' facets, each id once, with the
      // directory photo when the Teachers list has one.
      expect(catalog.teacherFacets.map((Teacher t) => t.id), <int>[1, 4, 2, 3]);
      expect(catalog.teacherFacets.first.name, 'FARES PHILO');
      expect(catalog.teacherFacets.first.photo, startsWith('https://'));
      expect(catalog.subjectFacets.map((RefItem s) => s.id), <int>[19, 5]);
      expect(catalog.subjectFacets.last.name, 'Langue anglaise');
    });

    test('cart items and quotes keep the server amounts', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'POST /cart/items': const FakeResponse(201, <String, Object>{
          'data': <Object>[
            <String, Object?>{
              'key': 'offer:6', 'kind': 'offer', 'id': 6, 'slug': 'fares-1er-trimestre',
              'title': 'عرض الفصل الاول', 'price': '2500.00', 'image': null,
              'meta': 'Offer · 1 Courses',
            },
          ],
        }),
        'POST /checkout/quote': const FakeResponse(200, <String, Object>{
          'data': <String, Object>{
            'base_amount': '2500.00', 'overlap_credit': '0.00',
            'referral_discount': '0.00', 'promo_discount': '300.00',
            'points_discount': '0.00', 'final_amount': '2200.00',
            'points_used': 0, 'points_balance': 0, 'max_points_usable': 0,
            'points_redemption_enabled': false,
          },
        }),
      });
      final CommerceStore commerce = CommerceStore(fakeApi(backend));

      await commerce.add(kind: 'offer', id: 6);
      final CartItem item = commerce.items.single;
      expect(item.id, 'offer:6');
      expect(item.productBody, <String, Object>{'offer_id': 6});

      final Quote quote = await commerce.quote(item, discountCode: ' BAC26 ');
      expect(quote.finalAmount, 2200);
      expect(quote.promoDiscount, 300);
      // The website's body: `points_to_use` is always sent, 0 by default.
      expect(backend.requests.last.data, <String, Object>{
        'offer_id': 6,
        'discount_code': 'BAC26',
        'points_to_use': 0,
      });
    });

    test('orders map payment state the way the web account page does', () {
      Order order(String status, String? payment) => Order.fromJson(<String, Object?>{
            'id': 1,
            'order_number': 'NV-1',
            'status': status,
            'final_amount': '2500.00',
            'items': <Object>[<String, Object?>{'title': 'X', 'offer_id': 6}],
            'latest_payment': payment == null
                ? null
                : <String, Object?>{'method': 'ccp', 'status': payment},
            'quote_expires_at': DateTime.now().add(const Duration(minutes: 20)).toIso8601String(),
          });

      expect(order('paid', 'paid').status, OrderStatus.paid);
      expect(order('awaiting_payment', null).status, OrderStatus.awaiting);
      expect(order('awaiting_payment', null).payable, isTrue);
      expect(order('awaiting_payment', 'pending_review').status, OrderStatus.pendingReview);
      expect(order('awaiting_payment', 'pending_review').payable, isFalse);
      expect(order('expired', null).status, OrderStatus.expired);
      expect(order('paid', 'paid').kind, 'Offer');
    });
  });
}
