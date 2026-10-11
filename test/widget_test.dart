import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/utils/format_price.dart';
import 'package:nova_mobile/core/utils/search_text.dart';
import 'package:nova_mobile/core/widgets/hero_style.dart';
import 'package:nova_mobile/core/widgets/nova_bottom_bar.dart';
import 'package:nova_mobile/core/widgets/pressable_scale.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/features/account/orders_screen.dart';
import 'package:nova_mobile/features/account/settings_screen.dart';
import 'package:nova_mobile/features/cart/cart_screen.dart';
import 'package:nova_mobile/features/detail/course_detail_screen.dart';
import 'package:nova_mobile/features/detail/teacher_detail_screen.dart';
import 'package:nova_mobile/features/catalog/offers_catalog_screen.dart';
import 'package:nova_mobile/features/catalog/teachers_screen.dart';
import 'package:nova_mobile/features/catalog/units_catalog_screen.dart';
import 'package:nova_mobile/features/home/home_screen.dart';
import 'package:nova_mobile/features/home/widgets/nova_product_card.dart';
import 'package:nova_mobile/features/learning/learn_screen.dart';
import 'package:nova_mobile/features/learning/lesson_screen.dart';
import 'package:nova_mobile/features/learning/lives_screen.dart';
import 'package:nova_mobile/features/learning/my_learning_screen.dart';
import 'package:nova_mobile/features/shell/shell_screen.dart';
import 'package:nova_mobile/features/shell/student_top_bar.dart';
import 'package:nova_mobile/main.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';

// Public catalogue payloads in the backend's shape (list resources), for
// the teacher and detail pages.
const Map<String, Object> _maya = {'id': 4, 'first_name': 'MAYA', 'last_name': 'ARABE'};
const Map<String, Object> _fares = {'id': 1, 'first_name': 'FARES', 'last_name': 'PHILO'};
const Map<String, Object> _amira = {'id': 2, 'first_name': 'AMIRA', 'last_name': 'ENGLISH'};
const Map<String, Object> _english = {'id': 5, 'name_fr': 'Langue anglaise', 'name_ar': 'اللغة الإنجليزية'};
const Map<String, Object> _philosophy = {'id': 19, 'name_fr': 'Philosophie', 'name_ar': 'الفلسفة'};
const String _arabicPack = 'Arabic — First Trimester';
const String _philosophyPack = 'Philosophy — First Trimester';
const String _philosophyCourse = 'Philosophy — Essay Method';
const String _englishCourse = 'English — Exam Skills';

