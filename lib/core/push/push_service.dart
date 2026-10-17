import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_exception.dart';
import '../api/nova_api.dart';
import 'push_platform.dart';

/// Remembers that the app already explained push and asked once.
abstract class PushFlags {
  Future<bool> asked();
  Future<void> markAsked();
}

class SecurePushFlags implements PushFlags {
  const SecurePushFlags();

  static const String _key = 'nova.push.asked';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<bool> asked() async {
    try {
      return await _storage.read(key: _key) == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markAsked() async {
    try {
      await _storage.write(key: _key, value: '1');
    } catch (_) {
      // Unwritable storage: the explanation may show once more.
    }
  }
}

/// D-143 system notifications (BR-M1..M3): the phone's FCM token belongs to
/// the signed-in account (`POST /me/devices` after sign-in and on every
/// refresh, `DELETE /me/devices` before sign-out), the permission is asked
/// once after a short explanation, and messages are handed to the app
/// ([foreground] while it is open, [opened] when a notification is tapped).
///
/// Without a [PushPlatform] (missing `--dart-define`s, tests) every call is
/// a no-op and the app behaves as before.
class PushService extends ChangeNotifier {
  PushService({required this._platform, required this._api, this._flags = const SecurePushFlags()});

  final PushPlatform? _platform;
  final NovaApi? _api;
  final PushFlags _flags;

  final StreamController<PushPayload> _foreground = StreamController<PushPayload>.broadcast();
  final StreamController<PushPayload> _opened = StreamController<PushPayload>.broadcast();

  /// Messages received while the app is open.
  Stream<PushPayload> get foreground => _foreground.stream;

  /// Notifications tapped (app in the background or closed).
  Stream<PushPayload> get opened => _opened.stream;

  Future<bool>? _starting;
  bool _available = false;
  PushPermission _permission = PushPermission.unknown;

  /// A signed-in account past its required steps: the token is theirs.
  bool _session = false;
  String? _registered;
  Future<void>? _registering;
  String _appVersion = '';

  /// Firebase runs on this build (its options were given and it started).
  bool get available => _available;
  PushPermission get permission => _permission;

  /// The token registered for the signed-in account, if any.
  @visibleForTesting
  String? get registeredToken => _registered;

  /// Starts Firebase once; false when push is off on this build.
  Future<bool> start() => _starting ??= _start();

  Future<bool> _start() async {
    final PushPlatform? platform = _platform;
    if (platform == null) return false;
    try {
      await platform.initialize();
      platform.foregroundMessages.listen(_foreground.add);
      platform.openedMessages.listen(_opened.add);
      platform.tokenRefreshes.listen(_onTokenRefresh);
      _appVersion = await platform.appVersion();
      _permission = await platform.permission();
      _available = true;
      notifyListeners();
      final PushPayload? launch = await platform.launchMessage();
      if (launch != null) _opened.add(launch);
      return true;
    } catch (error) {
      // No Google services, wrong options…: push stays off, nothing fails.
      debugPrint('Push unavailable: $error');
      return false;
    }
  }

  /// Names the Android channels in the app language.
  Future<void> nameChannels({required String messages, required String general}) async {
    if (!await start()) return;
    try {
      await _platform!.nameChannels(messages: messages, general: general);
    } catch (_) {
      // Keeps the previous names.
    }
  }

  /// The account is signed in and past its required steps: its token is
  /// registered when notifications are allowed (asking is [offerPermission]'s).
  Future<void> signedIn() async {
    if (_session) return;
    _session = true;
    if (!await start() || !_session) return;
    await refreshPermission();
  }

  /// Reads the permission again (back from the phone's settings) and
  /// registers the token once it is allowed.
  Future<void> refreshPermission() async {
    if (!await start()) return;
    try {
      _setPermission(await _platform!.permission());
    } catch (_) {
      return;
    }
    if (_permission == PushPermission.granted) await _register();
  }

  /// Once the signed-in space shows: when the phone has not allowed
  /// notifications yet, [explain] says why (true = "Enable"), then the
  /// system asks. Only once per installation; Settings can ask again.
  Future<void> offerPermission(Future<bool> Function() explain) async {
    if (!_session || !await start()) return;
    await refreshPermission();
    if (!_session || _permission == PushPermission.granted || _permission == PushPermission.blocked) return;
    if (await _flags.asked()) return;
    await _flags.markAsked();
    if (!await explain()) return;
    await requestPermission();
  }

  /// The system prompt; the token follows when allowed.
  Future<PushPermission> requestPermission() async {
    if (!await start()) return _permission;
    try {
      _setPermission(await _platform!.requestPermission());
    } catch (_) {
      return _permission;
    }
    if (_permission == PushPermission.granted) await _register();
    return _permission;
  }

  /// Settings' "Enable": the system prompt while it may still show, the
  /// phone's notification settings otherwise.
  Future<PushPermission> enable() async {
    final PushPermission status = await requestPermission();
    if (status != PushPermission.granted && _available) {
      try {
        await _platform!.openSettings();
      } catch (_) {
        // No settings page on this phone.
      }
    }
    return status;
  }

  /// Explicit sign-out, while the session still works: the token leaves the
  /// account (`DELETE /me/devices`) and is deleted on the phone.
  Future<void> unregister() async {
    final String? token = _registered;
    _session = false;
    _registered = null;
    if (token == null) return;
    try {
      await _api?.delete('/me/devices', <String, String>{'token': token}).timeout(const Duration(seconds: 5));
    } catch (_) {
      // The deleted token below stops the pushes anyway.
    }
    await _deleteToken();
  }

  /// The session ended (sign-out, replaced, expired): a token still known
  /// is deleted on the phone so this account's pushes stop here.
  Future<void> signedOut() async {
    final bool hadToken = _registered != null;
    _session = false;
    _registered = null;
    if (hadToken) await _deleteToken();
  }

  Future<void> _deleteToken() async {
    try {
      await _platform?.deleteToken();
    } catch (_) {
      // Firebase unreachable: the server drops the token once FCM refuses it.
    }
  }

  void _onTokenRefresh(String token) {
    if (!_session || _permission != PushPermission.granted) return;
    _register(token);
  }

  /// One registration at a time; a refreshed token is sent at once.
  Future<void> _register([String? fresh]) {
    if (fresh != null) return _send(fresh);
    return _registering ??= _send(null).whenComplete(() => _registering = null);
  }

  Future<void> _send(String? fresh) async {
    final PushPlatform? platform = _platform;
    final NovaApi? api = _api;
    if (platform == null || api == null || !_session) return;
    String? token = fresh;
    try {
      token ??= await platform.token();
    } catch (_) {
      return;
    }
    if (token == null || token.isEmpty || token == _registered || !_session) return;
    try {
      await api.post('/me/devices', <String, String>{
        'token': token,
        'platform': platform.platformName,
        if (_appVersion.isNotEmpty) 'app_version': _appVersion,
      });
      if (_session) _registered = token;
    } on ApiException {
      // The next launch, sign-in or token refresh tries again.
    }
  }

  void _setPermission(PushPermission permission) {
    if (permission == _permission) return;
    _permission = permission;
    notifyListeners();
  }

  @override
  void dispose() {
    _foreground.close();
    _opened.close();
    super.dispose();
  }
}
