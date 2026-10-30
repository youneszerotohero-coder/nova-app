import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/json.dart';
import '../api/api_exception.dart';
import '../api/nova_api.dart';
import '../utils/screen_awake.dart';

/// Where the last measured `version|revision|account` is remembered.
abstract interface class MeasurementMemory {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class _SecureMeasurementMemory implements MeasurementMemory {
  const _SecureMeasurementMemory();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

/// One test playback: `passed`, `failed`, `inconclusive` (no decoded
/// picture confirmed), `unavailable` (no test video, no DRM) or `skipped`
/// (not for this phone), with the player's error category and code.
class MeasuredTest {
  const MeasuredTest(this.result, {this.error, this.code});

  factory MeasuredTest.fromNative(Map<String, dynamic>? value) {
    final String result = '${value?['result'] ?? ''}';
    return MeasuredTest(
      _results.contains(result) ? result : 'inconclusive',
      error: _code(value?['error']) ?? (_results.contains(result) ? null : 'no_answer'),
      code: value?['code'] is num ? (value!['code'] as num).toInt() : null,
    );
  }

  static const Set<String> _results = <String>{'passed', 'failed', 'inconclusive', 'unavailable', 'skipped'};

  final String result;
  final String? error;
  final int? code;

  /// The backend accepts lower-case codes only (`StoreDeviceMeasurementRequest`).
  static String? _code(Object? value) {
    final String text = '${value ?? ''}'.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '_');
    return RegExp(r'^[a-z][a-z0-9_]{0,23}$').hasMatch(text) ? text : null;
  }
}

/// D-168 phase 1a: once per app version, the app silently measures what
/// this phone can do with DRM and reports it to `POST /app-measurements`,
/// so the owner can decide with real numbers before the apps require DRM
/// again (docs/phase1-drm-measurement.md). Nothing here changes playback,
/// shows anything or blocks the UI: it starts [delay] after the Student's
/// session is ready, waits while a video plays, and any failure is dropped
/// (it is tried again at the next launch).
///
/// Android (`nova/measure`, `DeviceMeasurement.kt`): Widevine level, HDCP,
/// secure H.264 1080p decoder, Google Play services, then a short muted
/// playback of the `/device-check` test pattern with the mode A licence
/// (L1 phones) and forced to Widevine L3 (`/app-measurements/software-playback`),
/// and a Play Integrity verdict when the server configured it. iPhone
/// (`DeviceMeasurement.swift`): a short FairPlay playback of the test
/// pattern, and App Attest support when the server configured it.
class DeviceMeasurement {
  DeviceMeasurement(
    this._api, {
    MethodChannel? channel,
    MethodChannel? appInfo,
    MeasurementMemory? memory,
    this.delay = const Duration(seconds: 45),
    this.retryAfter = const Duration(minutes: 3),
    bool Function()? playerBusy,
  })  : _channel = channel ?? const MethodChannel('nova/measure'),
        _appInfo = appInfo ?? const MethodChannel('nova/app_update'),
        _memory = memory ?? const _SecureMeasurementMemory(),
        _playerBusy = playerBusy ?? (() => ScreenAwake.held);

  static const String doneKey = 'nova.measure.done';

  /// Test playbacks give up after this long (the native side stops too).
  static const Duration testTimeout = Duration(seconds: 30);

  final NovaApi _api;
  final MethodChannel _channel;
  final MethodChannel _appInfo;
  final MeasurementMemory _memory;
  final bool Function() _playerBusy;
  final Duration delay;
  final Duration retryAfter;

  Timer? _timer;
  int? _user;
  Future<Json?>? _running;

  /// The account this app process is done with (measured, already measured
  /// or refused for good): later session changes do not ask again.
  int? _settled;

  /// Runs put off in this app process (video playing, test interrupted).
  int _deferrals = 0;

  /// After this many put-off runs, the next app launch tries again.
  static const int maxDeferrals = 5;

  /// Test outcomes that say nothing about the phone: the run is put off.
  static const Set<String> _transient = <String>{'interrupted', 'other_audio', 'authorization'};

  /// Only the phone apps measure (not tests, the web or a desktop build).
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// The Student [userId] is signed in past every required step: measure
  /// after [delay] if this app version was not measured for them yet.
  void schedule(int userId) {
    if (_settled == userId || (_user == userId && (_timer != null || _running != null))) return;
    cancel();
    _user = userId;
    _timer = Timer(delay, () {
      _timer = null;
      _run(force: false);
    });
  }

  /// What [schedule]'s timer does: measures [userId] now unless this app
  /// version (and server revision) was already measured for them.
  @visibleForTesting
  Future<Json?> measureIfDue(int userId) {
    _timer?.cancel();
    _timer = null;
    _user = userId;
    return _run(force: false);
  }

  /// Signed out (or a Teacher): nothing more is measured or sent.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _user = null;
  }

