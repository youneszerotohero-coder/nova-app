import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// What to do about a newer store version.
enum UpdateAction {
  /// Offer the update: Google Play's own flexible flow on Android (it
  /// downloads in the background), the NOVA sheet → App Store on iPhone.
  prompt,

  /// Google Play's full-screen flow: a release published with high
  /// in-app update priority (4–5), or an immediate update left unfinished.
  immediate,

  /// A flexible update finished downloading: restart to install it.
  restart,
}

class UpdateOffer {
  const UpdateOffer({
    required this.action,
    required this.version,
    this.storeUrl,
    this.installerUrl,
    this.sha256,
    this.required = false,
  });

  /// D-194: the Student must update before using the app (no "Later").
  final bool required;

  final UpdateAction action;

  /// Store version: `1.2.0` on the App Store, the version code on Play,
  /// `X.Y.Z+build` for the PC app.
  final String version;

  /// App Store page (iPhone).
  final Uri? storeUrl;

  /// PC app: the NOVA installer to download, and its SHA-256 (hex).
  final Uri? installerUrl;
  final String? sha256;
}

/// Where a declined offer is remembered, so the Student is not asked
/// again for the same version for [StoreUpdates.remindAfter].
abstract class UpdateMemory {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureUpdateMemory implements UpdateMemory {
  const SecureUpdateMemory();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

/// Store update check (owner request 2026-09-26): the stores are the
/// source of truth, so publishing a new version on Google Play or the App
/// Store is all it takes; no backend is involved.
///
/// * Android: Google Play In-App Updates (`AppUpdate.kt`, `nova/app_update`).
///   Only installs from Play see updates.
/// * iPhone: the public App Store lookup for this bundle id, compared with
///   the installed version (`AppDelegate.swift`, `nova/app_update`).
/// * PC app (owner decision 2026-10-29, no store): [pcLatestUrl] says
///   `{version, url, sha256}`; a newer installer is downloaded from the NOVA
///   site, checked against its SHA-256 and run silently, then NOVA restarts
///   (`docs/pc-app-windows.md`).
class StoreUpdates {
  StoreUpdates({
    MethodChannel? channel,
    Future<Map<String, dynamic>?> Function(Uri uri)? fetchJson,
    UpdateMemory? memory,
    this._platform,
    DateTime Function()? now,
    bool? mandatory,
  })  : mandatory = mandatory ?? mandatoryUpdates,
        _channel = channel ?? const MethodChannel('nova/app_update'),
        _fetchJson = fetchJson ?? _getJson,
        _memory = memory ?? const SecureUpdateMemory(),
        _now = now ?? DateTime.now;

  /// D-194 (owner decision 2026-11-01): every newer version is required —
  /// a Student updates before continuing, on Android, iPhone and the PC app.
  /// `--dart-define=NOVA_MANDATORY_UPDATES=false` builds the optional offers
  /// back (sheets with "Later").
  static const bool mandatoryUpdates = bool.fromEnvironment('NOVA_MANDATORY_UPDATES', defaultValue: true);

  /// The Play Store page, when Play's own full-screen flow is not available.
  static final Uri playStoreUrl = Uri.https('play.google.com', '/store/apps/details', <String, String>{'id': 'dz.nova.nova_mobile'});

  /// Whether newer versions are required ([mandatoryUpdates] by default).
  final bool mandatory;

  /// A declined version is offered again after this long.
  static const Duration remindAfter = Duration(days: 3);

  /// Google's convention: priority 4–5 releases are urgent (immediate).
  static const int immediatePriority = 4;

  /// App Store storefronts to look in: Algeria first, then the default.
  static const List<String?> storefronts = <String?>['dz', null];

  /// The PC app's update manifest; `--dart-define=NOVA_PC_UPDATE_URL=…`
  /// points a test build elsewhere.
  static const String pcLatestUrl = String.fromEnvironment(
    'NOVA_PC_UPDATE_URL',
    defaultValue: 'https://nova-elearning.com/downloads/pc/latest.json',
  );

  /// Installers are only ever taken from the NOVA site, over HTTPS.
  static bool trustedInstallerUrl(Uri url) =>
      url.scheme == 'https' && (url.host == 'nova-elearning.com' || url.host.endsWith('.nova-elearning.com'));

  static const String _declinedKey = 'nova.update.declined';

