import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/security/device_measurement.dart';

import 'fixtures/fake_api.dart';

/// D-168 phase 1a: the phone measurement (once per app version, silent,
/// never while a video plays, nothing sent when the server switched it off).

class _Memory implements MeasurementMemory {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const MethodChannel _measure = MethodChannel('test/measure');
const MethodChannel _appInfo = MethodChannel('test/app_info');

Map<String, Object?> _config({bool testVideo = true, String? project, bool appAttest = false, bool enabled = true}) =>
    <String, Object?>{
      'data': <String, Object?>{
        'enabled': enabled,
        'revision': '1${testVideo ? 'v' : ''}',
        'test_video': testVideo,
        'play_integrity': project == null ? null : <String, String>{'cloud_project_number': project},
        'app_attest': appAttest,
      },
    };

Map<String, Object?> _authorization({bool fairplay = false}) => <String, Object?>{
      'data': <String, Object?>{
        'mode': 'protected',
        'manifests': <String, String>{'dash': 'https://cdn.test/dash/manifest.mpd', 'hls': 'https://cdn.test/hls/master.m3u8'},
        'drm': <String, Object?>{
          'token': 'entitlement',
          'license_urls': <String, String>{
            'widevine': 'https://widevine.test',
            if (fairplay) 'fairplay': 'https://fairplay.test',
          },
          if (fairplay) 'fairplay_certificate_url': 'https://fairplay.test/cert',
        },
      },
    };

const Map<String, Object?> _l1Phone = <String, Object?>{
  'model': 'samsung SM-A515F',
  'osVersion': '14',
  'sdkInt': 34,
  'securityLevel': 'L1',
  'maxHdcp': '2.2',
  'connectedHdcp': 'no_output',
  'secureDecoder1080p': true,
  'secureDecoder': 'c2.exynos.h264.decoder.secure',
  'googlePlayServices': true,
  'gmsVersion': 251234000,
  'playStore': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<MethodCall> calls = <MethodCall>[];
  late List<Map<String, Object?>> tests;
  late Map<String, Object?> phone;
  late _Memory memory;

  setUp(() {
    calls.clear();
    tests = <Map<String, Object?>>[];
    phone = Map<String, Object?>.of(_l1Phone);
    memory = _Memory();
    final TestDefaultBinaryMessengerBinding binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_measure, (MethodCall call) async {
      calls.add(call);
      return switch (call.method) {
        'snapshot' => phone,
        'testPlayback' => tests.isEmpty ? <String, Object?>{'result': 'passed'} : tests.removeAt(0),
        'integrity' => <String, Object?>{'token': 'integrity.token-1'},
        _ => null,
      };
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _appInfo,
      (MethodCall call) async => <String, String>{'version': '0.6.0', 'build': '20'},
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final TestDefaultBinaryMessengerBinding binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_measure, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_appInfo, null);
  });

  DeviceMeasurement service(FakeBackend backend, {bool busy = false}) => DeviceMeasurement(
        fakeApi(backend),
        channel: _measure,
        appInfo: _appInfo,
        memory: memory,
        playerBusy: () => busy,
      );

  FakeBackend backend(Map<String, Object?> config) => FakeBackend(<String, FakeResponse>{
        'GET /app-measurements/config': FakeResponse(200, config),
        'POST /device-check/playback': FakeResponse(200, _authorization()),
        'POST /app-measurements/software-playback': FakeResponse(200, _authorization()),
        'POST /app-measurements': const FakeResponse(204),
      });

  List<FakeRequest> reports(FakeBackend api) =>
      api.requests.where((FakeRequest r) => r.method == 'POST' && r.path == '/app-measurements').toList();

  test('an L1 Android phone plays the hardware and the forced L3 test and reports once per version', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final FakeBackend api = backend(_config(project: '123456789012'));
    tests = <Map<String, Object?>>[
      <String, Object?>{'result': 'passed', 'decoder': 'c2.exynos.h264.decoder.secure'},
      <String, Object?>{'result': 'failed', 'error': 'license', 'code': 6004},
    ];

    final Map<String, dynamic>? sent = await service(api).measureIfDue(7);

    final List<MethodCall> playbacks = calls.where((MethodCall c) => c.method == 'testPlayback').toList();
    expect(playbacks.map((MethodCall c) => (c.arguments as Map)['forceL3']), <bool>[false, true]);
    expect((playbacks.first.arguments as Map)['manifest'], 'https://cdn.test/dash/manifest.mpd');
    expect((playbacks.first.arguments as Map)['license'], 'https://widevine.test');
    expect((playbacks.first.arguments as Map)['token'], 'entitlement');
    final MethodCall integrity = calls.singleWhere((MethodCall c) => c.method == 'integrity');
    expect((integrity.arguments as Map)['cloudProjectNumber'], '123456789012');
    final String hash = (integrity.arguments as Map)['requestHash'] as String;
    expect(hash, matches(RegExp(r'^[a-f0-9]{64}$')));

    expect(reports(api), hasLength(1));
    expect(reports(api).single.data, sent);
    expect(sent, <String, Object>{
      'platform': 'android',
      'app_version': '0.6.0+20',
      'device_model': 'samsung SM-A515F',
      'os_version': '14',
      'sdk_int': 34,
      'security_level': 'L1',
      'max_hdcp': '2.2',
      'connected_hdcp': 'no_output',
      'secure_decoder_1080p': true,
      'secure_decoder': 'c2.exynos.h264.decoder.secure',
      'google_play_services': true,
      'gms_version': 251234000,
      'play_store': true,
      'hardware_test': 'passed',
      'software_test': 'failed',
      'software_test_error': 'license',
      'software_test_code': 6004,
      'integrity_token': 'integrity.token-1',
      'integrity_request_hash': hash,
    });
    expect(api.requests.where((FakeRequest r) => r.path == '/device-check/playback'), hasLength(1));
    expect(api.requests.where((FakeRequest r) => r.path == '/app-measurements/software-playback'), hasLength(1));

    // Same version and server revision: nothing is measured again, even after a relaunch.
    calls.clear();
    expect(await service(api).measureIfDue(7), isNull);
    expect(calls.where((MethodCall c) => c.method == 'snapshot'), isEmpty);
    expect(reports(api), hasLength(1));
    // The hidden debug action measures anyway; another account measures too.
    expect(await service(api).runNow(7), isNotNull);
    expect(await service(api).measureIfDue(8), isNotNull);
    expect(reports(api), hasLength(3));
  });