  /// The hidden debug action: measures now, even an app version already
  /// measured, and answers what was sent (null when nothing could be).
  Future<Json?> runNow(int userId) {
    _timer?.cancel();
    _timer = null;
    _user = userId;
    return _run(force: true);
  }

  Future<Json?> _run({required bool force}) =>
      _running ??= _measure(force: force).whenComplete(() => _running = null);

  Future<Json?> _measure({required bool force}) async {
    final int? user = _user;
    if (user == null) return null;
    String? done;
    try {
      final Json config = (await _api.get('/app-measurements/config')).obj('data') ?? <String, dynamic>{};
      if (_user != user) return null;
      if (config['enabled'] != true) {
        _settled = user;
        return null;
      }
      final String version = await _appVersion();
      done = '$version|${config.str('revision')}|$user';
      if (!force && await _memory.read(doneKey) == done) {
        _settled = user;
        return null;
      }
      // A video plays: its decoder and bandwidth come first.
      if (!force && _playerBusy()) return _putOff(user);

      final Json? body = await _collect(config, version, force: force);
      if (_user != user) return null;
      if (body == null) return _putOff(user);
      await _api.post('/app-measurements', body);
      await _memory.write(doneKey, done);
      _settled = user;
      return body;
    } on ApiException catch (error) {
      // The server refuses this report for good: do not send it again.
      if (error.status == 422 && done != null) await _memory.write(doneKey, done);
      // Network or server trouble: the next launch tries again.
      if (error.status >= 400 && error.status < 500 && error.status != 429) _settled = user;
      return null;
    } on PlatformException {
      _settled = user;
      return null;
    } on MissingPluginException {
      _settled = user;
      return null;
    }
  }

  /// Measures again after [retryAfter], at most [maxDeferrals] times.
  Json? _putOff(int user) {
    if (++_deferrals > maxDeferrals || _user != user) return null;
    _timer?.cancel();
    _timer = Timer(retryAfter, () {
      _timer = null;
      _run(force: false);
    });
    return null;
  }

  /// The report, or null when a test was cut short (a real player started,
  /// another app plays sound, the network failed): measured again later.
  Future<Json?> _collect(Json config, String version, {required bool force}) async {
    final bool ios = defaultTargetPlatform == TargetPlatform.iOS;
    final bool appAttest = config['app_attest'] == true;
    final Json snapshot = Json.from(
      await _channel.invokeMapMethod<String, dynamic>('snapshot', <String, Object>{'appAttest': appAttest}) ??
          const <String, dynamic>{},
    );
    final bool testVideo = config['test_video'] == true;
    const MeasuredTest noVideo = MeasuredTest('unavailable', error: 'no_test_video');

    final MeasuredTest hardware;
    final MeasuredTest software;
    if (ios) {
      hardware = snapshot['fairplay'] != true
          ? const MeasuredTest('unavailable', error: 'no_fairplay')
          : testVideo
              ? await _fairPlayTest()
              : noVideo;
      software = const MeasuredTest('skipped');
    } else if (snapshot.strOrNull('securityLevel') == null) {
      hardware = const MeasuredTest('unavailable', error: 'no_widevine');
      software = const MeasuredTest('unavailable', error: 'no_widevine');
    } else {
      hardware = snapshot.str('securityLevel') != 'L1'
          ? const MeasuredTest('skipped', error: 'not_l1')
          : testVideo
              ? await _widevineTest(software: false)
              : noVideo;
      software = testVideo ? await _widevineTest(software: true) : noVideo;
    }
    if (!force && <MeasuredTest>[hardware, software].any((MeasuredTest test) => _transient.contains(test.error))) {
      return null;
    }

    final Json body = <String, dynamic>{
      'platform': ios ? 'ios' : 'android',
      'app_version': version,
      'device_model': _text(snapshot.str('model'), 80, 'unknown'),
      'os_version': _text(snapshot.str('osVersion'), 32, 'unknown'),
      if (snapshot['sdkInt'] is int) 'sdk_int': snapshot['sdkInt'],
      if (const <String>{'L1', 'L2', 'L3'}.contains(snapshot['securityLevel'])) 'security_level': snapshot['securityLevel'],
      if (_hdcp(snapshot['maxHdcp']) != null) 'max_hdcp': _hdcp(snapshot['maxHdcp']),
      if (_hdcp(snapshot['connectedHdcp']) != null) 'connected_hdcp': _hdcp(snapshot['connectedHdcp']),
      if (snapshot['secureDecoder1080p'] is bool) 'secure_decoder_1080p': snapshot['secureDecoder1080p'],
      if (snapshot.strOrNull('secureDecoder') != null)
        'secure_decoder': _text(snapshot.str('secureDecoder').replaceAll(RegExp('[^A-Za-z0-9._-]'), '_'), 80, ''),
      if (snapshot['googlePlayServices'] is bool) 'google_play_services': snapshot['googlePlayServices'],
      if (snapshot['gmsVersion'] is int) 'gms_version': snapshot['gmsVersion'],
      if (snapshot['playStore'] is bool) 'play_store': snapshot['playStore'],
      'hardware_test': hardware.result,
      if (hardware.error != null) 'hardware_test_error': hardware.error,
      if (hardware.code != null) 'hardware_test_code': hardware.code,
      'software_test': software.result,
      if (software.error != null) 'software_test_error': software.error,
      if (software.code != null) 'software_test_code': software.code,
      if (appAttest && snapshot['appAttestSupported'] is bool) 'app_attest_supported': snapshot['appAttestSupported'],
    }..removeWhere((String _, dynamic value) => value == '');

    final String? project = config.obj('play_integrity')?.strOrNull('cloud_project_number');
    if (!ios && project != null) body.addAll(await _integrity(project));
    return body;
  }