  final MethodChannel _channel;
  final Future<Map<String, dynamic>?> Function(Uri uri) _fetchJson;
  final UpdateMemory _memory;
  final TargetPlatform? _platform;
  final DateTime Function() _now;

  /// Download progress of a flexible Android update (`status`:
  /// `downloading`, `downloaded`, `installed`, `failed`, `canceled`…).
  Stream<Map<Object?, Object?>> get installStates => const EventChannel('nova/app_update/events')
      .receiveBroadcastStream()
      .where((Object? event) => event is Map)
      .cast<Map<Object?, Object?>>();

  Future<UpdateOffer?> check() async {
    if (kIsWeb) return null;
    try {
      return switch (_platform ?? defaultTargetPlatform) {
        TargetPlatform.android => await _android(),
        TargetPlatform.iOS => await _ios(),
        TargetPlatform.windows => await _windows(),
        _ => null,
      };
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<UpdateOffer?> _android() async {
    final Map<String, dynamic>? info = await _channel.invokeMapMethod<String, dynamic>('info');
    if (info == null) return null;
    final String version = '${info['versionCode'] ?? ''}';
    if (info['downloaded'] == true) return UpdateOffer(action: UpdateAction.restart, version: version);
    // An immediate update the Student left: Google asks to resume it.
    if (info['inProgress'] == true) return UpdateOffer(action: UpdateAction.immediate, version: version);
    if (info['available'] != true) return null;
    if (mandatory) {
      // D-194: Google Play's full-screen flow, or the Play Store page.
      return info['immediate'] == true
          ? UpdateOffer(action: UpdateAction.immediate, version: version, required: true)
          : UpdateOffer(action: UpdateAction.prompt, version: version, storeUrl: playStoreUrl, required: true);
    }
    final int priority = info['priority'] is int ? info['priority'] as int : 0;
    if (info['immediate'] == true && priority >= immediatePriority) {
      return UpdateOffer(action: UpdateAction.immediate, version: version);
    }
    if (info['flexible'] == true && await _mayOffer(version)) {
      return UpdateOffer(action: UpdateAction.prompt, version: version);
    }
    return null;
  }

  Future<UpdateOffer?> _ios() async {
    final Map<String, dynamic>? me = await _channel.invokeMapMethod<String, dynamic>('version');
    final String bundleId = '${me?['bundleId'] ?? ''}';
    final String installed = appStoreVersion('${me?['version'] ?? ''}');
    if (bundleId.isEmpty || installed.isEmpty) return null;

    for (final String? country in storefronts) {
      final Map<String, dynamic>? body = await _fetchJson(Uri.https('itunes.apple.com', '/lookup', <String, String>{
        'bundleId': bundleId,
        'country': ?country,
      }));
      final Object? results = body?['results'];
      if (results is! List || results.isEmpty || results.first is! Map) continue;
      final Map<Object?, Object?> app = results.first as Map<Object?, Object?>;
      final String store = appStoreVersion('${app['version'] ?? ''}');
      final Uri? url = Uri.tryParse('${app['trackViewUrl'] ?? ''}');
      if (store.isEmpty || compareVersions(store, installed) <= 0) return null;
      // A version this iPhone cannot install is not offered.
      final String minimumOs = '${app['minimumOsVersion'] ?? ''}';
      final String os = '${me?['osVersion'] ?? ''}';
      if (minimumOs.isNotEmpty && os.isNotEmpty && compareVersions(os, minimumOs) < 0) return null;
      if (mandatory) return UpdateOffer(action: UpdateAction.prompt, version: store, storeUrl: url, required: true);
      if (!await _mayOffer(store)) return null;
      return UpdateOffer(action: UpdateAction.prompt, version: store, storeUrl: url);
    }
    return null;
  }

  Future<UpdateOffer?> _windows() async {
    final Map<String, dynamic>? me = await _channel.invokeMapMethod<String, dynamic>('version');
    final String installed = '${me?['version'] ?? ''}';
    if (installed.isEmpty) return null;
    final Map<String, dynamic>? latest = await _fetchJson(Uri.parse(pcLatestUrl));
    final String version = '${latest?['version'] ?? ''}';
    final Uri? url = Uri.tryParse('${latest?['url'] ?? ''}');
    final String sha256 = '${latest?['sha256'] ?? ''}'.toLowerCase();
    if (version.isEmpty || url == null || !trustedInstallerUrl(url)) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) return null;
    if (compareVersions(version, installed) <= 0) return null;
    if (mandatory) {
      return UpdateOffer(action: UpdateAction.prompt, version: version, installerUrl: url, sha256: sha256, required: true);
    }
    if (!await _mayOffer(version)) return null;
    return UpdateOffer(action: UpdateAction.prompt, version: version, installerUrl: url, sha256: sha256);
  }

  /// PC app: downloads [offer]'s installer to the temporary folder and keeps
  /// it only when its SHA-256 is the announced one; null otherwise.
  Future<File?> downloadInstaller(UpdateOffer offer) async {
    final Uri? url = offer.installerUrl;
    final String? expected = offer.sha256;
    if (url == null || expected == null || !trustedInstallerUrl(url)) return null;
    try {
      final Directory folder = await getTemporaryDirectory();
      final File file = File('${folder.path}${Platform.pathSeparator}NOVA-Setup-${offer.version.replaceAll(RegExp(r'[^0-9A-Za-z.+-]'), '')}.exe');
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 2),
      )).downloadUri(url, file.path);
      // The announced SHA-256 is the guard: a corrupted or replaced file is
      // never run.
      final String actual = (await crypto.sha256.bind(file.openRead()).first).toString();
      if (actual != expected.toLowerCase()) {
        await file.delete();
        return null;
      }
      return file;
    } on DioException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// PC app: runs the verified installer silently (per-user, no admin
  /// rights; it closes NOVA, replaces it and starts it again) and quits.
  Future<void> installAndRestart(File installer) async {
    try {
      await Process.start(
        installer.path,
        const <String>['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
    } on ProcessException {
      return;
    }
    exit(0);
  }

  /// Starts Google Play's flow; `ok`, `canceled` or `failed`.
  Future<String> start({required bool immediate}) async {
    try {
      return await _channel.invokeMethod<String>('start', <String, bool>{'immediate': immediate}) ?? 'failed';
    } on PlatformException {
      return 'failed';
    } on MissingPluginException {
      return 'failed';
    }
  }

  /// Installs a downloaded flexible update; Android restarts the app.
  Future<void> complete() async {
    try {
      await _channel.invokeMethod<void>('complete');
    } on PlatformException {
      // Offered again at the next check.
    }
  }

  /// "Later": not offered again for [remindAfter].
  Future<void> declined(String version) async {
    try {
      await _memory.write(_declinedKey, '$version|${_now().millisecondsSinceEpoch}');
    } catch (_) {
      // Unwritable storage: asked again at the next check.
    }
  }

  Future<bool> _mayOffer(String version) async {
    try {
      final String? saved = await _memory.read(_declinedKey);
      final List<String> parts = (saved ?? '').split('|');
      if (parts.length != 2 || parts.first != version) return true;
      final int? at = int.tryParse(parts.last);
      if (at == null) return true;
      return _now().difference(DateTime.fromMillisecondsSinceEpoch(at)) >= remindAfter;
    } catch (_) {
      return true;
    }
  }

  static Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final Response<dynamic> response = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.json,
      )).getUri<dynamic>(uri);
      Object? data = response.data;
      // A server that names the JSON text/plain still gives JSON.
      if (data is String) {
        try {
          data = jsonDecode(data);
        } on FormatException {
          return null;
        }
      }
      return data is Map<String, dynamic> ? data : null;
    } on DioException {
      return null;
    }
  }
}

/// The `x.y.z` in an App Store version text. The version is typed by hand in
/// App Store Connect and has been published as `0.5.8+29` and `24 (0.5.3)`:
/// read whole, `0.5.8+29` counted as newer than the installed `0.5.8` and
/// required an update nobody could install (2026-11-25). Empty when the text
/// holds no dotted version; nothing is then offered.
String appStoreVersion(String text) => RegExp(r'\d+(?:\.\d+)+').firstMatch(text)?.group(0) ?? '';

/// Compares dotted versions numerically (`1.10.0` > `1.9.2`); missing
/// parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split(RegExp(r'[.+-]')).map((String p) => int.tryParse(p) ?? 0).toList();
  final List<int> x = parts(a);
  final List<int> y = parts(b);
  for (int i = 0; i < x.length || i < y.length; i++) {
    final int left = i < x.length ? x[i] : 0;
    final int right = i < y.length ? y[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}
