import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/i18n/notification_text.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_colors.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/widgets/notification_banner.dart';
import 'package:nova_mobile/data/account_store.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/session_store.dart';
import 'package:nova_mobile/features/account/notifications_screen.dart';
import 'package:nova_mobile/features/explore/explore_screen.dart';
import 'package:nova_mobile/main.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

const String _scheduled = '2026-09-26T13:45:00+00:00';

/// A notification exactly as `StudentNotificationResource` (or the
/// `NotificationCreated` broadcast) sends it.
Map<String, Object?> _payload(
  String id,
  String type, {
  String title = 'Stored title',
  String message = 'Stored message',
  Map<String, Object?> data = const <String, Object?>{},
  int? liveId,
  String? scheduledAt,
  String? url,
  String? readAt,
  String createdAt = '2026-09-26T08:00:00+00:00',
}) =>
    <String, Object?>{
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'data': data,
      'live_id': liveId,
      'scheduled_at': scheduledAt,
      'url': url,
      'read_at': readAt,
      'created_at': createdAt,
    };

AppNotification _parse(Map<String, Object?> json) =>
    AppNotification.fromJson(Map<String, dynamic>.of(json));

/// One page of `GET /me/notifications`.
FakeResponse _page(List<Map<String, Object?>> items, {required int page, required int lastPage, int unread = 0}) =>
    FakeResponse(200, <String, Object?>{
      'data': items,
      'meta': <String, Object?>{'current_page': page, 'last_page': lastPage, 'per_page': 20},
      'unread_count': unread,
    });

List<Map<String, Object?>> _notices(int from, int to) => <Map<String, Object?>>[
      for (int i = from; i <= to; i++)
        _payload(
          'n$i',
          'admin_message',
          title: 'Notice $i',
          message: 'Message $i',
          readAt: i.isEven ? '2026-09-26T09:00:00+00:00' : null,
          createdAt: DateTime.utc(2026, 9, 26, 8).subtract(Duration(minutes: i)).toIso8601String(),
        ),
    ];

