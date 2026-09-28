/// Search matching that forgives how students type: case, Arabic
/// harakat, tatweel and letter variants (أ/إ/آ → ا, ى → ي, ة → ه), and
/// French accents (é → e, ç → c).
bool searchMatches(String text, String query) {
  final String q = searchKey(query).trim();
  return q.isEmpty || searchKey(text).contains(q);
}

/// [text] reduced to its comparable form.
String searchKey(String text) {
  final StringBuffer out = StringBuffer();
  for (final int rune in text.toLowerCase().runes) {
    // Harakat, superscript alef and tatweel carry no letter.
    if ((rune >= 0x064B && rune <= 0x065F) || rune == 0x0670 || rune == 0x0640) {
      continue;
    }
    out.write(_folded[rune] ?? String.fromCharCode(rune));
  }
  return out.toString();
}

const Map<int, String> _folded = <int, String>{
  0x0623: 'ا', // أ
  0x0625: 'ا', // إ
  0x0622: 'ا', // آ
  0x0671: 'ا', // ٱ
  0x0649: 'ي', // ى
  0x0626: 'ي', // ئ
  0x0624: 'و', // ؤ
  0x0629: 'ه', // ة
  0x00E0: 'a', 0x00E2: 'a', 0x00E4: 'a',
  0x00E7: 'c',
  0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
  0x00EE: 'i', 0x00EF: 'i',
  0x00F4: 'o', 0x00F6: 'o',
  0x00F9: 'u', 0x00FB: 'u', 0x00FC: 'u',
  0x0153: 'oe',
};
