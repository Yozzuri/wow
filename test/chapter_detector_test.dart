import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/reading/chapter_detector.dart';

void main() {
  test('detects English and Chinese chapter headings', () {
    const content = 'Intro text\nChapter 1\nFirst body\n\n第2章 开始\nSecond body';
    final chapters = detectChapters(content);
    expect(chapters, hasLength(2));
    expect(chapters.first.title, 'Chapter 1');
    expect(chapters.last.title, '第2章 开始');
    expect(chapters.first.start, lessThan(chapters.last.start));
    expect(chapters.last.end, content.length);
  });

  test('creates pseudo chapters when no heading exists', () {
    final content = List.generate(70, (i) => 'Paragraph $i').join('\n\n');
    final chapters = detectChapters(
      content,
      fallback: ChapterFallback.pseudo,
      pseudoParagraphs: 30,
    );
    expect(chapters.length, 3);
    expect(chapters.first.title, '第 1 部分');
  });
}