void main() {
  setUpAll(loadNovaFonts);

  group('Algeria date and time', () {
    test('formats like the web for each language, from the UTC instant', () {
      final DateTime at = DateTime.parse('2026-09-26T13:45:00Z');
      expect(formatAlgeriaDateTime(at, NovaLang.en), '26 Sept 2026, 14:45');
      expect(formatAlgeriaDateTime(at, NovaLang.fr), '26 sept. 2026, 2:45 PM');
      expect(formatAlgeriaDateTime(at, NovaLang.ar), '26‏/09‏/2026، 2:45 م');
    });

    test('is UTC+1 whatever the zone of the parsed value', () {
      // Same instant written in another offset, then in device time.
      final DateTime other = DateTime.parse('2026-09-26T15:45:00+02:00');
      expect(formatAlgeriaDateTime(other, NovaLang.en), '26 Sept 2026, 14:45');
      expect(formatAlgeriaDateTime(other.toLocal(), NovaLang.en), '26 Sept 2026, 14:45');
      // No DST: a July instant is also UTC+1.
      expect(formatAlgeriaDateTime(DateTime.parse('2026-07-01T11:00:00Z'), NovaLang.en), '1 Jul 2026, 12:00');
    });

    test('crosses midnight and the year into Algeria time', () {
      final DateTime at = DateTime.parse('2026-12-31T23:59:00Z');
      expect(formatAlgeriaDateTime(at, NovaLang.en), '1 Jan 2027, 00:59');
      expect(formatAlgeriaDateTime(at, NovaLang.fr), '1 janv. 2027, 12:59 AM');
      expect(formatAlgeriaDateTime(at, NovaLang.ar), '01‏/01‏/2027، 12:59 ص');
    });

    test('groups by Algeria calendar day', () {
      final DateTime now = DateTime.parse('2026-09-26T10:00:00Z');
      // 23:30 UTC on the 25th is already the 26th in Algeria.
      expect(_parse(_payload('a', 'x', createdAt: '2026-09-25T23:30:00+00:00')).groupAt(now), NotificationGroup.today);
      expect(_parse(_payload('b', 'x', createdAt: '2026-09-25T22:30:00+00:00')).groupAt(now), NotificationGroup.yesterday);
      expect(_parse(_payload('c', 'x', createdAt: '2026-09-22T12:00:00+00:00')).groupAt(now), NotificationGroup.thisWeek);
      expect(_parse(_payload('d', 'x', createdAt: '2026-09-10T12:00:00+00:00')).groupAt(now), NotificationGroup.earlier);
    });

    test('each notification shows its creation date and time', () {
      final AppNotification n = _parse(_payload('a', 'admin_message', createdAt: '2026-09-26T13:45:00+00:00'));
      expect(notificationTime(n, NovaLang.en), '26 Sept 2026, 14:45');
      expect(notificationTime(n, NovaLang.ar), '26‏/09‏/2026، 2:45 م');
    });
  });

  group('Notification text per type and language', () {
    const String enDate = '26 Sept 2026, 14:45';
    const String frDate = '26 sept. 2026, 2:45 PM';
    const String arDate = '26‏/09‏/2026، 2:45 م';
    const Map<String, Object?> live = <String, Object?>{
      'entity_type': 'LiveSession',
      'entity_id': 12,
      'live_title': 'Limits',
      'scheduled_at': _scheduled,
    };
    const Map<String, Object?> order = <String, Object?>{
      'entity_type': 'Order',
      'entity_id': 4,
      'order_number': 'ORD-1',
    };

    final Map<String, (Map<String, Object?>, Map<NovaLang, (String, String)>)> cases = {
      'live_scheduled': (live, {
        NovaLang.en: ('New Live scheduled', 'Limits is scheduled for $enDate (Algeria time).'),
        NovaLang.fr: ('Nouveau live programmé', 'Limits est programmé le $frDate (heure d’Algérie).'),
        NovaLang.ar: ('حصة مباشرة جديدة مبرمجة', 'Limits مبرمجة يوم $arDate (بتوقيت الجزائر).'),
      }),
      'live_rescheduled': (live, {
        NovaLang.en: ('Live rescheduled', 'Limits is now scheduled for $enDate (Algeria time).'),
        NovaLang.fr: ('Live reprogrammé', 'Limits est désormais programmé le $frDate (heure d’Algérie).'),
        NovaLang.ar: ('تغيير موعد الحصة المباشرة', 'Limits أصبحت مبرمجة يوم $arDate (بتوقيت الجزائر).'),
      }),
      'live_reminder': (live, {
        NovaLang.en: ('Live starts soon', 'Limits starts at $enDate (Algeria time).'),
        NovaLang.fr: ('Le live commence bientôt', 'Limits commence le $frDate (heure d’Algérie).'),
        NovaLang.ar: ('الحصة المباشرة ستبدأ قريبًا', 'تبدأ Limits يوم $arDate (بتوقيت الجزائر).'),
      }),
      'live_started': (live, {
        NovaLang.en: ('Live started', 'Limits is live now.'),
        NovaLang.fr: ('Le live a commencé', 'Limits est en direct maintenant.'),
        NovaLang.ar: ('بدأت الحصة المباشرة', 'Limits مباشرة الآن.'),
      }),
      'live_cancelled': (live, {
        NovaLang.en: ('Live cancelled', 'Limits has been cancelled.'),
        NovaLang.fr: ('Live annulé', 'Limits a été annulé.'),
        NovaLang.ar: ('أُلغيت الحصة المباشرة', 'تم إلغاء Limits.'),
      }),
      'live_replay_ready': (live, {
        NovaLang.en: ('Replay available', 'Limits is ready to watch.'),
        NovaLang.fr: ('Replay disponible', 'Limits est prêt à être visionné.'),
        NovaLang.ar: ('التسجيل متاح', 'تسجيل Limits جاهز للمشاهدة.'),
      }),
      'lesson_published': (<String, Object?>{'course_id': 3, 'lesson_title': 'Derivatives'}, {
        NovaLang.en: ('New Lesson published', 'Derivatives is now available.'),
        NovaLang.fr: ('Nouvelle leçon publiée', 'Derivatives est maintenant disponible.'),
        NovaLang.ar: ('درس جديد منشور', 'Derivatives متاح الآن.'),
      }),
      'access_closed': (<String, Object?>{'academic_year_name': '2025-2026'}, {
        NovaLang.en: ('Academic access closed', 'Your access for Academic Year 2025-2026 is now closed.'),
        NovaLang.fr: ('Accès académique clôturé', 'Votre accès pour l’année scolaire 2025-2026 est désormais clôturé.'),
        NovaLang.ar: ('انتهى الوصول الأكاديمي', 'انتهى وصولك للسنة الدراسية 2025-2026.'),
      }),
      'purchase_paid': (<String, Object?>{...order, 'purchase_id': 9}, {
        NovaLang.en: ('Purchase paid', 'Your Order ORD-1 is paid and your access is ready.'),
        NovaLang.fr: ('Achat payé', 'Votre commande ORD-1 est payée et votre accès est prêt.'),
        NovaLang.ar: ('تم دفع الطلب', 'تم دفع طلبك ORD-1 ووصولك جاهز.'),
      }),
      'points_credited': (<String, Object?>{'points': 600, 'balance': 1200}, {
        NovaLang.en: ('Points credited', '600 points were credited to your Nova balance.'),
        NovaLang.fr: ('Points crédités', '600 points ont été crédités sur votre solde Nova.'),
        NovaLang.ar: ('تمت إضافة نقاط', 'تمت إضافة 600 نقطة إلى رصيدك في نوفا.'),
      }),
      'referral_reward_credited': (<String, Object?>{'points': 600, 'balance': 1200}, {
        NovaLang.en: ('Referral reward credited', '600 points were credited to your Nova balance.'),
        NovaLang.fr: ('Récompense de parrainage créditée', '600 points ont été crédités sur votre solde Nova.'),
        NovaLang.ar: ('تمت إضافة مكافأة الإحالة', 'تمت إضافة 600 نقطة إلى رصيدك في نوفا.'),
      }),
      'ccp_approved': (order, {
        NovaLang.en: ('CCP receipt approved', 'Your CCP payment for Order ORD-1 was approved.'),
        NovaLang.fr: ('Reçu CCP approuvé', 'Votre paiement CCP pour la commande ORD-1 a été approuvé.'),
        NovaLang.ar: ('تم قبول وصل CCP', 'تم قبول دفعك عبر CCP للطلب ORD-1.'),
      }),
      'ccp_rejected': (<String, Object?>{...order, 'reason': 'Illegible receipt'}, {
        NovaLang.en: ('CCP receipt rejected', 'Your CCP payment for Order ORD-1 was rejected: Illegible receipt'),
        NovaLang.fr: ('Reçu CCP refusé', 'Votre paiement CCP pour la commande ORD-1 a été refusé : Illegible receipt'),
        NovaLang.ar: ('تم رفض وصل CCP', 'تم رفض دفعك عبر CCP للطلب ORD-1: Illegible receipt'),
      }),
    };

    for (final MapEntry<String, (Map<String, Object?>, Map<NovaLang, (String, String)>)> entry in cases.entries) {
      test('${entry.key} renders from its params', () {
        final AppNotification n = _parse(_payload('id', entry.key, data: entry.value.$1));
        for (final MapEntry<NovaLang, (String, String)> expected in entry.value.$2.entries) {
          final NotificationText text = notificationText(n, expected.key);
          expect((text.title, text.message), expected.value, reason: '${entry.key} ${expected.key.name}');
        }
      });
    }

    test('admin messages and unknown types keep the stored text as written', () {
      for (final String type in <String>['admin_message', 'something_new']) {
        final AppNotification n = _parse(_payload('id', type, title: 'Bac blanc samedi', message: 'Salle 3, 9h.'));
        for (final NovaLang lang in NovaLang.values) {
          final NotificationText text = notificationText(n, lang);
          expect((text.title, text.message), ('Bac blanc samedi', 'Salle 3, 9h.'));
        }
      }
    });

    test('a missing param keeps the localized title and the stored message', () {
      final AppNotification n = _parse(_payload('id', 'ccp_rejected', message: 'Stored rejection.', data: <String, Object?>{'order_number': 'ORD-1'}));
      final NotificationText text = notificationText(n, NovaLang.ar);
      expect((text.title, text.message), ('تم رفض وصل CCP', 'Stored rejection.'));
    });

    test('rows stored before the params existed are read back from the English text', () {
      final AppNotification n = _parse(_payload('id', 'live_started', title: 'Live started', message: 'Old live is live now.'));
      expect(notificationText(n, NovaLang.fr).message, 'Old live est en direct maintenant.');
      // The reminder date falls back to the top-level scheduled_at.
      final AppNotification reminder = _parse(_payload('r', 'live_reminder', message: 'Limits starts at $_scheduled.', scheduledAt: _scheduled));
      expect(notificationText(reminder, NovaLang.en).message, 'Limits starts at $enDate (Algeria time).');
    });

    test('a notification without text shows its Live date or a generic line', () {
      final AppNotification scheduled = _parse(_payload('a', 'admin_message', message: '', scheduledAt: _scheduled));
      expect(emptyNotificationBody(scheduled, NovaLang.fr), 'Prévu le $frDate');
      final AppNotification bare = _parse(_payload('b', 'admin_message', message: ''));
      expect(emptyNotificationBody(bare, NovaLang.ar), 'تحديث جديد من نوفا');
    });

    test('live_reminder looks like the other Live notifications and opens its room', () {
      final AppNotification reminder = _parse(_payload('r', 'live_reminder', data: live, url: '/live/12'));
      final AppNotification scheduled = _parse(_payload('s', 'live_scheduled', data: live, liveId: 12, url: '/live/12'));
      expect(reminder.icon, Icons.alarm_rounded);
      expect(reminder.iconColor, scheduled.iconColor);
      expect(reminder.iconColor, NovaHue.sky.solid);
      expect(reminder.liveId, 12);
      expect(_parse(_payload('c', 'live_cancelled', data: live, url: '/account/lives')).liveId, isNull);
    });
  });

  group('History pagination', () {
    FakeBackend backend({int lastPage = 2}) => FakeBackend(<String, FakeResponse>{
          'GET /me/notifications?page=1': _page(_notices(1, 20), page: 1, lastPage: lastPage, unread: 7),
          // A new notification shifted every row by one: n20 comes again.
          'GET /me/notifications?page=2': _page(_notices(20, 25), page: 2, lastPage: lastPage, unread: 7),
          'PATCH /me/notifications/n1/read': const FakeResponse(204),
          'PATCH /me/notifications/read-all': const FakeResponse(204),
        });

    List<String> pages(FakeBackend b) => <String>[
          for (final FakeRequest r in b.requests)
            if (r.method == 'GET' && r.path == '/me/notifications') r.query,
        ];

    test('pages load in order without duplicates and a refresh restarts at page 1', () async {
      final FakeBackend b = backend();
      final AccountStore account = AccountStore(fakeApi(b));

      await account.refreshNotifications();
      expect(account.notifications, hasLength(20));
      expect(account.hasMoreNotifications, isTrue);
      // The bell shows the server count, not the unread rows listed.
      expect(account.unreadCount, 7);

      await account.loadMoreNotifications();
      expect(account.notifications.map((AppNotification n) => n.id).toList(),
          <String>[for (int i = 1; i <= 25; i++) 'n$i']);
      expect(account.hasMoreNotifications, isFalse);

      await account.loadMoreNotifications(); // Last page reached.
      expect(pages(b), <String>['page=1', 'page=2']);

      await account.refreshNotifications();
      expect(account.notifications, hasLength(20));
      expect(account.hasMoreNotifications, isTrue);
      expect(pages(b), <String>['page=1', 'page=2', 'page=1']);
    });

    test('mark-read and mark-all-read keep working on paged rows', () async {
      final FakeBackend b = backend();
      final AccountStore account = AccountStore(fakeApi(b));
      await account.refreshNotifications();

      await account.markRead(account.notifications.first);
      expect(account.notifications.first.read, isTrue);
      expect(account.unreadCount, 6);

      await account.markAllRead();
      expect(account.notifications.every((AppNotification n) => n.read), isTrue);
      expect(account.unreadCount, 0);
      expect(
        b.requests.where((FakeRequest r) => r.method == 'PATCH').map((FakeRequest r) => r.path),
        <String>['/me/notifications/n1/read', '/me/notifications/read-all'],
      );
    });

    testWidgets('the screen loads page 1 on open, more near the end, and page 1 on pull-to-refresh', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final FakeBackend b = backend();
      final AppState state = installFixtureApp(account: AccountStore(fakeApi(b)));

      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(theme: NovaTheme.light, home: const Scaffold(body: NotificationsScreen())),
      ));
      await tester.pumpAndSettle();
      expect(pages(b), <String>['page=1']);
      expect(find.text('Notice 1'), findsOneWidget);
      // Created 07:59 UTC → 08:59 in Algeria, whatever the machine zone.
      expect(find.text('26 Sept 2026, 08:59'), findsOneWidget);

      await tester.fling(find.byType(ListView), const Offset(0, -6000), 4000);
      await tester.pumpAndSettle();
      expect(pages(b), <String>['page=1', 'page=2']);
      expect(state.account.notifications, hasLength(25));

      await tester.scrollUntilVisible(
        find.text('You’re all caught up!'),
        400,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
      );
      expect(find.text('Notice 25'), findsOneWidget);

      await tester.fling(find.byType(ListView), const Offset(0, 20000), 6000);
      await tester.pumpAndSettle();
      await tester.fling(find.byType(ListView), const Offset(0, 500), 1000);
      await tester.pumpAndSettle();
      expect(pages(b), <String>['page=1', 'page=2', 'page=1']);
      expect(state.account.notifications, hasLength(20));
      expect(state.account.hasMoreNotifications, isTrue);
    });

    testWidgets('"Show more" loads the next page when the list does not scroll', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final FakeBackend b = FakeBackend(<String, FakeResponse>{
        'GET /me/notifications?page=1': _page(_notices(1, 2), page: 1, lastPage: 2),
        'GET /me/notifications?page=2': _page(_notices(3, 3), page: 2, lastPage: 2),
      });
      final AppState state = installFixtureApp(account: AccountStore(fakeApi(b)));

      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(theme: NovaTheme.light, home: const Scaffold(body: NotificationsScreen())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('You’re all caught up!'), findsNothing);

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(find.text('Notice 3'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
      expect(find.text('You’re all caught up!'), findsOneWidget);
      // Let the new rows' entrance delays run out.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  });

  group('Realtime notification banner', () {
    late List<MethodCall> chimes;

    setUp(() {
      installFixtureApp();
      NotificationChime.resetThrottle();
      chimes = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('nova/chime'),
        (MethodCall call) async {
          chimes.add(call);
          return true;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('nova/chime'), null);
    });

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NovaApp());
      await tester.pumpAndSettle();
    }

    final Map<String, Object?> started = _payload(
      'live-started-12',
      'live_started',
      title: 'Live started',
      message: 'Limits is live now.',
      data: <String, Object?>{'entity_type': 'LiveSession', 'entity_id': 12, 'live_title': 'Limits'},
      url: '/live/12',
    );

    testWidgets('NotificationCreated chimes, lists it and shows a 3-second banner over any screen', (tester) async {
      await pumpApp(tester);
      final AppState state = AppState.instance;
      final int unread = state.unreadCount;

      state.onNotificationCreated(Map<String, dynamic>.of(started));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Live started'), findsOneWidget);
      expect(find.text('Limits is live now.'), findsOneWidget);
      expect(chimes.map((MethodCall c) => c.method), <String>['play']);
      expect(state.account.notifications.first.id, 'live-started-12');
      expect(state.unreadCount, unread + 1);

      // The same broadcast again is neither listed nor announced twice.
      state.onNotificationCreated(Map<String, dynamic>.of(started));
      await tester.pump();
      expect(chimes, hasLength(1));
      expect(state.account.notifications.where((AppNotification n) => n.id == 'live-started-12'), hasLength(1));

      // The rest of the screen stays usable while the banner shows.
      await tester.tap(find.bySemanticsLabel('Explore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ExploreScreen), findsOneWidget);
      expect(find.text('Live started'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Live started'), findsNothing);
    });

    testWidgets('tapping the banner opens the notification like the list', (tester) async {
      await pumpApp(tester);
      final AppState state = AppState.instance;
      final int unread = state.unreadCount;

      state.onNotificationCreated(Map<String, dynamic>.of(_payload(
        'points-1',
        'points_credited',
        title: 'Points credited',
        message: '600 points were credited to your Nova balance.',
        data: <String, Object?>{'points': 600, 'balance': 1200},
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.unreadCount, unread + 1);
      final AppNotification arrived = state.account.notifications.first;

      await tester.tap(find.text('Points credited'));
      await tester.pumpAndSettle();
      expect(state.account.notifications.first.read, isTrue);
      expect(state.unreadCount, unread);
      expect(find.text('Points credited'), findsNothing);

      // Opening the same row again from the list counts it once.
      await state.account.markRead(arrived);
      expect(state.unreadCount, unread);
    });

    testWidgets('the banner speaks the app language and follows RTL', (tester) async {
      AppState.instance.setLang(NovaLang.ar);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('nova/chime'), null);
      await pumpApp(tester);

      // Without the platform side the chime fails silently.
      AppState.instance.onNotificationCreated(Map<String, dynamic>.of(started));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final Finder title = find.text('بدأت الحصة المباشرة');
      expect(title, findsOneWidget);
      expect(find.text('Limits مباشرة الآن.'), findsOneWidget);
      // The icon leads on the right in Arabic.
      final Finder icon = find.descendant(
        of: find.ancestor(of: title, matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.sensors_rounded),
      );
      expect(tester.getCenter(icon).dx, greaterThan(tester.getCenter(title).dx));

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  test('a fresh app starts in Arabic', () {
    expect(AppState.live().lang, NovaLang.ar);
    final AppState seeded = AppState.seeded(
      session: SessionStore.seeded(HomeData.student),
      catalog: CatalogStore.seeded(courses: const <Course>[], offers: const <Pack>[], teachers: const <Teacher>[]),
      learning: LearningStore.seeded(owned: const <Course>[], lives: const <LiveSession>[]),
      commerce: CommerceStore.seeded(),
      account: AccountStore.seeded(),
    );
    expect(seeded.lang, NovaLang.ar);
  });
}
