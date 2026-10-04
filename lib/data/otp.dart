import '../core/api/api_exception.dart';
import 'json.dart';

/// D-096: how smssak delivers a code; the Student chooses, SMS first.
enum OtpChannel { sms, whatsapp }

/// D-093: a code was requested (`202 {data: {challenge_id, expires_in,
/// resend_in}}`). A forgotten-password request answers the same whether
/// the number has an account or not.
class OtpChallenge {
  const OtpChallenge({
    required this.id,
    this.expiresIn = 300,
    this.resendIn = 60,
  });

  factory OtpChallenge.fromJson(Json json) => OtpChallenge(
        id: json.str('challenge_id'),
        expiresIn: json.integer('expires_in', 300),
        resendIn: json.integer('resend_in', 60),
      );

  final String id;
  final int expiresIn;
  final int resendIn;
}

/// Seconds to wait before a new code (`details.retry_after` of
/// `OTP_RESEND_TOO_SOON` / `OTP_TOO_MANY_REQUESTS`), or null.
int? otpRetryAfter(Object error) {
  if (error is! ApiException ||
      (error.code != 'OTP_RESEND_TOO_SOON' && error.code != 'OTP_TOO_MANY_REQUESTS')) {
    return null;
  }
  final Object? details = error.details;
  final Object? raw = details is Map ? details['retry_after'] : null;
  final int? seconds = raw is num ? raw.ceil() : int.tryParse('$raw');
  return seconds != null && seconds > 0 ? seconds : null;
}

/// Attempts left after a wrong code (`OTP_INVALID`), or null.
int? otpRemainingAttempts(Object error) {
  if (error is! ApiException || error.code != 'OTP_INVALID') return null;
  final Object? details = error.details;
  final Object? raw = details is Map ? details['remaining_attempts'] : null;
  final int? remaining = raw is num ? raw.toInt() : int.tryParse('$raw');
  return remaining != null && remaining > 0 ? remaining : null;
}

/// The 6 digits the backend accepts (`/^\d{6}$/`).
bool isOtpCode(String code) => RegExp(r'^\d{6}$').hasMatch(code.trim());
