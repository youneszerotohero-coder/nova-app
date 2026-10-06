import 'json.dart';

/// `POST /lessons/{id}/playback` (backend `PlaybackService::authorize`)
/// and `GET /lives/{id}/replay/playback`: either the protected stream
/// with its entitlement (DASH + Widevine, or HLS + FairPlay on iPhone,
/// D-118), or (`mode: clear`, D-070) the signed clear HLS copy protected by
/// the watermark only.
class PlaybackAuthorization {
  const PlaybackAuthorization({
    this.mode = 'protected',
    this.manifestUrl = '',
    this.mimeType = '',
    this.clearDeliveryAvailable = false,
    required this.dashUrl,
    required this.hlsUrl,
    required this.drmToken,
    required this.widevineLicenseUrl,
    this.fairplayLicenseUrl = '',
    this.fairplayCertificateUrl = '',
    required this.strict,
    required this.softwareFallback,
    required this.maxHeight,
    required this.supportUrl,
    required this.durationSeconds,
    required this.resumeSeconds,
    required this.watchAgain,
    required this.progressSession,
    required this.expiresAt,
    required this.watermarkName,
    required this.watermarkPhone,
    required this.watermarkSession,
  });

  factory PlaybackAuthorization.fromJson(Json json) {
    final Json manifests = json.obj('manifests') ?? <String, dynamic>{};
    final Json drm = json.obj('drm') ?? <String, dynamic>{};
    final Json licenses = drm.obj('license_urls') ?? <String, dynamic>{};
    final Json protection = json.obj('protection') ?? <String, dynamic>{};
    final Json watermark = json.obj('watermark') ?? <String, dynamic>{};
    final Object? duration = json['duration_seconds'];
    return PlaybackAuthorization(
      mode: json.str('mode', 'protected'),
      manifestUrl: json.str('manifest_url'),
      mimeType: json.str('mime_type', 'application/x-mpegurl'),
      clearDeliveryAvailable: json.flag('clear_delivery_available'),
      dashUrl: manifests.str('dash'),
      hlsUrl: manifests.str('hls'),
      drmToken: drm.str('token'),
      widevineLicenseUrl: licenses.str('widevine'),
      fairplayLicenseUrl: licenses.str('fairplay'),
      fairplayCertificateUrl: drm.str('fairplay_certificate_url'),
      strict: protection.str('mode', 'strict') == 'strict',
      softwareFallback: protection.flag('software_fallback'),
      maxHeight: protection['max_height'] is int ? protection['max_height'] as int : null,
      supportUrl: protection.strOrNull('support_url') ?? json.strOrNull('support_url'),
      durationSeconds: duration is num ? duration.toDouble() : 0,
      resumeSeconds: json.integer('resume_position_seconds'),
      watchAgain: json.flag('watch_again'),
      progressSession: json.str('progress_session'),
      expiresAt: json.date('expires_at'),
      watermarkName: watermark.str('name'),
      watermarkPhone: watermark.str('phone'),
      watermarkSession: watermark.str('session'),
    );
  }

  /// `protected` or `clear`.
  final String mode;

  /// Signed clear HLS manifest (`mode: clear`).
  final String manifestUrl;
  final String mimeType;

  /// Mode B: this protected video also has a clear copy this device may
  /// fall back to when its DRM cannot play.
  final bool clearDeliveryAvailable;

  bool get clear => mode == 'clear';

  final String dashUrl;
  final String hlsUrl;
  final String drmToken;
  final String widevineLicenseUrl;

  /// Present only while FairPlay is enabled on the server (D-088).
  final String fairplayLicenseUrl;
  final String fairplayCertificateUrl;

  bool get hasFairPlay =>
      hlsUrl.isNotEmpty && fairplayLicenseUrl.isNotEmpty && fairplayCertificateUrl.isNotEmpty;

  /// `protection.mode == 'strict'`: hardware DRM only, never software.
  final bool strict;
  final bool softwareFallback;

  /// Resolution cap (only set when software fallback is allowed).
  final int? maxHeight;
  final String? supportUrl;
  final double durationSeconds;
  final int resumeSeconds;

  /// Already ≥90% or completed: the server restarts from 0.
  final bool watchAgain;

