import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/ai/word_analysis.dart';

void main() {
  test('parses an inflected word with POS-bound senses and forms', () {
    const raw =
        '{"classification":"inflected","lemma":"build","surfaceReading":"/ˈbɪldɪŋ/",'
        '"lemmaReading":"/bɪld/","relation":"building 在这里是 build 的现在分词",'
        '"senses":[{"pos":"v.","meaning":"建造"},{"pos":"n.","meaning":"建筑物"}],'
        '"usage":"build sth","examples":["They build houses."],'
        '"forms":[{"label":"过去式","value":"built"},{"label":"现在分词","value":"building"}],'
        '"inflection":{"changed":true,"summary":"building → build","explanation":"去 ing 还原"},'
        '"lemmaSentence":"They build houses.","detail":"**详解**"}';
    final analysis = parseWordAnalysis(
      raw,
      surface: 'building',
      sentence: 'They are building houses.',
    );
    expect(analysis.kind, WordFormKind.inflected);
    expect(analysis.lemma, 'build');
    expect(analysis.senses.length, 2);
    expect(analysis.senses.first.pos, 'v.');
    expect(analysis.meaningSummary, contains('n. 建筑物'));
    expect(
      analysis.forms.map((form) => form.value),
      containsAll(['built', 'building']),
    );
    expect(analysis.surfaceReading, '/ˈbɪldɪŋ/');
    expect(analysis.inflectionChanged, isTrue);
  });

  test('treats an independent lexical item as its own lemma', () {
    const raw =
        '{"classification":"independent","lemma":"build","surfaceReading":"/ˈbɪldɪŋ/",'
        '"relation":"building 源自动词 build，现已独立为名词",'
        '"senses":[{"pos":"n.","meaning":"建筑物"}],'
        '"forms":[{"label":"复数","value":"buildings"}],'
        '"inflection":{"changed":false}}';
    final analysis = parseWordAnalysis(
      raw,
      surface: 'building',
      sentence: 'The building is tall.',
    );
    expect(analysis.kind, WordFormKind.independent);
    expect(analysis.lemma, 'building');
    expect(analysis.inflectionChanged, isFalse);
    expect(analysis.relation, contains('独立'));
    expect(analysis.senses.single.pos, 'n.');
  });

  test('keeps old flat pos and meaning fields working', () {
    const raw = '{"lemma":"run","pos":"v.","meaning":"跑"}';
    final analysis = parseWordAnalysis(
      raw,
      surface: 'run',
      sentence: 'I run every day.',
    );
    expect(analysis.kind, WordFormKind.lemma);
    expect(analysis.senses.single.pos, 'v.');
    expect(analysis.senses.single.meaning, '跑');
  });

  test('repairs fenced json with trailing commas and raw newlines', () {
    final raw =
        '\u0060\u0060\u0060json\n'
        '{"classification":"lemma","lemma":"run",'
        '"senses":[{"pos":"v.","meaning":"跑"},],'
        '"detail":"第一行\n第二行"}\n'
        '\u0060\u0060\u0060';
    final analysis = parseWordAnalysis(
      raw,
      surface: 'run',
      sentence: 'I run every day.',
    );
    expect(analysis.parseFailed, isFalse);
    expect(analysis.senses.single.meaning, '跑');
    expect(analysis.detailMarkdown, contains('第二行'));
  });

  test('flags a broken json instead of exposing the raw text', () {
    const raw = '{"lemma":"run","senses":[';
    final analysis = parseWordAnalysis(
      raw,
      surface: 'run',
      sentence: 'I run every day.',
    );
    expect(analysis.parseFailed, isTrue);
    expect(analysis.detailMarkdown, isEmpty);
  });
}
