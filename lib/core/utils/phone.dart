/// Algerian mobile spellings (D-078, D-079). Laravel's
/// `LegacyPhoneNormalizer` stays authoritative; these only explain a
/// refusal before the request, like the website does.
library;

final RegExp _mobile = RegExp(r'^[567]\d{8}$');

/// The canonical spelling of an Algerian mobile, 0 then 5, 6 or 7 and
/// eight digits, or null. Accepts +213 / 00213 / 213 prefixes (also with
/// the national 0 kept), a missing 0, spaces, dashes and Arabic-Indic
/// digits — the website's `normalizeAlgerianMobile`.
String? normalizeAlgerianMobile(String raw) {
  final StringBuffer ascii = StringBuffer();
  for (final int rune in raw.trim().runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      ascii.writeCharCode(rune);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      ascii.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      ascii.writeCharCode(0x30 + rune - 0x06F0);
    }
  }
  String digits = ascii.toString();
  if (digits.startsWith('00213')) {
    digits = digits.substring(5);
  } else if (digits.startsWith('213') && digits.length >= 12) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0213') && digits.length == 13) {
    digits = digits.substring(4);
  }
  if (digits.length == 10 && digits.startsWith('0')) digits = digits.substring(1);
  return _mobile.hasMatch(digits) ? '0$digits' : null;
}

/// Digits of an Algerian mobile as 05XXXXXXXX, whether written 05…, 5…,
/// +213… or with spaces (the website onboarding's `nationalPhone`).
String _nationalPhone(String value) {
  final String digits = value.replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^(00)?213[567]\d{8}$').hasMatch(digits)) {
    return '0${digits.substring(digits.length - 9)}';
  }
  if (_mobile.hasMatch(digits)) return '0$digits';
  return digits;
}

/// Whether a new [password] is the Student's [phone] in any of those
/// spellings (the website onboarding's `samePhone`).
bool isSamePhone(String password, String phone) {
  final String national = _nationalPhone(phone);
  return password == phone ||
      (RegExp(r'^0[567]\d{8}$').hasMatch(national) &&
          _nationalPhone(password) == national);
}
