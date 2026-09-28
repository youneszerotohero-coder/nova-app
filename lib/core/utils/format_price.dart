/// Formats an integer DA amount with thin-space thousands separators,
/// e.g. 18900 -> "18 900 DA".
///
/// A leading left-to-right mark keeps the amount in reading order inside
/// Arabic text; without it the digit groups flip ("DA 900 18").
String formatDaPrice(int amount) {
  final String digits = amount.toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final int remaining = digits.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) buffer.write('\u2009');
  }
  return '\u200E$buffer DA';
}

/// A discount badge, e.g. 23 -> minus sign + "23%", kept in that order in Arabic.
String formatDiscount(int percent) => '\u200E\u2212$percent%';
