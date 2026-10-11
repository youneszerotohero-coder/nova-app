import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/widgets/hero_style.dart';
import 'package:nova_mobile/core/widgets/pressable_scale.dart';
import 'package:nova_mobile/core/widgets/subject_chip.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/catalog/offers_catalog_screen.dart';
import 'package:nova_mobile/features/catalog/teachers_screen.dart';
import 'package:nova_mobile/features/catalog/units_catalog_screen.dart';
import 'package:nova_mobile/features/detail/course_detail_screen.dart';
import 'package:nova_mobile/features/detail/teacher_detail_screen.dart';
import 'package:nova_mobile/features/home/widgets/nova_product_card.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/shell/student_top_bar.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'nova_font_loader.dart';

// Public catalogue payloads in the backend's shape (list resources plus
// their `facets` and `audience`).
const Map<String, Object> _maya = {'id': 4, 'first_name': 'MAYA', 'last_name': 'ARABE'};
const Map<String, Object> _fares = {'id': 1, 'first_name': 'FARES', 'last_name': 'PHILO'};
const Map<String, Object> _amira = {'id': 2, 'first_name': 'AMIRA', 'last_name': 'ENGLISH'};
const Map<String, Object> _english = {'id': 5, 'name_fr': 'Langue anglaise', 'name_ar': 'اللغة الإنجليزية'};
const Map<String, Object> _philosophy = {'id': 19, 'name_fr': 'Philosophie', 'name_ar': 'الفلسفة'};
const Map<String, Object> _level3 = {'id': 2, 'code': '3AS', 'name_fr': 'Troisième année secondaire', 'name_ar': 'السنة الثالثة ثانوي'};
const Map<String, Object> _letters = {'id': 1, 'code': 'literature_philosophy', 'name_fr': 'Lettres et philosophie', 'name_ar': 'آداب وفلسفة'};
const String _arabicPack = 'Arabic — First Trimester';
const String _philosophyPack = 'Philosophy — First Trimester';
const String _philosophyCourse = 'Philosophy — Essay Method';
const String _englishCourse = 'English — Exam Skills';

Map<String, Object?> _page(List<Object> data, {Map<String, Object>? facets, Map<String, Object>? audience}) => <String, Object?>{
      'data': data,
      'meta': <String, Object>{'current_page': 1, 'last_page': 1, 'total': data.length},
      'facets': ?facets,
      'audience': ?audience,
    };

Map<String, Object> _facets({
  List<Object> levels = const <Object>[],
  List<Object> tracks = const <Object>[],
  List<Object> teachers = const <Object>[],
  List<Object> subjects = const <Object>[],
  Map<String, Object>? access,
  List<String>? types,
}) =>
    <String, Object>{
      'levels': levels,
      'subjects': subjects,
      'teachers': teachers,
      'tracks': tracks,
      'access': ?access,
      'types': ?types,
    };

Map<String, Object?> _course(int id, String title, Map<String, Object> teacher, Map<String, Object> subject, {bool free = false}) =>
    <String, Object?>{
      'id': id,
      'slug': 'course-$id',
      'title': title,
      'reference_price': '3000.00',
      'is_free': free,
      'individual_purchase_enabled': !free,
      'teacher': teacher,
      'subject': subject,
      'lessons_count': 2,
    };

Map<String, Object?> _offer(int id, String title, Map<String, Object> teacher, {String type = 'trimestre'}) => <String, Object?>{
      'id': id,
      'slug': 'offer-$id',
      'title': title,
      'type': type,
      'price': '2900.00',
      'courses_count': 0,
      'courses_reference_total': '0.00',
      'courses': const <Object>[],
      'teachers': <Object>[teacher],
    };

