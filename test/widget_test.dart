import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/utils/format_price.dart';
import 'package:nova_mobile/core/utils/search_text.dart';
import 'package:nova_mobile/core/widgets/pressable_scale.dart';
import 'package:nova_mobile/core/widgets/subject_chip.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/features/detail/course_detail_screen.dart';
import 'package:nova_mobile/features/detail/teacher_detail_screen.dart';
import 'package:nova_mobile/features/explore/explore_screen.dart';
import 'package:nova_mobile/features/home/home_screen.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/main.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';

// Public catalogue payloads in the backend's shape (list resources plus
// their `facets`), for the Explore filters.
const Map<String, Object> _maya = {'id': 4, 'first_name': 'MAYA', 'last_name': 'ARABE'};
const Map<String, Object> _fares = {'id': 1, 'first_name': 'FARES', 'last_name': 'PHILO'};
const Map<String, Object> _amira = {'id': 2, 'first_name': 'AMIRA', 'last_name': 'ENGLISH'};
const Map<String, Object> _english = {'id': 5, 'name_fr': 'Langue anglaise', 'name_ar': 'اللغة الإنجليزية'};
const Map<String, Object> _philosophy = {'id': 19, 'name_fr': 'Philosophie', 'name_ar': 'الفلسفة'};
const String _arabicPack = 'Arabic — First Trimester';
const String _philosophyPack = 'Philosophy — First Trimester';
const String _philosophyCourse = 'Philosophy — Essay Method';
const String _englishCourse = 'English — Exam Skills';

Map<String, Object?> _page(List<Object> data, {Map<String, Object>? facets}) => <String, Object?>{
      'data': data,
      'meta': <String, Object>{'current_page': 1, 'last_page': 1, 'total': data.length},
      'facets': ?facets,
    };

Map<String, Object> _facets({
  List<Object> teachers = const <Object>[],
  List<Object> subjects = const <Object>[],
}) =>
    <String, Object>{
      'levels': const <Object>[],
      'subjects': subjects,
      'teachers': teachers,
      'tracks': const <Object>[],
    };

Map<String, Object?> _course(
  int id,
  String title,
  Map<String, Object> teacher,
  Map<String, Object> subject, {
  bool free = false,
}) =>
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

Map<String, Object?> _offer(int id, String title, Map<String, Object> teacher) => <String, Object?>{
      'id': id,
      'slug': 'offer-$id',
      'title': title,
      'type': 'trimestre',
      'price': '2900.00',
      'courses_count': 0,
      'courses_reference_total': '0.00',
      'courses': const <Object>[],
      'teachers': <Object>[teacher],
    };

