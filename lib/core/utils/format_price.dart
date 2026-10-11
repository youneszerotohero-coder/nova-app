/// The website's price (`formatPrice`, data/catalog.ts: `toLocaleString('en-DZ')`
/// + " DZD"), e.g. 18900 -> "18,900 DZD" in every language. The comma keeps the
/// digit groups together, so Arabic text shows "DZD 18,900" as the website does.
String formatDaPrice(int amount) {
  final String digits = amount.abs().toString();
  final StringBuffer buffer = StringBuffer(amount < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final int remaining = digits.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) buffer.write(',');
  }
  return '$buffer DZD';
}

/// A discount badge, e.g. 23 -> minus sign + "23%", kept in that order in Arabic.
String formatDiscount(int percent) => '\u200E\u2212$percent%';
