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

  group('PC app (Windows)', () {
    const String sha = 'a3f1c2d4e5b60718293a4b5c6d7e8f90112233445566778899aabbccddeeff00';

    StoreUpdates updates(Map<String, dynamic>? latest, _Memory memory, {String installed = '0.5.1+19', bool mandatory = false}) {
      _native((MethodCall _) => <String, Object?>{
            'version': <String, String>{'version': installed},
          });
      return StoreUpdates(
        channel: _channel,
        platform: TargetPlatform.windows,
        memory: memory,
        mandatory: mandatory,
        now: () => DateTime(2026, 10, 29, 12),
        fetchJson: (Uri uri) async {
          expect(uri.toString(), StoreUpdates.pcLatestUrl);
          return latest;
        },
      );
    }

    Map<String, dynamic> latest(String version, {String url = 'https://nova-elearning.com/downloads/pc/NOVA-Setup.exe', String hash = sha}) =>
        <String, dynamic>{'version': version, 'url': url, 'sha256': hash};

    test('a newer installer on the NOVA site is offered with its checksum', () async {
      final UpdateOffer? offer = await updates(latest('0.5.2+20'), _Memory()).check();
      expect(offer?.action, UpdateAction.prompt);
      expect(offer?.version, '0.5.2+20');
      expect(offer?.installerUrl.toString(), 'https://nova-elearning.com/downloads/pc/NOVA-Setup.exe');
      expect(offer?.sha256, sha);
      expect(offer?.storeUrl, isNull);
      // A new build of the same version counts too.
      expect(await updates(latest('0.5.1+20'), _Memory()).check(), isNotNull);
    });

    test('the same version, another host, plain HTTP or a bad checksum is never offered', () async {
      expect(await updates(latest('0.5.1+19'), _Memory()).check(), isNull);
      expect(await updates(latest('0.5.0+30'), _Memory()).check(), isNull);
      expect(await updates(latest('0.6.0+21', url: 'https://example.com/NOVA-Setup.exe'), _Memory()).check(), isNull);
      expect(await updates(latest('0.6.0+21', url: 'http://nova-elearning.com/NOVA-Setup.exe'), _Memory()).check(), isNull);
      expect(await updates(latest('0.6.0+21', hash: 'abc'), _Memory()).check(), isNull);
      expect(await updates(null, _Memory()).check(), isNull);
    });

    test('"Later" hides the PC version for three days', () async {
      final _Memory memory = _Memory();
      await updates(null, memory).declined('0.5.2+20');
      expect(await updates(latest('0.5.2+20'), memory).check(), isNull);
      expect(await updates(latest('0.5.3+21'), memory).check(), isNotNull);
    });

    test('D-194: a newer installer is required, even after "Later"', () async {
      final _Memory memory = _Memory();
      await updates(null, memory).declined('0.5.2+20');
      final UpdateOffer? offer = await updates(latest('0.5.2+20'), memory, mandatory: true).check();
      expect(offer?.required, isTrue);
      expect(offer?.installerUrl, isNotNull);
      // Never an untrusted or unverifiable installer, required or not.
      expect(await updates(latest('0.6.0+21', hash: 'abc'), _Memory(), mandatory: true).check(), isNull);
      expect(await updates(latest('0.5.1+19'), _Memory(), mandatory: true).check(), isNull);
    });

    test('installers come from the NOVA site only, over HTTPS', () {
      expect(StoreUpdates.trustedInstallerUrl(Uri.parse('https://nova-elearning.com/downloads/pc/a.exe')), isTrue);
      expect(StoreUpdates.trustedInstallerUrl(Uri.parse('https://cdn.nova-elearning.com/a.exe')), isTrue);
      expect(StoreUpdates.trustedInstallerUrl(Uri.parse('https://nova-elearning.com.evil.example/a.exe')), isFalse);
      expect(StoreUpdates.trustedInstallerUrl(Uri.parse('http://nova-elearning.com/a.exe')), isFalse);
    });
  });

  group('App Store (iPhone)', () {
    StoreUpdates updates(Map<String?, Map<String, dynamic>?> storefronts, _Memory memory, {DateTime? now, bool mandatory = false}) {
      _native(_iphone);
      return StoreUpdates(
        channel: _channel,
        platform: TargetPlatform.iOS,
        memory: memory,
        mandatory: mandatory,
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

    test('D-194: a newer store version is required, even after "Later"', () async {
      final _Memory memory = _Memory();
      await updates(const <String?, Map<String, dynamic>?>{}, memory).declined('1.1.0');
      final UpdateOffer? offer =
          await updates(<String?, Map<String, dynamic>?>{'dz': _lookup('1.1.0')}, memory, mandatory: true).check();
      expect(offer?.required, isTrue);
      expect(offer?.storeUrl.toString(), 'https://apps.apple.com/dz/app/nova/id123456789');
      // Not a version this iPhone cannot install, nor the installed one.
      expect(await updates(<String?, Map<String, dynamic>?>{'dz': _lookup('1.1.0', minimumOs: '18.0')}, _Memory(), mandatory: true).check(), isNull);
      expect(await updates(<String?, Map<String, dynamic>?>{'dz': _lookup('1.0.0')}, _Memory(), mandatory: true).check(), isNull);
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
      return StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: memory ?? _Memory(), mandatory: false);
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

    test('D-194: any update is required through Play\'s full-screen flow, or the Play Store page', () async {
      StoreUpdates required(Map<String, Object?> answers) {
        _native((_) => answers);
        return StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: _Memory(), mandatory: true);
      }

      final UpdateOffer? immediate = await required(_play()).check();
      expect(immediate?.action, UpdateAction.immediate);
      expect(immediate?.required, isTrue);
      final Map<String, Object?> flexibleOnly = _play();
      (flexibleOnly['info']! as Map<String, Object?>)['immediate'] = false;
      final UpdateOffer? store = await required(flexibleOnly).check();
      expect(store?.required, isTrue);
      expect(store?.storeUrl.toString(), 'https://play.google.com/store/apps/details?id=dz.nova.nova_mobile');
      expect(await required(_play(available: false)).check(), isNull);
    });

    test('D-194: required by default in this build', () {
      expect(StoreUpdates.mandatoryUpdates, isTrue);
      expect(StoreUpdates(channel: _channel).mandatory, isTrue);
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
          mandatory: false,
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
          mandatory: false,
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
      await pumpGate(tester, StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: _Memory(), mandatory: false));

      expect(calls.map((MethodCall c) => c.method), <String>['info', 'start']);
      expect(calls.last.arguments, <String, bool>{'immediate': false});

      sink()!.success(<String, Object>{'status': 'downloaded', 'downloaded': 10, 'total': 10});
      await tester.pumpAndSettle();
      expect(find.text('Update ready'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'complete');
    });

    testWidgets('D-194 iPhone: the required page covers the app until the App Store opens; no "Later"', (tester) async {
      _native(_iphone);
      final List<Uri> opened = <Uri>[];
      await pumpGate(
        tester,
        StoreUpdates(channel: _channel, platform: TargetPlatform.iOS, memory: _Memory(), mandatory: true, fetchJson: (Uri _) async => _lookup('1.1.0')),
        launch: (Uri url) async {
          opened.add(url);
          return true;
        },
      );
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      // The app below takes no tap.
      expect(find.text('home').hitTestable(), findsNothing);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://apps.apple.com/dz/app/nova/id123456789');
      // Still required when the Student comes back without updating.
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('D-194 Android: Play\'s full-screen flow first; cancelled, the required page retries it', (tester) async {
      final List<MethodCall> calls = <MethodCall>[];
      _native((_) => _play(start: 'canceled'), calls);
      await pumpGate(tester, StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: _Memory(), mandatory: true));
      expect(calls.map((MethodCall c) => c.method), <String>['info', 'start']);
      expect(calls.last.arguments, <String, bool>{'immediate': true});
      expect(find.text('Update required'), findsOneWidget);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(calls.map((MethodCall c) => c.method), <String>['info', 'start', 'info', 'start']);
      expect(calls.last.arguments, <String, bool>{'immediate': true});
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('Android: declining Play\'s dialog is remembered', (tester) async {
      _native((_) => _play(start: 'canceled'));
      _mockInstallStates();
      final _Memory memory = _Memory();
      await pumpGate(tester, StoreUpdates(channel: _channel, platform: TargetPlatform.android, memory: memory, mandatory: false));
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
