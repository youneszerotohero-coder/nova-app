import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:nova_mobile/core/api/nova_api.dart';

/// One canned response.
class FakeResponse {
  const FakeResponse(this.status, [this.body, this.headers = const {}]);

  final int status;
  final Object? body;
  final Map<String, List<String>> headers;
}

/// A recorded request, for asserting what the app sent.
class FakeRequest {
  const FakeRequest(this.method, this.path, this.headers, this.data, [this.query = '']);

  final String method;
  final String path;

  /// Decoded query string, e.g. `teacher_ids[]=1&teacher_ids[]=4`.
  final String query;
  final Map<String, dynamic> headers;
  final Object? data;
}

/// Serves `/api/v1` from a route table keyed `'METHOD /path'` (or
/// `'METHOD /path?query'` for one query, e.g. a page), so tests
/// drive the real [NovaApi] (cookies, CSRF, envelopes) without network.
/// `GET /auth/csrf-cookie` answers like Laravel: 204 plus an encrypted,
/// URL-encoded `XSRF-TOKEN` cookie.
class FakeBackend implements HttpClientAdapter {
  FakeBackend(this.routes, {Map<String, List<FakeResponse>>? sequences})
      : sequences = sequences ?? <String, List<FakeResponse>>{};

  final Map<String, FakeResponse> routes;

  /// Successive answers for one route (then the last one repeats), e.g. a
  /// 409 followed by a success. Takes precedence over [routes].
  final Map<String, List<FakeResponse>> sequences;
  final List<FakeRequest> requests = <FakeRequest>[];

  static const String xsrfCookieValue = 'eyJpdiI6IkFCQyJ9%3D%3D';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String path = options.uri.path.replaceFirst('/api/v1', '');
    requests.add(FakeRequest(
      options.method,
      path,
      options.headers,
      options.data,
      Uri.decodeQueryComponent(options.uri.query),
    ));

    if (path == '/auth/csrf-cookie') {
      return ResponseBody.fromString('', 204, headers: <String, List<String>>{
        'set-cookie': <String>[
          'XSRF-TOKEN=$xsrfCookieValue; path=/',
          'nova_e_learning_session=abc; path=/; httponly',
        ],
      });
    }

    final String query = Uri.decodeQueryComponent(options.uri.query);
    final List<FakeResponse>? queued = sequences['${options.method} $path'];
    final FakeResponse? response = queued != null && queued.isNotEmpty
        ? (queued.length > 1 ? queued.removeAt(0) : queued.first)
        : (query.isEmpty ? null : routes['${options.method} $path?$query']) ??
            routes['${options.method} $path'];
    if (response == null) {
      return _json(404, <String, Object>{
        'error': <String, String>{'code': 'NOT_FOUND', 'message': 'No route $path'},
      });
    }
    return _json(response.status, response.body, response.headers);
  }

  static ResponseBody _json(
    int status,
    Object? body, [
    Map<String, List<String>> headers = const {},
  ]) =>
      ResponseBody.fromString(
        body == null ? '' : jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
          ...headers,
        },
      );

  @override
  void close({bool force = false}) {}
}

/// A [NovaApi] wired to [backend] with an in-memory cookie jar.
NovaApi fakeApi(FakeBackend backend) {
  final Dio dio = Dio()..httpClientAdapter = backend;
  return NovaApi(
    baseUrl: 'https://nova.test/api/v1',
    cookieJar: CookieJar(),
    dio: dio,
  );
}
