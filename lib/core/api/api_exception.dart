/// An `/api/v1` failure in the backend's own envelope:
/// `{"error": {"code", "message", "details?"}}`.
///
/// Screens branch on [code] (stable, e.g. `COURSE_IS_FREE`) and never
/// on [message], which the backend always writes in English.
class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.details,
  });

  /// HTTP status; 0 when the request never reached the server.
  final int status;
  final String code;
  final String message;
  final Object? details;

  static const String network = 'NETWORK_UNAVAILABLE';
  static const String unauthenticated = 'UNAUTHENTICATED';
  static const String sessionReplaced = 'SESSION_REPLACED';
  static const String validationFailed = 'VALIDATION_FAILED';
  static const String onboardingRequired = 'ONBOARDING_REQUIRED';
  static const String passwordChangeRequired = 'PASSWORD_CHANGE_REQUIRED';

  bool get isNetwork => status == 0;

  /// Field errors of a 422 `VALIDATION_FAILED`, first message per field.
  Map<String, String> get fieldErrors {
    final Object? raw = details;
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final MapEntry<dynamic, dynamic> entry in raw.entries)
        if (entry.value is List && (entry.value as List).isNotEmpty)
          '${entry.key}': '${(entry.value as List).first}'
        else if (entry.value is String)
          '${entry.key}': entry.value as String,
    };
  }

  @override
  String toString() => 'ApiException($status $code: $message)';
}