  /// Required by `PUT /lessons/{id}/progress`.
  final String progressSession;
  final DateTime? expiresAt;
  final String watermarkName;
  final String watermarkPhone;
  final String watermarkSession;
}

/// A lesson Quiz as a Student sees it (no correct answers).
class StudentQuiz {
  const StudentQuiz({
    required this.id,
    required this.required,
    required this.passingScore,
    required this.maxAttempts,
    required this.cooldownMinutes,
    required this.questions,
  });

  factory StudentQuiz.fromJson(Json json) => StudentQuiz(
        id: json.integer('id'),
        required: json.flag('required'),
        passingScore: json.integer('passing_score_percent', 70),
        maxAttempts: json['max_attempts'] is int ? json['max_attempts'] as int : null,
        cooldownMinutes: json.flag('cooldown_enabled') ? json.integer('cooldown_minutes') : 0,
        questions: json.list('questions').map(QuizItem.fromJson).toList()
          ..sort((QuizItem a, QuizItem b) => a.order.compareTo(b.order)),
      );

  final int id;
  final bool required;
  final int passingScore;

  /// Null means unlimited attempts.
  final int? maxAttempts;
  final int cooldownMinutes;
  final List<QuizItem> questions;
}

class QuizItem {
  const QuizItem({
    required this.id,
    required this.type,
    required this.prompt,
    required this.order,
    required this.options,
  });

  factory QuizItem.fromJson(Json json) => QuizItem(
        id: json.integer('id'),
        type: json.str('type'),
        prompt: json.str('prompt'),
        order: json.integer('order_index'),
        options: <QuizOption>[
          for (final Json option in json.list('options'))
            QuizOption(id: option.integer('id'), label: option.str('label'), order: option.integer('order_index')),
        ]..sort((QuizOption a, QuizOption b) => a.order.compareTo(b.order)),
      );

  final int id;

  /// `single_choice` | `multiple_choice` | `true_false`.
  final String type;
  final String prompt;
  final int order;
  final List<QuizOption> options;

  bool get multiple => type == 'multiple_choice';
}

class QuizOption {
  const QuizOption({required this.id, required this.label, required this.order});

  final int id;
  final String label;
  final int order;
}

/// `attempts` summary returned with a quiz and after a submit.
class QuizAttempts {
  const QuizAttempts({
    required this.submitted,
    required this.remaining,
    required this.bestScore,
    required this.passed,
    required this.openAttemptId,
    required this.retryAt,
  });

  factory QuizAttempts.fromJson(Json json) => QuizAttempts(
        submitted: json.integer('attempts_submitted'),
        remaining: json['remaining_attempts'] is int ? json['remaining_attempts'] as int : null,
        bestScore: json['best_score_percent'] == null ? null : dinars(json['best_score_percent']),
        passed: json.flag('passed'),
        openAttemptId: json['open_attempt_id'] is int ? json['open_attempt_id'] as int : null,
        retryAt: json.date('retry_at'),
      );

  final int submitted;

  /// Null means unlimited.
  final int? remaining;
  final int? bestScore;
  final bool passed;
  final int? openAttemptId;

  /// Set when attempts are exhausted and a cooldown applies.
  final DateTime? retryAt;

  bool get canStart =>
      openAttemptId != null ||
      remaining == null ||
      remaining! > 0 ||
      (retryAt != null && retryAt!.isBefore(DateTime.now()));
}

/// The graded result of `POST /quiz-attempts/{id}/submit`.
class QuizResult {
  const QuizResult({
    required this.score,
    required this.passed,
    required this.attempts,
    required this.correctByQuestion,
  });

  factory QuizResult.fromJson(Json body) {
    final Json attempt = body.obj('data') ?? <String, dynamic>{};
    return QuizResult(
      score: dinars(attempt['score_percent']),
      passed: attempt.flag('passed'),
      attempts: QuizAttempts.fromJson(body.obj('attempts') ?? <String, dynamic>{}),
      correctByQuestion: <int, bool>{
        for (final Json answer in attempt.list('answers'))
          answer.integer('question_id'): answer.flag('is_correct'),
      },
    );
  }

  final int score;
  final bool passed;
  final QuizAttempts attempts;
  final Map<int, bool> correctByQuestion;
}
