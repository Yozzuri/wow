import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/models/content_document.dart';

void main() {
  test('ContentDocument round-trips through JSON', () {
    final document = ContentDocument(
      kind: ContentKind.video,
      meta: const ContentMeta(
        title: 'Demo',
        source: 'demo.srt',
        language: 'en',
        durationMs: 60000,
      ),
      segments: const [
        ContentSegment(
          index: 0,
          startMs: 1000,
          endMs: 2500,
          text: 'Hello world',
          translation: '你好世界',
          tokens: [
            ContentToken(
              surface: 'Hello',
              lemma: 'hello',
              pos: 'int.',
              meaning: '你好',
            ),
          ],
          grammar: [
            GrammarNote(pattern: 'Hello world', explanation: 'greeting'),
          ],
        ),
      ],
    );

    final decoded = jsonDecode(jsonEncode(document.toJson()));
    final restored = ContentDocument.fromJson(
      (decoded as Map).cast<String, dynamic>(),
    );

    expect(restored.kind, ContentKind.video);
    expect(restored.meta.title, 'Demo');
    expect(restored.meta.language, 'en');
    expect(restored.segments, hasLength(1));
    expect(restored.segments.first.translation, '你好世界');
    expect(restored.segments.first.tokens.first.lemma, 'hello');
    expect(restored.segments.first.grammar.first.pattern, 'Hello world');
  });

  test('segmentAt finds the active segment', () {
    const document = ContentDocument(
      meta: ContentMeta(title: 'Demo'),
      segments: [
        ContentSegment(index: 0, startMs: 0, endMs: 1000, text: 'a'),
        ContentSegment(index: 1, startMs: 2000, endMs: 3000, text: 'b'),
      ],
    );

    expect(document.segmentAt(500)?.text, 'a');
    expect(document.segmentAt(2500)?.text, 'b');
    expect(document.segmentAt(1500), isNull);
  });
}