/// Two Units (a free one, a paid one) with every facet of the Units page.
Map<String, FakeResponse> _units([Map<String, FakeResponse> more = const <String, FakeResponse>{}]) => <String, FakeResponse>{
      'GET /courses': FakeResponse(
        200,
        _page(
          <Object>[_course(31, _philosophyCourse, _fares, _philosophy, free: true), _course(32, _englishCourse, _amira, _english)],
          facets: _facets(
            levels: <Object>[_level3],
            tracks: <Object>[_letters],
            teachers: <Object>[_fares, _amira],
            subjects: <Object>[_english, _philosophy],
            access: <String, Object>{'free': 1, 'paid': 1},
          ),
          audience: <String, Object>{'level': _level3, 'track': _letters},
        ),
      ),
      'GET /offers': FakeResponse(
        200,
        _page(
          <Object>[_offer(7, _arabicPack, _maya), _offer(6, _philosophyPack, _fares, type: 'dawra')],
          facets: _facets(teachers: <Object>[_maya, _fares], subjects: <Object>[_philosophy], types: <String>['dawra', 'trimestre']),
        ),
      ),
      'GET /teachers': FakeResponse(200, _page(const <Object>[])),
      ...more,
    };

void main() {
  setUpAll(loadNovaFonts);
  setUp(installFixtureApp);

  Finder inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

  /// A title drawn with its circled word (`*word*`), by its plain text.
  Finder heroTitle(String plain) => find.byWidgetPredicate((Widget w) => w is HeroTitle && HeroTitle.plain(w.text) == plain);

  /// The blue chip of an active filter (`.nvActiveChips`), by its label.
  Finder activeChip(String label) => find.byWidgetPredicate(
        (Widget w) => w is PressableScale && w.semanticLabel == label && w.child is Container,
      );

  /// Frames for two seconds: an empty state's orbit turns for ever, so
  /// the page never "settles" while it shows.
  Future<void> frames(WidgetTester tester) async {
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<String> queries(FakeBackend backend, String path) =>
      backend.requests.where((FakeRequest r) => r.path == path).map((FakeRequest r) => r.query).toList();

  /// [screen] over a catalogue served by [routes].
  Future<FakeBackend> pumpCatalog(WidgetTester tester, Widget screen, Map<String, FakeResponse> routes,
      {Map<String, List<FakeResponse>>? sequences}) async {
    tester.view.physicalSize = const Size(1170, 8100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final FakeBackend backend = FakeBackend(routes, sequences: sequences);
    final CatalogStore catalog = CatalogStore(fakeApi(backend));
    final AppState state = installFixtureApp(catalog: catalog);
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: NovaTheme.light, home: screen)));
    catalog.load();
    await frames(tester);
    return backend;
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    // The request leaves after a pause in the typing.
    await frames(tester);
  }

  group('Units catalogue (/courses)', () {
    testWidgets('the website band, the count with the Student\'s level, one card per Unit', (tester) async {
      await pumpCatalog(tester, const UnitsCatalogScreen(), _units());

      expect(find.byType(BackPill), findsOneWidget);
      expect(find.text('Learn one skill at a time'), findsOneWidget);
      expect(heroTitle('Find the unit that moves you forward'), findsOneWidget);
      expect(find.text('Search units, subjects or teachers…'), findsOneWidget);
      expect(find.text('2 Units found · Shown for your level and track: 3AS · Lettres et philosophie'), findsOneWidget);
      expect(find.byType(NovaProductCard), findsNWidgets(2));
      // Units only: the Offers have their own page.
      expect(find.text(_arabicPack), findsNothing);
    });

    testWidgets('the filter sheet offers the facets; a choice asks the backend and shows as a removable chip',
        (tester) async {
      final FakeBackend backend = await pumpCatalog(
        tester,
        const UnitsCatalogScreen(),
        _units(<String, FakeResponse>{
          'GET /courses?subject_ids[]=19&per_page=50&page=1':
              FakeResponse(200, _page(<Object>[_course(31, _philosophyCourse, _fares, _philosophy, free: true)])),
          'GET /courses?subject_ids[]=19&access=paid&per_page=50&page=1': FakeResponse(200, _page(const <Object>[])),
        }),
      );

      await tester.tap(find.bySemanticsLabel('Filters'));
      await frames(tester);

      // Free and paid Units both exist: the Access choice shows; Grade is open.
      expect(inSheet(find.text('Refine')), findsOneWidget);
      expect(inSheet(find.text('Access')), findsOneWidget);
      expect(inSheet(find.text('All levels')), findsOneWidget);
      expect(inSheet(find.text('Troisième année secondaire')), findsOneWidget);
      expect(inSheet(find.text('Track')), findsOneWidget);
      expect(inSheet(find.text('Maximum price')), findsOneWidget);
      expect(inSheet(find.text('Show 2 results')), findsOneWidget);
      // Subject is closed until opened.
      expect(inSheet(find.text('Philosophie')), findsNothing);
      await tester.tap(inSheet(find.text('Subject')));
      await frames(tester);

      await tester.tap(inSheet(find.text('Philosophie')));
      await frames(tester);
      expect(queries(backend, '/courses'), contains('subject_ids[]=19&per_page=50&page=1'));
      expect(inSheet(find.text('Show 1 results')), findsOneWidget);
      expect(
        tester.widget<SubjectChip>(find.byWidgetPredicate((Widget w) => w is SubjectChip && w.label == 'Philosophie')).selected,
        isTrue,
      );

      // Paid only, on top: nothing left.
      await tester.tap(inSheet(find.text('Paid')));
      await frames(tester);
      expect(queries(backend, '/courses'), contains('subject_ids[]=19&access=paid&per_page=50&page=1'));
      expect(inSheet(find.text('Show 0 results')), findsOneWidget);
      await tester.tap(inSheet(find.text('All')));
      await frames(tester);

      await tester.tap(inSheet(find.text('Show 1 results')));
      await frames(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(_philosophyCourse), findsOneWidget);
      expect(find.text(_englishCourse), findsNothing);
      expect(find.text('1 Unit found · Shown for your level and track: 3AS · Lettres et philosophie'), findsOneWidget);

      // The Filters button counts the choice; the blue chip removes it.
      expect(
        find.descendant(
          of: find.byWidgetPredicate((Widget w) => w is PressableScale && w.semanticLabel == 'Filters'),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tester.tap(activeChip('Philosophie'));
      await frames(tester);
      expect(find.text(_englishCourse), findsOneWidget);
      expect(activeChip('Philosophie'), findsNothing);
    });

    testWidgets('the sort asks the backend for the price order', (tester) async {
      final FakeBackend backend = await pumpCatalog(
        tester,
        const UnitsCatalogScreen(),
        _units(<String, FakeResponse>{
          'GET /courses?sort=price-high&per_page=50&page=1': FakeResponse(
            200,
            _page(<Object>[_course(32, _englishCourse, _amira, _english), _course(31, _philosophyCourse, _fares, _philosophy, free: true)]),
          ),
        }),
      );
      double top(String title) => tester.getTopLeft(find.text(title)).dy;
      expect(top(_philosophyCourse), lessThan(top(_englishCourse)));
      expect(find.text('Recommended'), findsOneWidget);

      await tester.tap(find.byTooltip('Sort by'));
      await frames(tester);
      await tester.tap(find.text('Price: high to low'));
      await frames(tester);

      expect(queries(backend, '/courses'), contains('sort=price-high&per_page=50&page=1'));
      expect(find.text('Price: high to low'), findsOneWidget);
      expect(top(_englishCourse), lessThan(top(_philosophyCourse)));
      // Sorting is not a filter.
      expect(find.text('2 Units found · Shown for your level and track: 3AS · Lettres et philosophie'), findsOneWidget);
    });

    testWidgets('the search asks the backend; with no match the filters can be reset', (tester) async {
      final FakeBackend backend = await pumpCatalog(
        tester,
        const UnitsCatalogScreen(),
        _units(<String, FakeResponse>{
          'GET /courses?search=philo&per_page=50&page=1':
              FakeResponse(200, _page(<Object>[_course(31, _philosophyCourse, _fares, _philosophy, free: true)])),
          'GET /courses?search=zzz&per_page=50&page=1': FakeResponse(200, _page(const <Object>[])),
        }),
      );

      await search(tester, 'philo');
      expect(queries(backend, '/courses'), contains('search=philo&per_page=50&page=1'));
      expect(find.text(_philosophyCourse), findsOneWidget);
      expect(find.text(_englishCourse), findsNothing);

      await search(tester, 'zzz');
      expect(find.text('No perfect match yet.'), findsOneWidget);
      expect(find.text('Try removing one filter or browse the full catalog.'), findsOneWidget);

      await tester.tap(find.text('Reset filters'));
      await frames(tester);
      expect(find.text(_englishCourse), findsOneWidget);
      expect(find.text(_philosophyCourse), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');

      await search(tester, 'philo');
      await tester.tap(find.bySemanticsLabel('Clear search'));
      await tester.pump(const Duration(milliseconds: 400));
      await frames(tester);
      expect(find.text(_englishCourse), findsOneWidget);
    });

    testWidgets('nothing published: the Units page points to the Offers', (tester) async {
      await pumpCatalog(tester, const UnitsCatalogScreen(), <String, FakeResponse>{
        'GET /courses': FakeResponse(200, _page(const <Object>[], facets: _facets())),
        'GET /offers': FakeResponse(200, _page(const <Object>[], facets: _facets())),
        'GET /teachers': FakeResponse(200, _page(const <Object>[])),
      });

      expect(heroTitle('Units are on their way.'), findsOneWidget);
      await tester.tap(find.text('Browse Offers'));
      await frames(tester);
      expect(find.byType(OffersCatalogScreen), findsOneWidget);
      expect(heroTitle('Offers are on their way.'), findsOneWidget);
    });

    testWidgets('a failed load says so and retries', (tester) async {
      await pumpCatalog(
        tester,
        const UnitsCatalogScreen(),
        _units(),
        sequences: <String, List<FakeResponse>>{
          'GET /courses': <FakeResponse>[
            const FakeResponse(500, <String, Object>{'error': <String, String>{'code': 'SERVER_ERROR', 'message': 'Boom'}}),
            _units()['GET /courses']!,
          ],
        },
      );

      expect(heroTitle('Units could not load.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await frames(tester);
      expect(find.text(_englishCourse), findsOneWidget);
    });
  });

  group('Offers catalogue (/bundles)', () {
    testWidgets('the website band; Offer type and Teacher filters ask the backend', (tester) async {
      final FakeBackend backend = await pumpCatalog(
        tester,
        const OffersCatalogScreen(),
        _units(<String, FakeResponse>{
          'GET /offers?teacher_ids[]=4&per_page=50&page=1': FakeResponse(200, _page(<Object>[_offer(7, _arabicPack, _maya)])),
        }),
      );

      expect(find.text('More learning, better value'), findsOneWidget);
      expect(heroTitle('Build your complete study plan.'), findsOneWidget);
      expect(find.text('Search offers and subjects…'), findsOneWidget);
      expect(find.text(_arabicPack), findsOneWidget);
      expect(find.text(_philosophyPack), findsOneWidget);
      expect(find.text(_philosophyCourse), findsNothing);

      await tester.tap(find.bySemanticsLabel('Filters'));
      await frames(tester);
      // Several Offer types: the type facet shows open; no Access on Offers.
      expect(inSheet(find.text('Offer type')), findsOneWidget);
      expect(inSheet(find.text('Dawra')), findsOneWidget);
      expect(inSheet(find.text('Trimester')), findsOneWidget);
      expect(inSheet(find.text('Access')), findsNothing);
      // The Teacher facet is open on the Offers page.
      await tester.tap(inSheet(find.text('MAYA ARABE')));
      await frames(tester);
      expect(queries(backend, '/offers'), contains('teacher_ids[]=4&per_page=50&page=1'));

      await tester.tap(inSheet(find.text('Show 1 results')));
      await frames(tester);
      expect(find.text(_arabicPack), findsOneWidget);
      expect(find.text(_philosophyPack), findsNothing);
      expect(find.text('1 Offers found · Shown for your level and track: 3AS · Lettres et philosophie'), findsOneWidget);
      expect(activeChip('MAYA ARABE'), findsOneWidget);
    });
  });

  group('cards and visitors', () {
    Future<void> pumpSeeded(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1170, 8100);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: AppState.instance, child: MaterialApp(key: UniqueKey(), theme: NovaTheme.light, home: screen)));
      await frames(tester);
    }

    testWidgets('a card opens the Student\'s own Unit, a Unit page or an Offer page', (tester) async {
      await pumpSeeded(tester, const UnitsCatalogScreen());
      await tester.tap(find.text('Physics — Mechanics Masterclass'));
      await frames(tester);
      expect(find.byType(LearnScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(LearnScreen))).pop();
      await frames(tester);

      await tester.tap(find.text('Mathematics — Problem Solving Lab'));
      await frames(tester);
      expect(tester.widget<CourseDetailScreen>(find.byType(CourseDetailScreen)).course?.id, 101);

      await pumpSeeded(tester, const OffersCatalogScreen());
      await tester.tap(find.text('Science Track — Complete Year'));
      await frames(tester);
      expect(tester.widget<CourseDetailScreen>(find.byType(CourseDetailScreen)).pack?.id, 201);
    });

    testWidgets('a visitor browses the catalogue read-only (D-134)', (tester) async {
      final FakeBackend backend = FakeBackend(_units());
      final AppState base = installFixtureApp();
      final AppState state = AppState.seeded(
        session: SessionStore(fakeApi(backend)),
        catalog: CatalogStore(fakeApi(backend)),
        learning: base.learning,
        commerce: base.commerce,
        account: base.account,
        lang: NovaLang.en,
      );
      AppState.instance = state;
      state.browseAsGuest(true);
      tester.view.physicalSize = const Size(1170, 8100);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: NovaTheme.light, home: const UnitsCatalogScreen())));
      state.catalog.load();
      await frames(tester);

      expect(state.guest, isTrue);
      expect(find.byType(BackPill), findsOneWidget);
      expect(find.text(_englishCourse), findsOneWidget);
      await tester.tap(find.text(_englishCourse));
      await frames(tester);
      expect(find.byType(CourseDetailScreen), findsOneWidget);
    });
  });

  group('Teachers (/teachers)', () {
    Future<void> pumpTeachers(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 8100);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: AppState.instance, child: MaterialApp(theme: NovaTheme.light, home: const TeachersScreen())));
      await frames(tester);
    }

    Finder tab(String label) => find.byWidgetPredicate((Widget w) => w is SubjectChip && w.tab && w.label == label);

    testWidgets('the band counts the teachers; subject tabs and the search narrow the cards', (tester) async {
      await pumpTeachers(tester);

      expect(find.text('Meet your teachers'), findsOneWidget);
      expect(find.text('Showing 5 teachers'), findsOneWidget);
      expect(tester.widget<SubjectChip>(tab('All')).selected, isTrue);
      for (final String subject in <String>['Mathematics', 'Physics', 'Science', 'Philosophy', 'English']) {
        expect(tab(subject), findsOneWidget);
      }

      await tester.tap(tab('Physics'));
      await frames(tester);
      expect(find.text('Showing 1 teachers'), findsOneWidget);
      expect(find.text('Amel Khaldi'), findsOneWidget);
      expect(find.text('Yacine Belkacem'), findsNothing);

      await tester.tap(tab('All'));
      await tester.enterText(find.byType(TextField), 'nadia');
      await frames(tester);
      expect(find.text('Showing 1 teachers'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await frames(tester);
      expect(heroTitle('No teacher matches'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await frames(tester);
      await tester.tap(find.text('Nadia Haddad'));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<TeacherDetailScreen>(find.byType(TeacherDetailScreen)).teacher.name, 'Nadia Haddad');
    });
  });
}