  test('an L3 phone skips the hardware test, a phone without Widevine plays nothing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final FakeBackend api = backend(_config());
    phone['securityLevel'] = 'L3';

    final Map<String, dynamic>? l3 = await service(api).measureIfDue(7);
    expect(l3!['hardware_test'], 'skipped');
    expect(l3['hardware_test_error'], 'not_l1');
    expect(l3['software_test'], 'passed');
    expect(l3.containsKey('integrity_token'), isFalse);
    expect(calls.where((MethodCall c) => c.method == 'integrity'), isEmpty);
    expect(calls.where((MethodCall c) => c.method == 'testPlayback'), hasLength(1));

    calls.clear();
    phone.remove('securityLevel');
    final Map<String, dynamic>? none = await service(api).runNow(7);
    expect(<Object?>[none!['hardware_test'], none['hardware_test_error'], none['software_test'], none['software_test_error']],
        <Object?>['unavailable', 'no_widevine', 'unavailable', 'no_widevine']);
    expect(none.containsKey('security_level'), isFalse);
    expect(calls.where((MethodCall c) => c.method == 'testPlayback'), isEmpty);
  });

  test('without the test video on the server the phone still reports its DRM, without playing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final FakeBackend api = backend(_config(testVideo: false));

    final Map<String, dynamic>? sent = await service(api).measureIfDue(7);
    expect(<Object?>[sent!['hardware_test'], sent['hardware_test_error'], sent['software_test']],
        <Object?>['unavailable', 'no_test_video', 'unavailable']);
    expect(calls.where((MethodCall c) => c.method == 'testPlayback'), isEmpty);
    expect(api.requests.where((FakeRequest r) => r.path.contains('playback')), isEmpty);
  });

  test('nothing is measured or sent while a video plays, when a test is interrupted or when the server says no', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final FakeBackend busy = backend(_config());
    final DeviceMeasurement waiting = service(busy, busy: true);
    expect(await waiting.measureIfDue(7), isNull);
    waiting.cancel();
    expect(calls, isEmpty);
    expect(reports(busy), isEmpty);

    tests = <Map<String, Object?>>[<String, Object?>{'result': 'inconclusive', 'error': 'interrupted'}];
    final FakeBackend interrupted = backend(_config());
    final DeviceMeasurement cut = service(interrupted);
    expect(await cut.measureIfDue(7), isNull);
    cut.cancel();
    expect(reports(interrupted), isEmpty);
    expect(memory.values, isEmpty);

    calls.clear();
    final FakeBackend off = backend(_config(enabled: false));
    expect(await service(off).measureIfDue(7), isNull);
    expect(calls, isEmpty);
    expect(reports(off), isEmpty);
  });

  test('an iPhone plays the FairPlay test and reports App Attest support when asked', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final FakeBackend api = FakeBackend(<String, FakeResponse>{
      'GET /app-measurements/config': FakeResponse(200, _config(appAttest: true, project: '123456789012')),
      'POST /device-check/playback': FakeResponse(200, _authorization(fairplay: true)),
      'POST /app-measurements': const FakeResponse(204),
    });
    phone = <String, Object?>{'model': 'iPhone14,5', 'osVersion': '17.5.1', 'fairplay': true, 'appAttestSupported': true};

    final Map<String, dynamic>? sent = await service(api).measureIfDue(7);

    final MethodCall playback = calls.singleWhere((MethodCall c) => c.method == 'testPlayback');
    expect((playback.arguments as Map)['manifest'], 'https://cdn.test/hls/master.m3u8');
    expect((playback.arguments as Map)['license'], 'https://fairplay.test');
    expect((playback.arguments as Map)['certificate'], 'https://fairplay.test/cert');
    expect((calls.first.arguments as Map)['appAttest'], isTrue);
    expect(calls.where((MethodCall c) => c.method == 'integrity'), isEmpty);
    expect(sent, <String, Object>{
      'platform': 'ios',
      'app_version': '0.6.0+20',
      'device_model': 'iPhone14,5',
      'os_version': '17.5.1',
      'hardware_test': 'passed',
      'software_test': 'skipped',
      'app_attest_supported': true,
    });
    expect(reports(api), hasLength(1));
  });
}
