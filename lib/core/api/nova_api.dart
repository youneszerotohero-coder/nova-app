import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import '../../data/json.dart';
import 'api_exception.dart';
import 'secure_cookie_storage.dart';

/// The one HTTP client for `/api/v1`, mirroring the web SPA's contract
/// (website-front `lib/api.ts`) so the backend needs no mobile branch:
///
/// * Laravel `web` session cookie in a persistent, keystore-backed jar;
/// * on writes, the decoded `XSRF-TOKEN` cookie echoed as `X-XSRF-TOKEN`,
///   fetched from `GET /auth/csrf-cookie` only when the jar has none, and
///   once more on a 419 (D-071: no CSRF round trip per write);
/// * `{data: …}` success bodies, `{error: {code, message, details}}`
///   failures surfaced as [ApiException];
/// * a 401 on an authenticated call reported through [onSessionLost]
///   (`SESSION_REPLACED` when another device signed in).
class NovaApi {
  NovaApi({String? baseUrl, CookieJar? cookieJar, Dio? dio})
      : baseUrl = baseUrl ?? defaultBaseUrl,
        cookieJar = cookieJar ??
            PersistCookieJar(storage: SecureCookieStorage()),
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = this.baseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers = <String, Object>{'Accept': 'application/json', clientHeader: clientName}
      // Every status reaches [_unwrap]; the backend's envelope, not
      // Dio, decides what counts as a failure.
      ..validateStatus = (_) => true;
    _dio.interceptors.add(CookieManager(this.cookieJar));
  }

  /// D-121: tells the backend the request comes from the NOVA app, which
  /// may take the clear copy of a video in mode A (the website may not).
  static const String clientHeader = 'X-Nova-Client';

  static String get clientName =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'app-ios' : 'app-android';

  /// Production API; `--dart-define=NOVA_API_URL=…` points a build at
  /// staging or a local backend instead.
  static const String defaultBaseUrl = String.fromEnvironment(
    'NOVA_API_URL',
    defaultValue: 'https://nova-elearning.com/api/v1',
  );

  final String baseUrl;
  final CookieJar cookieJar;
  final Dio _dio;

  /// Called when an authenticated request comes back 401.
  void Function(ApiException error)? onSessionLost;

  Future<Json> get(String path, {Map<String, Object?>? query}) =>
      _send('GET', path, query: query);

  Future<Json> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<Json> put(String path, [Object? body]) =>
      _send('PUT', path, body: body);

  Future<Json> patch(String path, [Object? body]) =>
      _send('PATCH', path, body: body);

  Future<Json> delete(String path, [Object? body]) =>
      _send('DELETE', path, body: body);

  /// Multipart upload of one local file under [field] (CCP receipts).
  Future<Json> upload(String path, {required String field, required File file}) async {
    final FormData form = FormData.fromMap(<String, Object>{
      field: await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.last,
      ),
    });
    return _send('POST', path, body: form);
  }

  /// Raw bytes of an absolute URL on the API host (signed PDF content),
  /// sent with the session cookie like any other request.
  Future<List<int>> getBytes(String url) async {
    try {
      final Response<List<int>> response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final int status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) return response.data ?? const <int>[];
      throw ApiException(
        status: status,
        code: 'HTTP_$status',
        message: 'Download failed ($status)',
      );
    } on DioException catch (error) {
      throw ApiException(
        status: 0,
        code: ApiException.network,
        message: error.message ?? 'Network unavailable',
      );
    }
  }

  /// Drops every cookie, e.g. after sign-out or a replaced session.
  Future<void> clearSession() => cookieJar.deleteAll();

  Future<Json> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) async {
    final bool write = method != 'GET';
    try {
      Response<dynamic> response = await _request(method, path, query, body, write: write);
      if (write && response.statusCode == 419) {
        // CSRF token mismatch (expired or rotated): one fresh token, once.
        response = await _request(
          method,
          path,
          query,
          body is FormData ? body.clone() : body,
          write: true,
          freshToken: true,
        );
      }
      return _unwrap(path, response);
    } on DioException catch (error) {
      throw ApiException(
        status: 0,
        code: ApiException.network,
        message: error.message ?? 'Network unavailable',
      );
    }
  }

  Future<Response<dynamic>> _request(
    String method,
    String path,
    Map<String, Object?>? query,
    Object? body, {
    required bool write,
    bool freshToken = false,
  }) async {
    final Map<String, Object> headers = <String, Object>{};
    if (write) headers['X-XSRF-TOKEN'] = await _csrfToken(fresh: freshToken);
    return _dio.request<dynamic>(
      path,
      data: body,
      queryParameters: _cleanQuery(query),
      options: Options(method: method, headers: headers),
    );
  }

  /// The URL-decoded `XSRF-TOKEN` cookie; `/auth/csrf-cookie` is only
  /// asked when the jar has none (or [fresh] after a 419).
  Future<String> _csrfToken({bool fresh = false}) async {
    if (!fresh) {
      final String? stored = await _storedCsrfToken();
      if (stored != null) return stored;
    }
    await _dio.get<dynamic>('/auth/csrf-cookie');
    final String? issued = await _storedCsrfToken();
    if (issued != null) return issued;
    throw const ApiException(
      status: 0,
      code: 'CSRF_UNAVAILABLE',
      message: 'The server did not issue a CSRF token.',
    );
  }

  Future<String?> _storedCsrfToken() async {
    final List<Cookie> cookies =
        await cookieJar.loadForRequest(Uri.parse(baseUrl));
    for (final Cookie cookie in cookies) {
      if (cookie.name == 'XSRF-TOKEN' && cookie.value.isNotEmpty) {
        return Uri.decodeComponent(cookie.value);
      }
    }
    return null;
  }

  Json _unwrap(String path, Response<dynamic> response) {
    final int status = response.statusCode ?? 0;
    final Object? body = response.data;
    if (status >= 200 && status < 300) {
      return body is Map<String, dynamic> ? body : <String, dynamic>{};
    }

    final Object? error = body is Map ? body['error'] : null;
    final ApiException exception = ApiException(
      status: status,
      code: error is Map && error['code'] is String
          ? error['code'] as String
          : 'HTTP_$status',
      message: error is Map && error['message'] is String
          ? error['message'] as String
          : 'Request failed ($status)',
      details: error is Map ? error['details'] : null,
    );
    if (status == 401 && !path.startsWith('/auth/login')) {
      onSessionLost?.call(exception);
    }
    throw exception;
  }

  static Map<String, Object?>? _cleanQuery(Map<String, Object?>? query) {
    if (query == null) return null;
    final Map<String, Object?> clean = <String, Object?>{};
    query.forEach((String key, Object? value) {
      if (value == null) return;
      if (value is Iterable) {
        // Laravel reads `ids[]=1&ids[]=2` as an array.
        if (value.isNotEmpty) clean['$key[]'] = value.toList();
      } else {
        clean[key] = value;
      }
    });
    return clean;
  }
}
