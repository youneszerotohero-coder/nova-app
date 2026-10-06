import 'package:flutter/foundation.dart';

import '../core/api/nova_api.dart';

/// `POST /playback-diagnostics` (D-077): why a player left DRM for the
/// clear copy (`clear_fallback`) or which error screen the Student saw
/// (`error_shown`), so the later DRM work knows which devices fail and
/// where. Fixed codes only — never a URL, token or key id. Best effort:
/// a trace never disturbs playback (web `lib/playback-diagnostics.ts`).
void reportPlaybackDiagnostic(
  NovaApi? api, {
  required String content,
  required int contentId,
  required String event,
  String? reason,
  String? category,
  String? phase,
  int? code,
  int? httpStatus,
  String? robustness,
  bool drm = false,
  bool neutral = true,
  bool clear = false,
}) {
  if (api == null) return;
  final Map<String, Object?> body = <String, Object?>{
    'content': content,
    'content_id': contentId,
    'event': event,
    'reason': reason,
    'category': category,
    'phase': phase,
    // The backend accepts -1..100000 (Media3 codes); AVFoundation's
    // negative codes are left out.
    if (code != null && code >= -1 && code <= 100000) 'code': code,
    if (httpStatus != null && httpStatus > 0) 'http_status': httpStatus,
    if (drm) 'drm': defaultTargetPlatform == TargetPlatform.iOS ? 'fairplay' : 'widevine',
    if (drm && robustness != null) 'robustness': robustness,
    'wording': neutral ? 'neutral' : 'protected',
    'delivery': clear ? 'clear' : 'protected',
    'build': 'app-${defaultTargetPlatform.name}',
  }..removeWhere((String _, Object? value) => value == null);
  api.post('/playback-diagnostics', body).catchError((Object _) => <String, dynamic>{});
}
