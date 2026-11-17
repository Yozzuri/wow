import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/ai/phrase_extractor.dart';
import 'package:langlearn/core/ai/word_analysis.dart';
import 'package:langlearn/core/models/content_document.dart';
import 'package:langlearn/core/vocab/wordbook.dart';

void main() {
  test('phrase parses normalized pattern and example', () {
    final phrase = ContentPhrase.fromJson(const {
      'pattern': 'take ... to do ...',
      'example': 'take notes to learn better',
      'meaning': '做笔记来学习',
      'usage': 'take + 名词 + to do',
    });
    expect(phrase.text, 'take ... to do ...');
    expect(phrase.example, 'take notes to learn better');
  });

  test('reading phrase extractor parses patterns', () {
    const raw =
        '{"phrases":[{"pattern":"take ... to do ...",'
        '"example":"take notes to learn better","meaning":"做笔记来学习"}]}';
    final phrases = parseReadingPhrases(raw);
    expect(phrases, hasLength(1));
    expect(phrases.single.text, 'take ... to do ...');
  });

  test('wordbook entries round-trip analysis-style fields', () {
    const entry = WordbookEntry(
      word: 'building',
      lemma: 'building',
      relation: '由 build 派生，现已独立为名词',
      senses: [WordSense(pos: 'n.', meaning: '建筑物')],
      examples: ['a tall building'],
      forms: [WordFormInfo(label: '复数', value: 'buildings')],
    );
    final decoded = WordbookEntry.fromJson(
      (jsonDecode(jsonEncode(entry.toJson())) as Map).cast<String, dynamic>(),
    );
    expect(decoded.displayMeaning, 'n. 建筑物');
    expect(decoded.primaryExample, 'a tall building');
    expect(decoded.forms.single.value, 'buildings');
    expect(decoded.headword, 'building');
  });

  test('legacy flat wordbook fields still work', () {
    final entry = WordbookEntry.fromJson(const {
      'word': 'run',
      'pos': 'v.',
      'meaning': '跑',
      'example': 'I run every day.',
    });
    expect(entry.displayMeaning, '跑');
    expect(entry.displayPos, 'v.');
    expect(entry.primaryExample, 'I run every day.');
  });
}
