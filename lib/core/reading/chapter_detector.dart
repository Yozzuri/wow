import 'reading_book.dart';

enum ChapterFallback { single, pseudo, ask }

final RegExp _headingPattern = RegExp(
  r'^\s*(?:#{1,6}\s+|第[一二三四五六七八九十百千0-9]+[章节回卷部篇][^\n]*|'
  r'(?:chapter|part|book)\s+[0-9ivxlcdm]+[^\n]*|'
  r'[0-9]{1,3}[.、]\s+[^\n]+)\s*$',
  caseSensitive: false,
);

List<ReadingChapter> detectChapters(
  String content, {
  ChapterFallback fallback = ChapterFallback.single,
  int pseudoParagraphs = 30,
}) {
  final chapters = <ReadingChapter>[];
  final headingOffsets = <({int offset, String title})>[];
  var offset = 0;
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty &&
        trimmed.length <= 60 &&
        _headingPattern.hasMatch(trimmed)) {
      headingOffsets.add((offset: offset, title: trimmed));
    }
    offset += line.length + 1;
  }
  if (headingOffsets.isNotEmpty) {
    for (var i = 0; i < headingOffsets.length; i++) {
      final start = headingOffsets[i].offset;
      final end = i + 1 < headingOffsets.length
          ? headingOffsets[i + 1].offset
          : content.length;
      chapters.add(
        ReadingChapter(
          title: headingOffsets[i].title,
          start: start,
          end: end,
        ),
      );
    }
    return chapters;
  }
  if (fallback == ChapterFallback.pseudo) {
    final paragraphs = content
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
    final ranges = <({int start, int end})>[];
    var cursor = 0;
    for (final paragraph in paragraphs) {
      final start = content.indexOf(paragraph, cursor);
      if (start < 0) {
        continue;
      }
      final end = start + paragraph.length;
      ranges.add((start: start, end: end));
      cursor = end;
    }
    if (ranges.isNotEmpty) {
      for (var i = 0; i < ranges.length; i += pseudoParagraphs) {
        final start = ranges[i].start;
        final end = i + pseudoParagraphs < ranges.length
            ? ranges[i + pseudoParagraphs].start
            : content.length;
        chapters.add(
          ReadingChapter(
            title: '第 ${(i ~/ pseudoParagraphs) + 1} 部分',
            start: start,
            end: end,
          ),
        );
      }
    }
    if (chapters.isEmpty) {
      chapters.add(ReadingChapter(title: '正文', start: 0, end: content.length));
    }
    return chapters;
  }
  return [ReadingChapter(title: '正文', start: 0, end: content.length)];
}

