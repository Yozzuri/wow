import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/text/normalize.dart';
import 'package:langlearn/core/text/tokenizer.dart';

void main() {
  test('tokenizes Latin, CJK, kana and Hangul', () {
    final words = tokenizeLine("Hello, 世界! こんにちは 안녕하세요 Привет")
        .where(isWordToken)
        .toList();
    expect(words, containsAll(['Hello', '世', '界']));
    expect(words, contains('こ'));
    expect(words, contains('ん'));
    expect(words, contains('안녕하세요'));
    expect(words, contains('Привет'));
  });

  test('segments Japanese into words instead of characters', () {
    final chunks = textChunks(
      'こんにちは、このレッスンへようこそ。',
      language: 'ja',
    );
    final words = chunks
        .where((chunk) => chunk.word != null)
        .map((chunk) => chunk.word)
        .toList();
    expect(
      chunks.map((chunk) => chunk.text).join(),
      'こんにちは、このレッスンへようこそ。',
    );
    expect(words, contains('こんにちは'));
    expect(words, contains('レッスン'));
    expect(words, isNot(contains('こ')));
  });

  test('keeps kana when normalizing titles', () {
    expect(normalizeForMatch('夜に駆ける (Official)'), '夜に駆ける');
    expect(normalizeForMatch('ノンブレス・オブリージュ'), 'ノンブレス・オブリージュ');
  });
}