/// Loads the bundled Inter families so text metrics match production.
Future<void> _loadNovaFonts() async {
  const Map<String, List<String>> families = {
    'Inter': [
      'Inter-Regular.ttf',
      'Inter-Medium.ttf',
      'Inter-SemiBold.ttf',
      'Inter-Bold.ttf',
    ],
    'InterDisplay': [
      'InterDisplay-SemiBold.ttf',
      'InterDisplay-Bold.ttf',
    ],
  };
  for (final MapEntry<String, List<String>> family in families.entries) {
    final FontLoader loader = FontLoader(family.key);
    for (final String file in family.value) {
      loader.addFont(
        Future<ByteData>.value(
          await rootBundle.load('assets/fonts/$file'),
        ),
      );
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadNovaFonts);
  setUp(installFixtureApp);

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 8100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NovaApp());
    await tester.pumpAndSettle();
  }

  testWidgets('home renders greeting and promotional sections', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('nova'), findsOneWidget);
    expect(find.text('Hello, ${HomeData.studentName}'), findsOneWidget);
    expect(find.text(HomeData.greetingSubtitle), findsOneWidget);
    // Search and filtering live on Explore now.
    expect(find.text(HomeData.searchHint), findsNothing);
    expect(find.text('Popular courses'), findsOneWidget);
    expect(find.text('Our teachers'), findsOneWidget);
  });

  testWidgets('pack banner carousel advances with next and prev', (
    tester,
  ) async {
    await pumpApp(tester);

    Rect slideRect(String packName) => tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is PressableScale &&
                widget.semanticLabel == 'Open pack $packName',
          ),
        );

    // The second banner only peeks from the right edge.
    expect(
      slideRect('Maths + Physics Power Pack').left,
      greaterThan(300),
    );

    await tester.tap(find.bySemanticsLabel('Next pack'));
    await tester.pumpAndSettle();

    // Now the second banner is the active page and the first is gone.
    expect(slideRect('Maths + Physics Power Pack').left, lessThan(100));
    expect(slideRect('Science Track — Complete Year').left, lessThan(-100));

    await tester.tap(find.bySemanticsLabel('Previous pack'));
    await tester.pumpAndSettle();

    expect(
      slideRect('Science Track — Complete Year').left,
      lessThan(50),
    );
  });

  testWidgets('pack banner arrows mirror in Arabic', (tester) async {
    final AppState state = AppState.instance;
    state.setLang(NovaLang.ar);
    addTearDown(() => state.setLang(NovaLang.en));
    await pumpApp(tester);

    final double screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    Rect slideRect(String packName) => tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is PressableScale &&
                widget.semanticLabel == 'Open pack $packName',
          ),
        );
    Rect arrowRect(String label) =>
        tester.getRect(find.bySemanticsLabel(label));

    // Right to left: "previous" on the right edge, "next" on the left,
    // matching the second banner peeking from the left.
    expect(arrowRect('Previous pack').left, greaterThan(screenWidth / 2));
    expect(arrowRect('Next pack').right, lessThan(screenWidth / 2));
    expect(slideRect('Maths + Physics Power Pack').right, lessThan(100));

    await tester.tap(find.bySemanticsLabel('Next pack'));
    await tester.pumpAndSettle();

    expect(
      slideRect('Maths + Physics Power Pack').right,
      greaterThan(screenWidth - 100),
    );
    expect(
      slideRect('Science Track — Complete Year').right,
      greaterThan(screenWidth + 100),
    );
  });

  testWidgets('menu opens and switches tabs', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('My courses'), findsOneWidget);

    await tester.tap(find.text('My courses'));
    await tester.pumpAndSettle();

    expect(find.text('My courses'), findsOneWidget);
    expect(find.text('Physics — Mechanics Masterclass'), findsOneWidget);
  });

  testWidgets('menu docks to the right edge in Arabic', (tester) async {
    final AppState state = AppState.instance;
    state.setLang(NovaLang.ar);
    addTearDown(() => state.setLang(NovaLang.en));
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Menu'));
    await tester.pumpAndSettle();

    final double screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final Rect panel = tester.getRect(
      find.byWidgetPredicate(
        (Widget w) => w is Container && w.constraints?.maxWidth == 316,
      ),
    );
    expect(panel.right, greaterThan(screenWidth - 20));
    expect(panel.left, greaterThan(0));
  });

  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byType(BottomSheet), matching: finder);

  /// Explore over a catalogue served by [routes] in the backend's shape,
  /// so the filters meet real facets and backend-filtered Offers.
  Future<FakeBackend> pumpExplore(
    WidgetTester tester,
    Map<String, FakeResponse> routes,
  ) async {
    tester.view.physicalSize = const Size(1170, 8100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final FakeBackend backend = FakeBackend(routes);
    final CatalogStore catalog = CatalogStore(fakeApi(backend));
    final AppState state = installFixtureApp(catalog: catalog);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: NovaTheme.light,
          home: const Scaffold(body: ExploreScreen()),
        ),
      ),
    );
    catalog.load();
    await tester.pumpAndSettle();
    return backend;
  }

  List<String> offerQueries(FakeBackend backend) => backend.requests
      .where((FakeRequest r) => r.path == '/offers')
      .map((FakeRequest r) => r.query)
      .toList();

  testWidgets(
      'with no listed Course the filter rails come from the facets and a '
      'teacher asks the backend for packs', (tester) async {
    final FakeBackend backend = await pumpExplore(tester, <String, FakeResponse>{
      // Production today: paid Courses are only sold inside Offers.
      'GET /courses': FakeResponse(200, _page(const <Object>[], facets: _facets())),
      'GET /offers': FakeResponse(
        200,
        _page(
          <Object>[_offer(7, _arabicPack, _maya), _offer(6, _philosophyPack, _fares)],
          facets: _facets(teachers: <Object>[_maya, _fares], subjects: <Object>[_english, _philosophy]),
        ),
      ),
      'GET /offers?teacher_ids[]=4&per_page=50&page=1':
          FakeResponse(200, _page(<Object>[_offer(7, _arabicPack, _maya)])),
      'GET /teachers': FakeResponse(200, _page(const <Object>[])),
    });

    await tester.tap(find.bySemanticsLabel('Filters'));
    await tester.pumpAndSettle();

    expect(inSheet(find.text('MAYA')), findsOneWidget);
    expect(inSheet(find.text('FARES')), findsOneWidget);
    expect(inSheet(find.text('Langue anglaise')), findsOneWidget);
    expect(inSheet(find.text('Philosophie')), findsOneWidget);
    expect(find.text('Show 2 results'), findsOneWidget);

    await tester.tap(inSheet(find.text('MAYA')));
    await tester.pumpAndSettle();

    // D-056: the backend decides which packs a Teacher matches.
    expect(offerQueries(backend), contains('teacher_ids[]=4&per_page=50&page=1'));
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Show 1 result'));
    await tester.pumpAndSettle();

    expect(find.text(_arabicPack), findsOneWidget);
    expect(find.text(_philosophyPack), findsNothing);
  });

  testWidgets(
      'courses filter locally by teacher and subject id, packs follow the '
      'backend, and the apply count adds both', (tester) async {
    final FakeBackend backend = await pumpExplore(tester, <String, FakeResponse>{
      'GET /courses': FakeResponse(
        200,
        _page(
          <Object>[
            _course(31, _philosophyCourse, _fares, _philosophy, free: true),
            _course(32, _englishCourse, _amira, _english),
          ],
          facets: _facets(teachers: <Object>[_fares, _amira], subjects: <Object>[_english, _philosophy]),
        ),
      ),
      'GET /offers': FakeResponse(
        200,
        _page(
          <Object>[_offer(7, _arabicPack, _maya), _offer(6, _philosophyPack, _fares)],
          facets: _facets(teachers: <Object>[_maya, _fares], subjects: <Object>[_english, _philosophy]),
        ),
      ),
      'GET /offers?subject_ids[]=19&per_page=50&page=1':
          FakeResponse(200, _page(<Object>[_offer(6, _philosophyPack, _fares)])),
      'GET /offers?teacher_ids[]=2&subject_ids[]=19&per_page=50&page=1':
          FakeResponse(200, _page(const <Object>[])),
      'GET /offers?teacher_ids[]=2&per_page=50&page=1':
          FakeResponse(200, _page(const <Object>[])),
      'GET /teachers': FakeResponse(200, _page(const <Object>[])),
    });

    // The Explore subject rail shares its selection with the sheet.
    await tester.tap(find.byWidgetPredicate(
      (Widget w) => w is SubjectChip && w.label == 'Philosophie',
    ));
    await tester.pumpAndSettle();

    expect(offerQueries(backend), contains('subject_ids[]=19&per_page=50&page=1'));
    expect(find.text(_philosophyCourse), findsOneWidget);
    expect(find.text(_englishCourse), findsNothing);
    expect(find.text(_philosophyPack), findsOneWidget);
    expect(find.text(_arabicPack), findsNothing);

    await tester.tap(find.bySemanticsLabel('Filters'));
    await tester.pumpAndSettle();
    // Teachers of both catalogues, each once.
    expect(inSheet(find.text('FARES')), findsOneWidget);
    expect(inSheet(find.text('AMIRA')), findsOneWidget);
    expect(inSheet(find.text('MAYA')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Show 2 results'), findsOneWidget);

    // "Only free" narrows Courses only: /offers has no access filter.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Show 2 results'), findsOneWidget);

    await tester.tap(inSheet(find.text('AMIRA')));
    await tester.pumpAndSettle();
    expect(
      offerQueries(backend),
      contains('teacher_ids[]=2&subject_ids[]=19&per_page=50&page=1'),
    );
    expect(find.text('No results match'), findsOneWidget);

    // Teacher alone: AMIRA's paid Course, and no pack of hers.
    await tester.tap(find.byType(Switch));
    await tester.tap(inSheet(find.text('Philosophie')));
    await tester.pumpAndSettle();
    expect(offerQueries(backend), contains('teacher_ids[]=2&per_page=50&page=1'));
    await tester.tap(find.text('Show 1 result'));
    await tester.pumpAndSettle();

    expect(find.text(_englishCourse), findsOneWidget);
    expect(find.text(_philosophyCourse), findsNothing);
    expect(find.text(_philosophyPack), findsNothing);
    expect(find.text('No offer matches'), findsOneWidget);
  });

  Map<String, FakeResponse> searchCatalog() => <String, FakeResponse>{
        'GET /courses': FakeResponse(
          200,
          _page(<Object>[
            _course(31, _philosophyCourse, _fares, _philosophy),
            _course(32, _englishCourse, _amira, _english),
          ]),
        ),
        'GET /offers': FakeResponse(
          200,
          _page(<Object>[
            _offer(7, _arabicPack, _maya),
            _offer(6, _philosophyPack, _fares),
          ]),
        ),
        'GET /offers/offer-6': FakeResponse(
          200,
          <String, Object?>{'data': _offer(6, _philosophyPack, _fares)},
        ),
        'GET /teachers': FakeResponse(200, _page(<Object>[_fares])),
      };

  /// A dropdown row by its label (`pack X` / `course X`); null: any row.
  Finder suggestion(String? label) => find.byWidgetPredicate(
        (Widget w) =>
            w is PressableScale &&
            (w.semanticLabel ?? '').startsWith('Suggestion ${label ?? ''}') &&
            (label == null || w.semanticLabel == 'Suggestion $label'),
      );

  testWidgets('search suggests matching packs and courses and opens them',
      (tester) async {
    await pumpExplore(tester, searchCatalog());

    await tester.enterText(find.byType(TextField), 'philo');
    await tester.pumpAndSettle();

    expect(
      suggestion('pack $_philosophyPack'),
      findsOneWidget,
    );
    expect(
      suggestion('course $_philosophyCourse'),
      findsOneWidget,
    );
    expect(suggestion('pack $_arabicPack'), findsNothing);
    expect(
      suggestion('course $_englishCourse'),
      findsNothing,
    );

    await tester.tap(suggestion('pack $_philosophyPack'));
    await tester.pumpAndSettle();

    expect(find.byType(CourseDetailScreen), findsOneWidget);
    // The dropdown closed behind the pack page.
    expect(suggestion(null), findsNothing);
  });

  testWidgets('search dropdown says when nothing matches and hides when cleared',
      (tester) async {
    await pumpExplore(tester, searchCatalog());

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No course or offer matches this search.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('No course or offer matches this search.'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  test('search forgives Arabic letter variants, harakat and French accents', () {
    expect(searchMatches('الأدب العربي', 'ادب'), isTrue);
    expect(searchMatches('الرِّياضيات', 'رياضيات'), isTrue);
    expect(searchMatches('الفيزياء والكيمياء', 'الكيمياء'), isTrue);
    expect(searchMatches('مدرسة', 'مدرسه'), isTrue);
    expect(searchMatches('Mathématiques', 'mathematiques'), isTrue);
    expect(searchMatches('Philosophie', 'PHILO'), isTrue);
    expect(searchMatches('Philosophie', 'maths'), isFalse);
  });

  testWidgets('teacher page lists the packs the backend matches to them',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 8100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final FakeBackend backend = FakeBackend(<String, FakeResponse>{
      ...searchCatalog(),
      'GET /offers?teacher_ids[]=1&per_page=50&page=1':
          FakeResponse(200, _page(<Object>[_offer(6, _philosophyPack, _fares)])),
    });
    final CatalogStore catalog = CatalogStore(fakeApi(backend));
    final AppState state = installFixtureApp(catalog: catalog);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: NovaTheme.light,
          home: TeacherDetailScreen(
            teacher: Teacher.fromJson(Map<String, dynamic>.of(_fares)),
          ),
        ),
      ),
    );
    catalog.load();
    await tester.pumpAndSettle();

    expect(offerQueries(backend), contains('teacher_ids[]=1&per_page=50&page=1'));
    expect(find.text('Courses by FARES PHILO'), findsOneWidget);
    expect(find.text(_philosophyCourse), findsOneWidget);
    expect(find.text('Offers with FARES PHILO'), findsOneWidget);
    expect(find.text(_philosophyPack), findsOneWidget);
    expect(find.text(_arabicPack), findsNothing);
  });

  testWidgets('a product outside the Student\'s level cannot be bought (D-083)',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 8100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Map<String, Object?> json = <String, Object?>{
      ..._course(32, _englishCourse, _amira, _english),
      'matches_student_profile': false,
    };
    final FakeBackend backend = FakeBackend(<String, FakeResponse>{
      'GET /courses/course-32': FakeResponse(200, <String, Object?>{'data': json}),
    });
    final AppState state =
        installFixtureApp(catalog: CatalogStore(fakeApi(backend)));
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: NovaTheme.light,
          home: CourseDetailScreen(
            course: Course.fromJson(
              Map<String, dynamic>.of(_course(32, _englishCourse, _amira, _english)),
            ),
          ),
        ),
      ),
    );
    // Before the detail answers, the list's course can still be bought.
    expect(find.text('Add to cart'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Not available for your level or track'), findsNWidgets(2));
    expect(
      find.textContaining('This Course is not part of your level and track'),
      findsOneWidget,
    );
    expect(find.text('Add to cart'), findsNothing);
    expect(find.text('Buy now'), findsNothing);
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Explore'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Explore'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Home'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a bottom bar tab switches from anywhere in its slot', (tester) async {
    await pumpApp(tester);
    final Rect explore = tester.getRect(find.bySemanticsLabel('Explore'));

    // The slot's empty corner, away from the icon.
    await tester.tapAt(explore.topLeft + const Offset(3, 3));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing);

    // The pill's padding ring above the Home slot.
    final Rect home = tester.getRect(find.bySemanticsLabel('Home'));
    await tester.tapAt(Offset(home.center.dx, home.top - 5));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the bottom bar ring maps to the mirrored tab in Arabic', (tester) async {
    final AppState state = AppState.instance;
    state.setLang(NovaLang.ar);
    addTearDown(() => state.setLang(NovaLang.en));
    await pumpApp(tester);

    final Rect explore = tester.getRect(find.bySemanticsLabel('استكشاف'));
    await tester.tapAt(Offset(explore.center.dx, explore.bottom + 5));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(ExploreScreen), findsOneWidget);
  });

  testWidgets('learn screen opens a fully completed course', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Course completed = HomeData.popularCourses
        .where((Course course) => course.progressPercent >= 100)
        .first;
    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          theme: NovaTheme.light,
          home: LearnScreen(course: completed),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Curriculum'), findsOneWidget);
  });

  test('DA prices use thin-space grouping', () {
    expect(formatDaPrice(18900), '\u200e18\u2009900 DA');
    expect(formatDaPrice(4800), '\u200e4\u2009800 DA');
    expect(formatDaPrice(950), '\u200e950 DA');
  });

  testWidgets('DA prices keep their reading order in Arabic', (tester) async {
    Future<List<double>> glyphStarts(TextDirection direction) async {
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: direction,
          child: Center(child: Text(formatDaPrice(4800), key: key)),
        ),
      );
      final RenderParagraph paragraph =
          tester.renderObject<RenderParagraph>(find.byKey(key));
      // Offsets of "4", the first digit of "800", and "D".
      return <int>[1, 3, 7]
          .map(
            (int i) => paragraph
                .getOffsetForCaret(TextPosition(offset: i), Rect.zero)
                .dx,
          )
          .toList();
    }

    final List<double> rtl = await glyphStarts(TextDirection.rtl);
    expect(rtl[0], lessThan(rtl[1]));
    expect(rtl[1], lessThan(rtl[2]));
  });
}