Map<String, Object?> _page(List<Object> data) => <String, Object?>{
      'data': data,
      'meta': <String, Object>{'current_page': 1, 'last_page': 1, 'total': data.length},
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

/// Loads the bundled Baloo Bhaijaan 2 / Geist families so text metrics match production.
Future<void> _loadNovaFonts() async {
  const Map<String, List<String>> families = {
    'BalooBhaijaan2': [
      'BalooBhaijaan2-400.ttf',
      'BalooBhaijaan2-500.ttf',
      'BalooBhaijaan2-600.ttf',
      'BalooBhaijaan2-700.ttf',
      'BalooBhaijaan2-800.ttf',
    ],
    'Geist': [
      'Geist-400.ttf',
      'Geist-500.ttf',
      'Geist-600.ttf',
      'Geist-700.ttf',
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

  /// Two seconds of frames: the home's live-now pulse loops, so the app
  /// never "settles" while it shows.
  Future<void> frames(WidgetTester tester) async {
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 8100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NovaApp());
    await frames(tester);
  }

  /// A title drawn with its circled word (`*word*`), by its plain text.
  Finder heroTitle(String plain) =>
      find.byWidgetPredicate((Widget w) => w is HeroTitle && HeroTitle.plain(w.text) == plain);

  Finder inBar(Finder finder) => find.descendant(of: find.byType(NovaBottomBar), matching: finder);

  /// The menu's panel (`.studentSidebar`, 258 wide), docked to the
  /// reading-start edge.
  final Finder menuPanel = find.byWidgetPredicate(
    (Widget w) => w is Container && w.constraints?.maxWidth == 258,
  );
  Finder inMenu(String text) => find.descendant(of: menuPanel, matching: find.text(text));

  /// The tab the Student sees: the only one that answers touches.
  Finder shown(Type screen) => find.byType(screen).hitTestable();

  testWidgets('home is the website account home: greeting band, live-now bar, Units then Offers', (tester) async {
    await pumpApp(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    // The band: today's date (Algeria time), the greeting, one line, two ways on.
    final DateTime now = algeriaTime(DateTime.now());
    const List<String> days = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const List<String> months = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    expect(find.text('${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}'), findsOneWidget);
    expect(heroTitle('Welcome back, ${HomeData.studentName}.'), findsOneWidget);
    expect(find.text('Open your Units or discover the ones made for your level.'), findsOneWidget);
    expect(find.text('Continue learning'), findsOneWidget);
    expect(find.text('See the Offers'), findsOneWidget);

    // One of the Student's Lives is on: one tap from home, with its Unit.
    final LiveSession live = HomeData.lives.first;
    expect(find.text('Your live class is on now'), findsOneWidget);
    expect(find.text('${live.title} · ${live.course}'), findsOneWidget);
    expect(find.text('Join live'), findsOneWidget);

    // Units: the Student's own first, then the others of their level.
    expect(find.text('Units'), findsOneWidget);
    expect(find.text('Your Units first, then more for your level.'), findsOneWidget);
    expect(find.text('All Units'), findsOneWidget);
    final List<Course> courses = <Course>[
      ...HomeData.popularCourses.where((Course c) => c.owned),
      ...HomeData.popularCourses.where((Course c) => !c.owned),
    ];
    final List<double> starts = <double>[
      for (final Course course in courses) tester.getRect(find.text(course.title)).left,
    ];
    expect(starts, orderedEquals(<double>[...starts]..sort()));
    final int owned = HomeData.popularCourses.where((Course c) => c.owned).length;
    expect(find.text('Open Unit'), findsNWidgets(owned));
    expect(find.text('Purchased'), findsNWidgets(owned));
    expect(find.text('Unlocked'), findsNWidgets(owned));
    // The others are catalogue cards: "N Live" tag, price, "See more".
    expect(find.text('12 Live'), findsOneWidget);
    expect(find.text('4,800 DZD'), findsOneWidget);
    expect(find.text('See more'), findsNWidgets(courses.length - owned));

    // Offers: several Units in one purchase.
    expect(find.text('Offers'), findsOneWidget);
    expect(find.text('Several Units in a single purchase, for your level.'), findsOneWidget);
    for (final Pack pack in HomeData.featuredPacks) {
      expect(find.text(pack.name), findsOneWidget);
    }
    expect(find.text('Buy now'), findsNWidgets(HomeData.featuredPacks.length));
    expect(find.byType(NovaProductCard), findsNWidgets(courses.length + HomeData.featuredPacks.length));

    // The old home's sections are gone.
    expect(find.text('Popular courses'), findsNothing);
    expect(find.text('Our teachers'), findsNothing);
  });

  testWidgets('"Continue learning" switches to My lessons; "See the Offers" and "All Units" open the catalogues', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Continue learning'));
    await frames(tester);
    expect(tester.widget<NovaBottomBar>(find.byType(NovaBottomBar)).currentIndex, ShellScreen.units);
    expect(shown(MyLearningScreen), findsOneWidget);
    expect(shown(HomeScreen), findsNothing);

    await tester.tap(inBar(find.text('Home')));
    await frames(tester);
    expect(shown(HomeScreen), findsOneWidget);

    await tester.tap(find.text('See the Offers'));
    await frames(tester);
    expect(find.byType(OffersCatalogScreen), findsOneWidget);
    await tester.tap(find.byType(BackPill).last);
    await frames(tester);
    expect(find.byType(OffersCatalogScreen), findsNothing);

    await tester.tap(find.text('All Units'));
    await frames(tester);
    expect(find.byType(UnitsCatalogScreen), findsOneWidget);
    await tester.tap(find.byType(BackPill).last);
    await frames(tester);
    expect(find.byType(UnitsCatalogScreen), findsNothing);

    await tester.ensureVisible(find.text('All Offers'));
    await tester.tap(find.text('All Offers'));
    await frames(tester);
    expect(find.byType(OffersCatalogScreen), findsOneWidget);
  });

  testWidgets('a card opens its Unit (owned), its page (not owned) or its Offer', (tester) async {
    await pumpApp(tester);
    Future<void> openCard(String title) async {
      await tester.ensureVisible(find.text(title));
      await frames(tester);
      await tester.tap(find.text(title));
      await frames(tester);
    }

    await openCard('Physics — Mechanics Masterclass');
    expect(find.byType(LearnScreen), findsOneWidget);
    expect(find.text('Unit Lessons'), findsOneWidget);
    await tester.tap(find.byType(BackPill));
    await frames(tester);

    await openCard('Mathematics — Problem Solving Lab');
    expect(find.byType(LearnScreen), findsNothing);
    expect(find.byType(CourseDetailScreen), findsOneWidget);
    expect(tester.widget<CourseDetailScreen>(find.byType(CourseDetailScreen)).course?.id, 101);
    await tester.tap(find.byType(BackPill).last);
    await frames(tester);
    expect(find.byType(CourseDetailScreen), findsNothing);

    await openCard('Science Track — Complete Year');
    expect(find.byType(CourseDetailScreen), findsOneWidget);
    expect(tester.widget<CourseDetailScreen>(find.byType(CourseDetailScreen)).pack?.id, 201);
  });

  testWidgets('in Arabic the greeting and the rails read from the right', (tester) async {
    final AppState state = AppState.instance;
    state.setLang(NovaLang.ar);
    addTearDown(() => state.setLang(NovaLang.en));
    await pumpApp(tester);

    final double screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(heroTitle('أهلا ${HomeData.studentName}! يلّا نكمّلو'), findsOneWidget);
    // The first Unit hugs the right edge; the next one sits to its left.
    final Rect first = tester.getRect(find.ancestor(of: find.text('Physics — Mechanics Masterclass'), matching: find.byType(NovaProductCard)));
    final Rect second = tester.getRect(find.ancestor(of: find.text('Philosophy — Essay Blueprint'), matching: find.byType(NovaProductCard)));
    expect(first.right, greaterThan(screenWidth - 30));
    expect(second.right, lessThan(first.left));
  });

  testWidgets('the menu is the website sidebar: Learning and Account, help, sign out', (tester) async {
    await pumpApp(tester);
    Future<void> openMenu() async {
      await tester.tap(find.bySemanticsLabel('Menu'));
      await frames(tester);
    }

    await openMenu();
    for (final String label in <String>[
      'Learning', 'Overview', 'My units', 'Lives', 'Teachers', //
      'Account', 'Orders', 'Wallet & rewards', 'Settings', 'Need help?', 'Talk to the Nova team', 'Sign out',
    ]) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    // No visitor buttons for a Student.
    expect(inMenu('Create my account'), findsNothing);

    // The open page is the blue row.
    BoxDecoration row(String label) => tester
        .widget<Container>(find.ancestor(of: inMenu(label), matching: find.byType(Container)).first)
        .decoration! as BoxDecoration;
    expect(row('Overview').color, const Color(0xFF1F54D6));
    expect(row('My units').color, Colors.transparent);

    // A tab of the bar.
    await tester.tap(inMenu('My units'));
    await frames(tester);
    expect(menuPanel, findsNothing);
    expect(shown(MyLearningScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(MyLearningScreen), matching: find.text('Physics — Mechanics Masterclass')), findsOneWidget);

    // A page of its own.
    await openMenu();
    expect(row('My units').color, const Color(0xFF1F54D6));
    await tester.tap(inMenu('Orders'));
    await frames(tester);
    expect(find.byType(OrdersScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(OrdersScreen))).pop();
    await frames(tester);

    await openMenu();
    await tester.tap(inMenu('Teachers'));
    await frames(tester);
    expect(find.byType(TeachersScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(TeachersScreen))).pop();
    await frames(tester);

    // Settings is the Account tab, as on the website.
    await openMenu();
    await tester.tap(inMenu('Settings'));
    await frames(tester);
    expect(tester.widget<NovaBottomBar>(find.byType(NovaBottomBar)).currentIndex, ShellScreen.account);
    expect(shown(SettingsScreen), findsOneWidget);

    // Sign out ends the session, like the settings' button.
    await openMenu();
    await tester.tap(inMenu('Sign out'));
    await frames(tester);
    expect(AppState.instance.session.signedIn, isFalse);
  });

  testWidgets('the top bar reads like the website: menu at the start; theme, bell, initials at the end', (tester) async {
    final AppState state = AppState.instance;
    state.setLang(NovaLang.ar);
    addTearDown(() => state.setLang(NovaLang.en));
    await pumpApp(tester);

    final Finder bar = find.byType(StudentTopBar).hitTestable().first;
    double x(Finder finder) => tester.getCenter(find.descendant(of: bar, matching: finder).first).dx;
    final double menu = x(find.bySemanticsLabel('Menu'));
    final double theme = x(find.bySemanticsLabel('الوضع الداكن'));
    // The bell's label carries its unread count.
    final double bell = x(find.bySemanticsLabel(RegExp('^الإشعارات')));
    final Finder initialsText = find.text(StudentTopBar.initialsOf('${HomeData.student.firstName} ${HomeData.student.lastName}'));
    final double initials = x(initialsText);
    // Right to left in Arabic: menu … theme, bell, initials.
    expect(menu, greaterThan(theme));
    expect(theme, greaterThan(bell));
    expect(bell, greaterThan(initials));

    // The initials open the settings: the Account tab.
    await tester.tap(find.descendant(of: bar, matching: initialsText));
    await frames(tester);
    expect(tester.widget<NovaBottomBar>(find.byType(NovaBottomBar)).currentIndex, ShellScreen.account);
    expect(shown(SettingsScreen), findsOneWidget);
  });

  testWidgets('menu docks to the right edge in Arabic', (tester) async {
    final AppState state = AppState.instance;
    state.setLang(NovaLang.ar);
    addTearDown(() => state.setLang(NovaLang.en));
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Menu'));
    await frames(tester);

    final double screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final Rect panel = tester.getRect(menuPanel);
    expect(panel.right, greaterThan(screenWidth - 20));
    expect(panel.left, greaterThan(0));
  });

  // The Units, Offers and Teachers catalogues (search, filters, sort) are
  // covered by test/catalog_test.dart.

  List<String> offerQueries(FakeBackend backend) => backend.requests
      .where((FakeRequest r) => r.path == '/offers')
      .map((FakeRequest r) => r.query)
      .toList();

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
    expect(find.text('Units by FARES PHILO'), findsOneWidget);
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
    // Before the detail answers, the list's course can still be bought (the
    // band's buy row and the buy card, D-134).
    expect(find.text('Add to cart'), findsNWidgets(2));
    await tester.pumpAndSettle();

    // The notice on the band and the sticky bar.
    expect(find.textContaining('Not available for your level or track'), findsNWidgets(2));
    expect(
      find.textContaining('This Unit is not part of your level and track'),
      findsOneWidget,
    );
    expect(find.text('Add to cart'), findsNothing);
    expect(find.text('Buy now'), findsNothing);
  });

  /// The yellow marker of the bottom bar (`.studentBottomNav` active pill).
  Rect marker(WidgetTester tester) =>
      tester.getRect(inBar(find.byType(AnimatedPositionedDirectional)));

  testWidgets('the bottom bar holds the website tabs and switches between them', (tester) async {
    await pumpApp(tester);

    const Map<String, Type> tabs = <String, Type>{
      'Home': HomeScreen,
      'My lessons': MyLearningScreen,
      'Live': LivesScreen,
      'Cart': CartScreen,
      // As on the website, "Account" is the settings (`/account/settings`).
      'Account': SettingsScreen,
    };
    final List<double> centers = <double>[
      for (final String label in tabs.keys) tester.getCenter(inBar(find.text(label))).dx,
    ];
    // Left to right in English, in the website's order.
    expect(centers, orderedEquals(<double>[...centers]..sort()));
    expect(shown(HomeScreen), findsOneWidget);
    expect(marker(tester).center.dx, closeTo(centers.first, 1));

    int index = 0;
    for (final MapEntry<String, Type> tab in tabs.entries.toList().reversed) {
      await tester.tap(inBar(find.text(tab.key)));
      await frames(tester);
      index = tabs.keys.toList().indexOf(tab.key);
      expect(tester.widget<NovaBottomBar>(find.byType(NovaBottomBar)).currentIndex, index);
      expect(shown(tab.value), findsOneWidget, reason: tab.key);
      for (final Type other in tabs.values.where((Type t) => t != tab.value)) {
        expect(shown(other), findsNothing, reason: '${tab.key} hides $other');
      }
      // The yellow marker sits under the active tab.
      expect(marker(tester).center.dx, closeTo(centers[index], 1));
    }
    expect(index, 0);
  });

  testWidgets('a bottom bar tab answers anywhere in its slot', (tester) async {
    await pumpApp(tester);
    final Rect cart = tester.getRect(inBar(find.ancestor(of: find.text('Cart'), matching: find.byType(PressableScale))));

    // The slot's empty corner, away from the icon and the label.
    await tester.tapAt(cart.topLeft + const Offset(3, 3));
    await frames(tester);
    expect(shown(CartScreen), findsOneWidget);
    expect(shown(HomeScreen), findsNothing);

    final Rect home = tester.getRect(inBar(find.ancestor(of: find.text('Home'), matching: find.byType(PressableScale))));
    await tester.tapAt(home.bottomRight - const Offset(3, 3));
    await frames(tester);
    expect(shown(HomeScreen), findsOneWidget);
  });

  testWidgets('the bottom bar mirrors in Arabic', (tester) async {
    final AppState state = AppState.instance;
    state.setLang(NovaLang.ar);
    addTearDown(() => state.setLang(NovaLang.en));
    await pumpApp(tester);

    // Home (الدار) on the right, Account (حسابي) on the left.
    final double home = tester.getCenter(inBar(find.text('الدار'))).dx;
    final double account = tester.getCenter(inBar(find.text('حسابي'))).dx;
    expect(home, greaterThan(account));
    expect(marker(tester).center.dx, closeTo(home, 1));

    await tester.tap(inBar(find.text('حسابي')));
    await frames(tester);
    expect(shown(SettingsScreen), findsOneWidget);
    expect(shown(HomeScreen), findsNothing);
    expect(marker(tester).center.dx, closeTo(account, 1));
  });

  group('the website catalogue card (`.novaCard`)', () {
    Course unit(Map<String, Object?> json, {bool owned = false}) =>
        Course.fromJson(<String, dynamic>{'slug': 'u', 'teacher': _fares, 'subject': _philosophy, ...json}, owned: owned);
    final Pack pack = Pack.fromJson(<String, dynamic>{
      'id': 8,
      'slug': 'pack-bac',
      'title': 'Pack BAC Sciences',
      'type': 'trimestre',
      'price': '5000.00',
      'courses_reference_total': '10300.00',
      'courses': <Object>[<String, Object>{'id': 2, 'title': 'Analyse BAC'}],
    });

    Future<void> pumpCards(WidgetTester tester, List<Widget Function(BuildContext)> cards) async {
      tester.view.physicalSize = const Size(1170, 9000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppScope(
          state: AppState.instance,
          child: MaterialApp(
            theme: NovaTheme.light,
            home: Scaffold(
              body: ListView(children: [for (final card in cards) Builder(builder: (BuildContext c) => card(c))]),
            ),
          ),
        ),
      );
      // The Live tag's dot pulses: frames, not settle.
      await frames(tester);
    }

    /// The arrow chip of the button that reads [label], if any.
    Finder chipOf(String label) => find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
          matching: find.byIcon(Icons.arrow_forward_rounded),
        );

    testWidgets('Units: tag, badge, price and button as on the website', (tester) async {
      await pumpCards(tester, <Widget Function(BuildContext)>[
        (BuildContext c) => NovaProductCard.unit(
              c,
              unit(<String, Object?>{'id': 1, 'title': 'SVT', 'reference_price': '0.00', 'is_free': true, 'individual_purchase_enabled': false}),
              onTap: () {},
            ),
        (BuildContext c) => NovaProductCard.unit(
              c,
              unit(<String, Object?>{'id': 2, 'title': 'Analyse BAC', 'reference_price': '3900.00', 'planned_live_count': 4}),
              onTap: () {},
            ),
        (BuildContext c) => NovaProductCard.unit(
              c,
              unit(<String, Object?>{'id': 3, 'title': 'Philo', 'reference_price': '2900.00', 'individual_purchase_enabled': false, 'offer_price_from': '5000.00'}),
              onTap: () {},
            ),
        (BuildContext c) => NovaProductCard.unit(c, unit(<String, Object?>{'id': 4, 'title': 'Mine', 'reference_price': '3000.00'}, owned: true), onTap: () {}),
      ]);

      // A free Unit: "Free" badge and price (never the raw key), "Get it free" with its chip.
      expect(find.text('detail.free'), findsNothing);
      expect(find.text('Free'), findsNWidgets(2));
      expect(find.text('Get it free'), findsOneWidget);
      expect(chipOf('Get it free'), findsOneWidget);
      // The tag is always there: "Recorded", or the Lives.
      expect(find.text('Recorded'), findsNWidgets(2));
      expect(find.text('4 Live'), findsOneWidget);
      // A paid Unit: its price and "See more", without a chip.
      expect(find.text('3,900 DZD'), findsOneWidget);
      expect(find.text('See more'), findsNWidgets(2));
      expect(chipOf('See more'), findsNothing);
      // Sold through Offers only: the cheapest Offer.
      expect(find.text('In Offers from'), findsOneWidget);
      expect(find.text('5,000 DZD'), findsOneWidget);
      // The Student's own Unit.
      expect(find.text('Purchased'), findsOneWidget);
      expect(find.text('Unlocked'), findsOneWidget);
      expect(find.text('Open Unit'), findsOneWidget);
    });

    testWidgets('Offers: saving, price and former total, "Buy now"; owned and covered Offers lead to My units', (tester) async {
      int myUnits = 0;
      await pumpCards(tester, <Widget Function(BuildContext)>[
        (BuildContext c) => NovaProductCard.offer(c, pack, onTap: () {}),
        (BuildContext c) => NovaProductCard.offer(c, pack, ownership: OfferOwnership.owned, onTap: () {}, onAction: () => myUnits++),
        (BuildContext c) => NovaProductCard.offer(c, pack, ownership: OfferOwnership.covered, onTap: () {}, onAction: () => myUnits++),
      ]);

      expect(find.text('Save 51%'), findsOneWidget);
      expect(find.text('5,000 DZD'), findsOneWidget);
      expect(find.text('10,300 DZD'), findsOneWidget);
      expect(find.text('Buy now'), findsOneWidget);
      expect(chipOf('Buy now'), findsOneWidget);
      expect(find.text('Purchased'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Units already yours'), findsOneWidget);
      expect(find.text('My units'), findsNWidgets(2));

      await tester.tap(find.text('My units').first);
      await tester.tap(find.text('My units').last);
      expect(myUnits, 2);
    });

    test('prices read as on the website (en-DZ grouping, DZD)', () {
      expect(NovaProductCard.formatCardPrice(950), '950 DZD');
      expect(NovaProductCard.formatCardPrice(5000), '5,000 DZD');
      expect(NovaProductCard.formatCardPrice(1234567), '1,234,567 DZD');
    });
  });

  group('what the Home shows (website `AccountHome`)', () {
    Course unit(int id, {bool free = false}) => Course.fromJson(<String, dynamic>{'id': id, 'title': 'U$id', 'is_free': free});
    Pack offer(int id, List<int> units) => Pack.fromJson(<String, dynamic>{
          'id': id,
          'title': 'O$id',
          'price': '1000.00',
          'courses': <Object>[for (final int u in units) <String, Object>{'id': u, 'title': 'U$u'}],
        });
    final List<Course> catalogue = <Course>[for (int i = 1; i <= 12; i++) unit(i)];

    test('owned Units first, then others to fill rows of three (six cards at least)', () {
      HomeSelection home = HomeSelection.of(owned: <Course>[unit(1), unit(2)], catalogue: catalogue, offers: const <Pack>[]);
      expect(home.ownedUnits.map((Course c) => c.id), <int>[1, 2]);
      expect(home.otherUnits.map((Course c) => c.id), <int>[3, 4, 5, 6]);
      expect(home.hasOffers, isFalse);

      home = HomeSelection.of(owned: <Course>[unit(1), unit(2), unit(3), unit(4)], catalogue: catalogue, offers: const <Pack>[]);
      expect(home.otherUnits, hasLength(5));

      home = HomeSelection.of(owned: const <Course>[], catalogue: catalogue, offers: const <Pack>[]);
      expect(home.otherUnits, hasLength(6));
      expect(HomeSelection.of(owned: const <Course>[], catalogue: const <Course>[], offers: const <Pack>[]).hasUnits, isFalse);
    });

    test('an Offer is the Student\'s when held; one whose Units are all paid is covered', () {
      final List<Course> owned = <Course>[unit(1), unit(2, free: true)];
      final List<Pack> offers = <Pack>[offer(10, <int>[1]), offer(11, <int>[2]), offer(12, <int>[1, 3]), offer(13, <int>[5])];

      // `owned_offer_ids` lists the Offers the Student holds.
      HomeSelection home = HomeSelection.of(owned: owned, catalogue: catalogue, offers: offers, ownedOfferIds: <int>{13});
      expect(home.ownedOffers.map((Pack p) => p.id), <int>[13]);
      // Offer 10 holds only a paid Unit: covered; a free enrolment (11) covers nothing.
      expect(home.otherOffers.map(((Pack, bool) e) => (e.$1.id, e.$2)), <(int, bool)>[(10, true), (11, false), (12, false)]);

      // Without the list, the website's older rule: all Units paid = the Student's.
      home = HomeSelection.of(owned: owned, catalogue: catalogue, offers: offers);
      expect(home.ownedOffers.map((Pack p) => p.id), <int>[10]);
      expect(home.otherOffers.map(((Pack, bool) e) => e.$1.id), <int>[11, 12, 13]);
    });
  });

  testWidgets('the Unit page of a finished Unit shows every Lesson done', (tester) async {
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
    expect(heroTitle(completed.title), findsOneWidget);
    expect(find.text('${completed.lessons.length} of ${completed.lessons.length} done'), findsOneWidget);
    expect(find.text('Unit Lessons'), findsOneWidget);
    for (final Lesson lesson in completed.lessons) {
      await tester.scrollUntilVisible(find.text(lesson.title), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text(lesson.title), findsOneWidget);
    }
    expect(find.text('Completed'), findsNWidgets(completed.lessons.length));
    // Nothing left to start: no "Continue here" mark on a row.
    expect(find.text('Continue here'), findsNothing);
    expect(find.text('Start here'), findsNothing);

    await tester.tap(find.text(completed.lessons.last.title));
    await tester.pumpAndSettle();
    expect(find.byType(LessonScreen), findsOneWidget);
    expect(find.text('Video watched. Well done!'), findsOneWidget);
  });

  test('prices are written as on the website (formatPrice)', () {
    expect(formatDaPrice(18900), '18,900 DZD');
    expect(formatDaPrice(4800), '4,800 DZD');
    expect(formatDaPrice(950), '950 DZD');
  });

  testWidgets('in Arabic a price reads "DZD 4,800", the digit groups in order, as on the website', (tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Center(child: Text(formatDaPrice(4800), key: key)),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.byKey(key));
    double left(int i) => paragraph.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first.left;
    // "4,800 DZD": "4" at 0, "8" at 2, "D" at 6.
    expect(left(6), lessThan(left(0)));
    expect(left(0), lessThan(left(2)));
  });
}
