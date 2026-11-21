import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/text/japanese_kana.dart';

void main() {
  test('katakana converts to hiragana', () {
    expect(katakanaToHiragana('カグヤ'), 'かぐや');
    expect(katakanaToHiragana('abc'), 'abc');
  });

  test('reading keeps only kana and drops pitch and brackets', () {
    expect(japaneseKanaOf('かぐや [1]'), 'かぐや');
    expect(japaneseKanaOf('カグヤ'), 'かぐや');
    expect(japaneseKanaOf('かぐや（0）'), 'かぐや');
    expect(japaneseKanaOf('hello'), '');
  });
}