  /// `/device-check/playback` (the mode A licence: Widevine L1) or the
  /// test pattern's Widevine L3 licence, played muted for a few seconds.
  Future<MeasuredTest> _widevineTest({required bool software}) async {
    if (_playerBusy()) return const MeasuredTest('inconclusive', error: 'interrupted');
    final Json authorization;
    try {
      authorization = (await _api.post(software ? '/app-measurements/software-playback' : '/device-check/playback'))
              .obj('data') ??
          <String, dynamic>{};
    } on ApiException catch (error) {
      return _refused(error);
    }
    final Json drm = authorization.obj('drm') ?? <String, dynamic>{};
    return MeasuredTest.fromNative(await _channel.invokeMapMethod<String, dynamic>('testPlayback', <String, Object>{
      'manifest': authorization.obj('manifests')?.str('dash') ?? '',
      'license': drm.obj('license_urls')?.str('widevine') ?? '',
      'token': drm.str('token'),
      'forceL3': software,
      'timeoutMs': testTimeout.inMilliseconds,
    }));
  }

  /// The FairPlay HLS of the test pattern with the mode A licence (D-118).
  Future<MeasuredTest> _fairPlayTest() async {
    if (_playerBusy()) return const MeasuredTest('inconclusive', error: 'interrupted');
    final Json authorization;
    try {
      authorization = (await _api.post('/device-check/playback')).obj('data') ?? <String, dynamic>{};
    } on ApiException catch (error) {
      return _refused(error);
    }
    final Json drm = authorization.obj('drm') ?? <String, dynamic>{};
    final String license = drm.obj('license_urls')?.str('fairplay') ?? '';
    final String certificate = drm.str('fairplay_certificate_url');
    if (license.isEmpty || certificate.isEmpty) return const MeasuredTest('unavailable', error: 'no_fairplay_on_server');
    return MeasuredTest.fromNative(await _channel.invokeMapMethod<String, dynamic>('testPlayback', <String, Object>{
      'manifest': authorization.obj('manifests')?.str('hls') ?? '',
      'license': license,
      'certificate': certificate,
      'token': drm.str('token'),
      'timeoutMs': testTimeout.inMilliseconds,
    }));
  }

  static MeasuredTest _refused(ApiException error) => error.code == 'DEVICE_CHECK_UNAVAILABLE'
      ? const MeasuredTest('unavailable', error: 'no_test_video')
      // Not the phone's fault (network, refusal): measured again later.
      : const MeasuredTest('inconclusive', error: 'authorization');

  /// Play Integrity standard request bound to a random request hash the
  /// server compares with the decoded verdict.
  Future<Json> _integrity(String project) async {
    final Random random = Random.secure();
    final String hash = List<String>.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final Map<String, dynamic>? answer = await _channel.invokeMapMethod<String, dynamic>(
      'integrity',
      <String, Object>{'cloudProjectNumber': project, 'requestHash': hash},
    );
    final Object? token = answer?['token'];
    if (token is String && RegExp(r'^[A-Za-z0-9._\-=+/]{1,8192}$').hasMatch(token)) {
      return <String, dynamic>{'integrity_token': token, 'integrity_request_hash': hash};
    }
    final Object? code = answer?['errorCode'];
    return <String, dynamic>{'integrity_error_code': code is int && code.abs() <= 1000 ? code : -901};
  }

  Future<String> _appVersion() async {
    final Map<String, dynamic>? info = await _appInfo.invokeMapMethod<String, dynamic>('version');
    final String version = '${info?['version'] ?? ''}';
    final String build = '${info?['build'] ?? ''}';
    final String full = build.isEmpty ? version : '$version+$build';
    final String clean = full.replaceAll(RegExp('[^0-9A-Za-z.+_-]'), '');
    return clean.isEmpty ? 'unknown' : _text(clean, 40, 'unknown');
  }

  static String? _hdcp(Object? value) {
    final String text = '${value ?? ''}'.toLowerCase().replaceAll(RegExp('[^a-z0-9._-]'), '_');
    return text.isEmpty ? null : _text(text, 24, '');
  }

  /// Printable text only, cut to the backend's column size.
  static String _text(String value, int max, String fallback) {
    final String clean = value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (clean.isEmpty) return fallback;
    return clean.length <= max ? clean : clean.substring(0, max).trim();
  }
}
