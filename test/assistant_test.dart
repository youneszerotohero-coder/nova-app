import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/i18n/nova_strings.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/data/assistant_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/features/assistant/assistant_screen.dart';
import 'package:nova_mobile/features/catalog/units_catalog_screen.dart';
import 'package:nova_mobile/features/detail/course_detail_screen.dart';
import 'package:nova_mobile/features/shell/shell_screen.dart';
import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'fixtures/fixture_data.dart';
import 'nova_font_loader.dart';

Map<String, Object?> envelope(List<Map<String, Object?>> messages) => <String, Object?>{
      'data': <String, Object?>{'messages': messages},
    };

Map<String, Object?> textMessage(int id, String role, String text) => <String, Object?>{
      'id': id,
      'role': role,
      'blocks': <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    };

void main() {
  setUpAll(loadNovaFonts);

  group('AssistantStore (D-150)', () {
    test('a signed-in Student reads and writes /me/assistant; the reply replaces the shown message', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /me/assistant': FakeResponse(200, envelope(<Map<String, Object?>>[textMessage(1, 'assistant', 'Hello')])),
        'POST /me/assistant/messages': FakeResponse(200, envelope(<Map<String, Object?>>[
          textMessage(2, 'student', 'Where is my Unit?'),
          <String, Object?>{
            'id': 3,
            'role': 'assistant',
            'blocks': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': 'Here it is'},
              <String, Object?>{'type': 'link', 'target': 'my_courses', 'href': '/account/enrollments'},
              <String, Object?>{'type': 'secret'},
            ],
          },
        ])),
      });
      final AssistantStore store = AssistantStore(fakeApi(backend), signedIn: true);
      await store.load();
      expect(store.loaded, isTrue);
      expect(store.messages.single.student, isFalse);

      final Future<String?> sending = store.send('  Where is my Unit?  ');
      // Shown at once, before the server answers.
      expect(store.messages.last.pending, isTrue);
      expect(store.sending, isTrue);
      expect(await sending, isNull);

      final FakeRequest post = backend.requests.lastWhere((FakeRequest r) => r.method == 'POST');
      expect(post.path, '/me/assistant/messages');
      expect(post.data, <String, Object>{'text': 'Where is my Unit?'});
      expect(store.messages.map((AssistantMessage m) => m.id), <String>['1', '2', '3']);
      expect(store.messages.any((AssistantMessage m) => m.pending), isFalse);
      // Blocks the app does not show (the sandbox's) are left out.
      expect(store.messages.last.blocks.map((AssistantBlock b) => b.type), <String>['text', 'link']);
      expect(store.sending, isFalse);
    });

    test('a visitor uses /assistant/visitor; a refused message comes back with its error; reset forgets the chat', () async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /assistant/visitor': FakeResponse(200, envelope(<Map<String, Object?>>[textMessage(1, 'student', 'Hi')])),
        'POST /assistant/visitor/messages': const FakeResponse(429, <String, Object?>{
          'error': <String, String>{'code': 'ASSISTANT_DAILY_LIMIT', 'message': 'limit'},
        }),
        'DELETE /assistant/visitor': const FakeResponse(204),
      });
      final AssistantStore store = AssistantStore(fakeApi(backend), signedIn: false);
      await store.load();
      expect(await store.send('Which Offers?'), 'Which Offers?');
      expect(store.error?.code, 'ASSISTANT_DAILY_LIMIT');
      expect(store.loadFailed, isFalse);
      expect(store.messages.single.id, '1');

      await store.reset();
      expect(backend.requests.last.method, 'DELETE');
      expect(backend.requests.last.path, '/assistant/visitor');
      expect(store.messages, isEmpty);
      expect(store.error, isNull);
    });
  });

  group('assistant text', () {
    test('paragraphs, bullets and marks as on the website', () {
      final List<AssistantLine> lines = assistantLines('First\n\n- one\n* two\nAfter');
      expect(lines.map((AssistantLine l) => l.text), <String>['First', 'one', 'two', 'After']);
      expect(lines.map((AssistantLine l) => l.bullet), <bool>[false, true, true, false]);
      expect(lines.map((AssistantLine l) => l.gap), <bool>[false, true, false, true]);

      final List<InlineSpan> spans = assistantSpans('Pay **by CCP** then *wait* for `24 h`');
      expect(spans.map((InlineSpan s) => (s as TextSpan).text), <String>['Pay ', 'by CCP', ' then ', 'wait', ' for ', '24 h']);
      expect((spans[1] as TextSpan).style?.fontWeight, FontWeight.w700);
      expect((spans[3] as TextSpan).style?.fontStyle, FontStyle.italic);

      expect(assistantTextDirection('مرحبا NOVA'), TextDirection.rtl);
      expect(assistantTextDirection('NOVA مرحبا'), TextDirection.ltr);
      expect(assistantTextDirection('2500 DZD'), TextDirection.ltr);
      expect(assistantTextDirection('2500'), isNull);
    });
  });

  group('assistant screen', () {
    Future<void> pump(WidgetTester tester, Widget home, {NovaLang lang = NovaLang.en}) async {
      final AppState state = installFixtureApp(lang: lang);
      AppState.instance = state;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: NovaTheme.light,
            locale: lang.locale,
            supportedLocales: const <Locale>[Locale('en'), Locale('fr'), Locale('ar')],
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: home,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('welcome and suggestions; a suggestion is sent; the reply shows its card and link, which open their screens', (WidgetTester tester) async {
      final Course course = HomeData.popularCourses.firstWhere((Course c) => !c.owned);
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /me/assistant': FakeResponse(200, envelope(<Map<String, Object?>>[])),
        'POST /me/assistant/messages': FakeResponse(200, envelope(<Map<String, Object?>>[
          textMessage(2, 'student', 'How do I buy an Offer?'),
          <String, Object?>{
            'id': 3,
            'role': 'assistant',
            'blocks': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': 'Pick a **Unit**:\n- add it to the cart\n- pay by CCP'},
              <String, Object?>{
                'type': 'product', 'kind': 'course', 'id': course.id, 'title': course.title, 'subtitle': 'Teacher',
                'cover_url': null, 'price': '2500.00', 'currency': 'DZD', 'owned': false, 'href': '/courses/${course.slug}',
              },
              <String, Object?>{'type': 'link', 'target': 'courses', 'href': '/courses'},
              <String, Object?>{
                'type': 'order', 'order_number': 'NV-12', 'title': 'Maths', 'amount': '4800.00', 'currency': 'DZD',
                'state': 'pending_review', 'href': '/account/orders',
              },
            ],
          },
        ])),
      });
      final AssistantStore store = AssistantStore(fakeApi(backend), signedIn: true);
      await pump(tester, AssistantScreen(store: store));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('NOVA assistant'), findsOneWidget);
      expect(find.textContaining('Ask me anything about NOVA'), findsOneWidget);
      expect(find.text('I paid but I don’t see my Unit'), findsOneWidget);

      await tester.tap(find.text('How do I buy an Offer?'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Ask me anything about NOVA'), findsNothing);
      expect(find.text('add it to the cart'), findsOneWidget);
      expect(find.text(course.title), findsOneWidget);
      expect(find.text('2,500 DZD'), findsOneWidget);
      expect(find.text('All Units'), findsOneWidget);
      expect(find.text('Order NV-12'), findsOneWidget);
      expect(find.text('4,800 DZD · Receipt under review'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('All Units'));
      await tester.tap(find.text('All Units'));
      // A new route is offstage for its first frame (heroes).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(UnitsCatalogScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(UnitsCatalogScreen))).pop();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.ensureVisible(find.text('View'));
      await tester.tap(find.text('View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CourseDetailScreen), findsOneWidget);
    });

    testWidgets('a refused message is put back in the composer with the reason, in Arabic', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend(<String, FakeResponse>{
        'GET /assistant/visitor': FakeResponse(200, envelope(<Map<String, Object?>>[])),
        'POST /assistant/visitor/messages': const FakeResponse(429, <String, Object?>{
          'error': <String, String>{'code': 'ASSISTANT_DAILY_LIMIT', 'message': 'limit'},
        }),
      });
      final AssistantStore store = AssistantStore(fakeApi(backend), signedIn: false);
      await pump(tester, AssistantScreen(store: store), lang: NovaLang.ar);
      await tester.pump(const Duration(milliseconds: 300));

      // The visitor's suggestions.
      expect(find.text(K['assistant.suggestLevel']!['ar']!), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'سلام');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(K['assistant.dailyLimit']!['ar']!), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'سلام');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Student space shows no assistant button in an offline preview', (WidgetTester tester) async {
      await pump(tester, const ShellScreen());
      expect(find.byType(AssistantFab), findsNothing);
    });
  });
}
