/// Katakana -> hiragana, leaving other characters untouched.
String katakanaToHiragana(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      buffer.writeCharCode(rune - 0x60);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Extracts the kana part of a reading such as "かぐや [1]" or "カグヤ".
/// Pitch numbers, brackets and spaces are dropped; katakana becomes hiragana.
String japaneseKanaOf(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x3041 && rune <= 0x3096) {
      buffer.writeCharCode(rune);
    } else if (rune >= 0x30A1 && rune <= 0x30F6) {
      buffer.writeCharCode(rune - 0x60);
    } else if (rune == 0x30FC || rune == 0x309D || rune == 0x309E) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
