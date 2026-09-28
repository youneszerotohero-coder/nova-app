import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Laravel session and `XSRF-TOKEN` cookies in the
/// platform keystore (Android Keystore / iOS Keychain), so a signed-in
/// Student stays signed in across launches without the cookies ever
/// sitting in plain app files (D-067).
class SecureCookieStorage implements Storage {
  SecureCookieStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _prefix = 'nova.cookies.';

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  @override
  Future<String?> read(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final String key in keys) {
      await delete(key);
    }
  }
}
