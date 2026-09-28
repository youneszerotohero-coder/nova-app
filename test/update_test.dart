import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/update/app_update_gate.dart';
import 'package:nova_mobile/core/update/store_updates.dart';

import 'fixtures/fixture_app.dart';
import 'nova_font_loader.dart';

class _Memory implements UpdateMemory {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const MethodChannel _channel = MethodChannel('test/app_update');

/// The App Store lookup answer for one storefront.
Map<String, dynamic> _lookup(String version, {String minimumOs = '15.0'}) => <String, dynamic>{
      'resultCount': 1,
      'results': <Object>[
        <String, Object>{
          'version': version,
          'trackViewUrl': 'https://apps.apple.com/dz/app/nova/id123456789',
          'minimumOsVersion': minimumOs,
        },
      ],
    };

void _native(Map<String, Object?> Function(MethodCall call) answer, [List<MethodCall>? calls]) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _channel,
    (MethodCall call) async {
      calls?.add(call);
      return answer(call)[call.method];
    },
  );
}

Map<String, Object?> _iphone(MethodCall _) => <String, Object?>{
      'version': <String, String>{'bundleId': 'dz.nova.novaMobile', 'version': '1.0.0', 'build': '3', 'osVersion': '17.4'},
    };

Map<String, Object?> _play({
  bool available = true,
  int priority = 0,
  bool downloaded = false,
  String start = 'ok',
}) =>
    <String, Object?>{
      'info': <String, Object?>{
        'available': available,
        'inProgress': false,
        'downloaded': downloaded,
        'versionCode': 7,
        'priority': priority,
        'flexible': true,
        'immediate': true,
      },
      'start': start,
      'complete': null,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test('versions compare numerically, part by part', () {
    expect(compareVersions('1.10.0', '1.9.2'), greaterThan(0));
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('2.0.0', '10.0'), lessThan(0));
    expect(compareVersions('1.0.1+5', '1.0.1'), greaterThan(0));
  });

  group('App Store (iPhone)', () {
    StoreUpdates updates(Map<String?, Map<String, dynamic>?> storefronts, _Memory memory, {DateTime? now}) {
      _native(_iphone);
      return StoreUpdates(
        channel: _channel,
        platform: TargetPlatform.iOS,
        memory: memory,
        now: () => now ?? DateTime(2026, 9, 26, 12),
        fetchJson: (Uri uri) async {
          expect(uri.host, 'itunes.apple.com');
          expect(uri.queryParameters['bundleId'], 'dz.nova.novaMobile');
          return storefronts[uri.queryParameters['country']];
        },
      );
    }

    test('a newer store version is offered with its App Store page', () async {
      final UpdateOffer? offer = await updates(<String?, Map<String, dynamic>?>{'dz': _lookup('1.1.0')}, _Memory()).check();
      expect(offer?.action, UpdateAction.prompt);
      expect(offer?.version, '1.1.0');
      expect(offer?.storeUrl.toString(), 'https://apps.apple.com/dz/app/nova/id123456789');
    });

    test('the default storefront is used when Algeria has no listing', () async {
      final UpdateOffer? offer = await updates(
        <String?, Map<String, dynamic>?>{'dz': <String, dynamic>{'resultCount': 0, 'results': <Object>[]}, null: _lookup('1.0.2')},
        _Memory(),
      ).check();
      expect(offer?.version, '1.0.2');
    });

    test('the same version, or one this iPhone cannot install, is not offered', () async {
      expect(await updates(<String?, Map<String, dynamic>?>{'dz': _lookup('1.0.0')}, _Memory()).check(), isNull);
      expect(
        await updates(<String?, Map<String, dynamic>?>{'dz': _lookup('1.1.0', minimumOs: '18.0')}, _Memory()).check(),
        isNull,
      );
    });

    test('"Later" hides a version for three days', () async {
      final _Memory memory = _Memory();
      final DateTime declinedAt = DateTime(2026, 9, 26, 12);
      await updates(<String?, Map<String, dynamic>?>{}, memory, now: declinedAt).declined('1.1.0');

      final Map<String?, Map<String, dynamic>?> store = <String?, Map<String, dynamic>?>{'dz': _lookup('1.1.0')};
      expect(await updates(store, memory, now: declinedAt.add(const Duration(days: 2))).check(), isNull);
      expect(await updates(store, memory, now: declinedAt.add(const Duration(days: 3))).check(), isNotNull);
      // A newer version than the declined one is offered at once.
      expect(
        await updates(<String?, Map<String, dynamic>?>{'dz': _lookup('1.2.0')}, memory, now: declinedAt).check(),
        isNotNull,
      );
    });
  });

  group('Google Play (Android)', () {
    StoreUpdates updates(Map<String, Object?> answers, [_Memory? memory]) {
      _native((_) => answers);
      return StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: memory ?? _Memory());
    }

    test('an update is offered through the flexible flow', () async {
      final UpdateOffer? offer = await updates(_play()).check();
      expect(offer?.action, UpdateAction.prompt);
      expect(offer?.storeUrl, isNull);
    });

    test('a high-priority release uses the immediate flow', () async {
      expect((await updates(_play(priority: 4)).check())?.action, UpdateAction.immediate);
    });

    test('a downloaded update offers a restart; none when Play has nothing', () async {
      expect((await updates(_play(downloaded: true)).check())?.action, UpdateAction.restart);
      expect(await updates(_play(available: false)).check(), isNull);
    });

    test('no plugin (tests, other platforms) means no offer', () async {
      expect(
        await StoreUpdates(channel: const MethodChannel('nothing/here'), platform: TargetPlatform.android).check(),
        isNull,
      );
    });
  });

  group('Update gate', () {
    setUpAll(loadNovaFonts);

    Future<GlobalKey<NavigatorState>> pumpGate(WidgetTester tester, StoreUpdates updates, {Future<bool> Function(Uri)? launch}) async {
      final AppState app = installFixtureApp();
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
          navigatorKey: navigator,
          theme: NovaTheme.light,
          builder: (BuildContext context, Widget? child) => AppUpdateGate(
            navigatorKey: navigator,
            updates: updates,
            launch: launch,
            child: child!,
          ),
          home: const Scaffold(body: Text('home')),
        ),
      ));
      await tester.pump(AppUpdateGate.firstCheckDelay);
      await tester.pumpAndSettle();
      return navigator;
    }

    testWidgets('iPhone: the sheet opens the App Store page', (tester) async {
      _native(_iphone);
      final List<Uri> opened = <Uri>[];
      await pumpGate(
        tester,
        StoreUpdates(
          channel: _channel,
          platform: TargetPlatform.iOS,
          memory: _Memory(),
          fetchJson: (Uri _) async => _lookup('1.1.0'),
        ),
        launch: (Uri url) async {
          opened.add(url);
          return true;
        },
      );

      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('NOVA 1.1.0 is available'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://apps.apple.com/dz/app/nova/id123456789');
    });

    testWidgets('iPhone: "Later" is remembered for that version', (tester) async {
      _native(_iphone);
      final _Memory memory = _Memory();
      await pumpGate(
        tester,
        StoreUpdates(
          channel: _channel,
          platform: TargetPlatform.iOS,
          memory: memory,
          fetchJson: (Uri _) async => _lookup('1.1.0'),
        ),
      );
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(memory.values['nova.update.declined'], startsWith('1.1.0|'));
    });

    testWidgets('Android: Play downloads, then the Student restarts to install', (tester) async {
      final List<MethodCall> calls = <MethodCall>[];
      _native((_) => _play(), calls);
      final MockStreamHandlerEventSink? Function() sink = _mockInstallStates();
      await pumpGate(tester, StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: _Memory()));

      expect(calls.map((MethodCall c) => c.method), <String>['info', 'start']);
      expect(calls.last.arguments, <String, bool>{'immediate': false});

      sink()!.success(<String, Object>{'status': 'downloaded', 'downloaded': 10, 'total': 10});
      await tester.pumpAndSettle();
      expect(find.text('Update ready'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'complete');
    });

    testWidgets('Android: declining Play\'s dialog is remembered', (tester) async {
      _native((_) => _play(start: 'canceled'));
      _mockInstallStates();
      final _Memory memory = _Memory();
      await pumpGate(tester, StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: memory));
      expect(memory.values['nova.update.declined'], startsWith('7|'));
    });
  });
}

/// Fakes Play's install-state stream; returns the sink once listened to.
MockStreamHandlerEventSink? Function() _mockInstallStates() {
  MockStreamHandlerEventSink? sink;
  const EventChannel channel = EventChannel('nova/app_update/events');
  final TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockStreamHandler(
    channel,
    MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink events) {
      sink = events;
    }),
  );
  addTearDown(() => messenger.setMockStreamHandler(channel, null));
  return () => sink;
}
