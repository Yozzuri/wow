import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/ai/word_analysis.dart';

void main() {
  test('parses structured word analysis and builds blockquote', () {
    const raw =
        '{"lemma":"食べる","reading":"たべる","pos":"動詞","inflection":{"changed":true,"summary":"食べる → 食べました","explanation":"ます形過去"},"lemmaSentence":"毎日ご飯を食べる。","usage":"食べる + ます","meaning":"吃了","examples":["ご飯を食べる"],"detail":"**详解**"}';
    final analysis = parseWordAnalysis(
      raw,
      surface: '食べました',
      sentence: '毎日ご飯を食べました。',
    );
    expect(analysis.lemma, '食べる');
    expect(analysis.inflectionChanged, isTrue);
    expect(analysis.lemmaSentence, '毎日ご飯を食べる。');
    expect(analysis.inflectionMarkdown, contains('> **变形说明**'));
    expect(analysis.examples, ['ご飯を食べる']);
  });

  test('falls back when AI does not return JSON', () {
    final analysis = parseWordAnalysis(
      '这是一段普通回答',
      surface: '食べました',
      sentence: '毎日ご飯を食べました。',
      lemmaHint: '食べる',
    );
    expect(analysis.lemma, '食べる');
    expect(analysis.lemmaSentence, '毎日ご飯を食べる。');
    expect(analysis.parseFailed, isTrue);
    expect(analysis.detailMarkdown, isEmpty);
  });
}
