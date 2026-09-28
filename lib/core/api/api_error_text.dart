import 'package:flutter/widgets.dart';

import '../i18n/nova_strings.dart';
import 'api_exception.dart';

/// Localized message for an API failure. The backend writes messages
/// in English only, so the app translates from the stable `code`; an
/// unknown code falls back to the server's message.
String apiErrorText(BuildContext context, Object error) {
  if (error is! ApiException) return context.tr('err.generic');
  if (error.code == 'DUPLICATE_ACCOUNT_DEACTIVATED') {
    // D-079: the masked number of the account to use, kept left-to-right
    // (an isolate) inside Arabic text.
    return context.trf('auth.duplicateClosed', <String, String>{
      'phone': '\u2066${error.fieldErrors['phone'] ?? ''}\u2069',
    });
  }
  final String key = switch (error.code) {
    ApiException.network => 'err.network',
    ApiException.sessionReplaced => 'err.sessionReplaced',
    ApiException.unauthenticated => error.status == 401 ? 'err.credentials' : 'err.generic',
    'STUDENT_ONLY' => 'err.studentOnly',
    'FORBIDDEN' => 'err.forbidden',
    'TOO_MANY_REQUESTS' => 'err.tooMany',
    'LIVE_BUSY' => 'err.liveBusy',
    'PROFILE_NAME_REQUIRED' => 'live.nameTitle',
    'COURSE_IS_FREE' => 'err.courseFree',
    'COURSE_NOT_SOLD_INDIVIDUALLY' => 'err.notSold',
    'COURSE_ALREADY_OWNED' || 'OFFER_ALREADY_OWNED' => 'err.owned',
    'ALREADY_OWNED_ON_OTHER_ACCOUNT' => 'err.ownedOtherAccount',
    'PHONE_ALREADY_REGISTERED' => 'auth.phoneTaken',
    'PHONE_REQUIRED' => 'err.phoneRequired',
    'PRODUCT_OUT_OF_TRACK' => 'err.outOfTrack',
    'SCHOOL_PROFILE_LOCKED' => 'err.profileLocked',
    'OFFER_NOT_AVAILABLE' => 'err.unavailable',
    'PROMO_CODE_INVALID' || 'DISCOUNT_CODE_INVALID' || 'DISCOUNT_CODE_AMBIGUOUS' =>
      'err.codeInvalid',
    'REFERRAL_DISCOUNT_UNAVAILABLE' || 'REFERRAL_MINIMUM_NOT_MET' => 'err.referralDiscount',
    'POINT_BALANCE_EXCEEDED' || 'POINTS_REDEMPTION_UNAVAILABLE' => 'err.points',
    'NO_ACTIVE_ACADEMIC_YEAR' => 'err.noYear',
    'REFERRAL_ALREADY_ATTACHED' => 'err.referralAttached',
    'REFERRAL_CODE_INVALID' || 'REFERRER_NOT_ELIGIBLE' => 'err.referralInvalid',
    'REFERRAL_SELF_NOT_ALLOWED' => 'err.referralSelf',
    'REFERRAL_ELIGIBILITY_CLOSED' => 'err.referralClosed',
    ApiException.validationFailed => '',
    _ => '',
  };
  if (key.isNotEmpty) return context.tr(key);
  if (error.code == ApiException.validationFailed) {
    final Map<String, String> fields = error.fieldErrors;
    return fields.isEmpty ? context.tr('err.generic') : fields.values.first;
  }
  if (error.status >= 500) return context.tr('err.server');
  return error.message;
}
