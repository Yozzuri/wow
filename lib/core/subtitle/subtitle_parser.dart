import '../models/content_document.dart';

class SubtitleParseResult {
  const SubtitleParseResult({
    required this.format,
    required this.segments,
    this.metadata = const {},
  });

  final String format;
  final List<ContentSegment> segments;
  final Map<String, String> metadata;
}

/// Parses SRT / VTT / ASS / SSA / LRC subtitles into a shared timed segment
/// shape. The result can later be enriched by AI and serialized as a
/// [ContentDocument].
class SubtitleParser {
  const SubtitleParser._();

  static SubtitleParseResult parse(String raw, {String? fileName}) {
    final content = _stripBom(
      raw,
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final ext = (fileName ?? '').split('.').last.toLowerCase();

    if (ext == 'lrc' || _looksLikeLrc(content)) {
      return _parseLrc(content);
    }
    if (ext == 'ass' || ext == 'ssa' || content.contains('[Events]')) {
      return _parseAss(content);
    }
    if (ext == 'vtt' || content.trimLeft().startsWith('WEBVTT')) {
      return _parseVtt(content);
    }
    return _parseSrt(content);
  }

  static String _stripBom(String text) =>
      text.startsWith('\uFEFF') ? text.substring(1) : text;

  static bool _looksLikeLrc(String content) =>
      RegExp(r'^\[\d{1,2}:\d{1,2}(?:[.:]\d{1,3})?\]', multiLine: true)
          .hasMatch(content);

  static int _timestampToMs(String value) {
    final match = RegExp(
      r'(\d{1,3}):(\d{2}):(\d{2})[,.](\d{1,3})',
    ).firstMatch(value.trim());
    if (match == null) {
      return 0;
    }
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final fraction = match.group(4)!;
    final ms = fraction.length == 1
        ? int.parse(fraction) * 100
        : fraction.length == 2
        ? int.parse(fraction) * 10
        : int.parse(fraction);
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + ms;
  }

  static int _assTimestampToMs(String value) {
    final match = RegExp(
      r'(\d{1,3}):(\d{2}):(\d{2})[.:](\d{1,3})',
    ).firstMatch(value.trim());
    if (match == null) {
      return 0;
    }
    final fraction = match.group(4)!;
    final cs = fraction.length == 1
        ? int.parse(fraction) * 10
        : int.parse(fraction);
    return ((int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!)) *
                60 +
            int.parse(match.group(3)!)) *
            1000 +
        cs * 10;
  }

  static String _cleanLine(String text) {
    var value = text
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\h', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    value = value
        .split('\n')
        .map(normalizeWhitespace)
        .where((line) => line.isNotEmpty)
        .join('\n');
    return value.trim();
  }

  static List<ContentSegment> _segmentsFromLines(
    List<({int startMs, int endMs, String text})> lines,
  ) {
    final sorted = [...lines]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final segments = <ContentSegment>[];
    for (var i = 0; i < sorted.length; i++) {
      final line = sorted[i];
      var end = line.endMs > line.startMs ? line.endMs : line.startMs + 2500;
      if (i + 1 < sorted.length && end > sorted[i + 1].startMs) {
        end = sorted[i + 1].startMs;
      }
      if (end < line.startMs) {
        end = line.startMs;
      }
      segments.add(
        ContentSegment(
          index: segments.length,
          startMs: line.startMs,
          endMs: end,
          text: line.text,
        ),
      );
    }
    return segments;
  }

  static SubtitleParseResult _parseSrt(String content) {
    final blocks = content.split(RegExp(r'\n\s*\n'));
    final lines = <({int startMs, int endMs, String text})>[];
    for (final block in blocks) {
      final rawLines = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (rawLines.isEmpty) {
        continue;
      }
      var cursor = 0;
      if (RegExp(r'^\d+$').hasMatch(rawLines[0])) {
        cursor = 1;
      }
      if (cursor >= rawLines.length) {
        continue;
      }
      final timing = rawLines[cursor];
      if (!timing.contains('-->')) {
        continue;
      }
      final parts = timing.split('-->');
      if (parts.length < 2) {
        continue;
      }
      final text = _cleanLine(rawLines.skip(cursor + 1).join('\n'));
      if (text.isEmpty) {
        continue;
      }
      lines.add((
        startMs: _timestampToMs(parts[0]),
        endMs: _timestampToMs(parts[1]),
        text: text,
      ));
    }
    return SubtitleParseResult(
      format: 'srt',
      segments: _segmentsFromLines(lines),
    );
  }

  static SubtitleParseResult _parseVtt(String content) {
    final stripped = content.replaceFirst(
      RegExp(r'^\s*WEBVTT[^\n]*\n?'),
      '',
    );
    final blocks = stripped.split(RegExp(r'\n\s*\n'));
    final lines = <({int startMs, int endMs, String text})>[];
    for (final block in blocks) {
      final rawLines = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (rawLines.isEmpty) {
        continue;
      }
      if (rawLines[0].startsWith('NOTE') ||
          rawLines[0].startsWith('STYLE') ||
          rawLines[0].startsWith('REGION')) {
        continue;
      }
      var timingIndex = rawLines.indexWhere((line) => line.contains('-->'));
      if (timingIndex < 0) {
        continue;
      }
      final timing = rawLines[timingIndex];
      final parts = timing.split('-->');
      if (parts.length < 2) {
        continue;
      }
      final endPart = parts[1].trim().split(RegExp(r'\s+')).first;
      final text = _cleanLine(
        rawLines.skip(timingIndex + 1).join('\n'),
      );
      if (text.isEmpty) {
        continue;
      }
      lines.add((
        startMs: _timestampToMs(parts[0]),
        endMs: _timestampToMs(endPart),
        text: text,
      ));
    }
    return SubtitleParseResult(
      format: 'vtt',
      segments: _segmentsFromLines(lines),
    );
  }

  static SubtitleParseResult _parseAss(String content) {
    List<String>? formatFields;
    final lines = <({int startMs, int endMs, String text})>[];
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.toLowerCase().startsWith('format:')) {
        formatFields = line
            .substring(line.indexOf(':') + 1)
            .split(',')
            .map((field) => field.trim().toLowerCase())
            .toList();
        continue;
      }
      if (!line.toLowerCase().startsWith('dialogue:') ||
          formatFields == null) {
        continue;
      }
      final parts = _splitAssDialogue(
        line.substring(line.indexOf(':') + 1),
        formatFields.length,
      );
      if (parts.length < formatFields.length) {
        continue;
      }
      final startIndex = formatFields.indexOf('start');
      final endIndex = formatFields.indexOf('end');
      final textIndex = formatFields.indexOf('text');
      if (startIndex < 0 || endIndex < 0 || textIndex < 0) {
        continue;
      }
      final text = _cleanLine(parts[textIndex]);
      if (text.isEmpty) {
        continue;
      }
      lines.add((
        startMs: _assTimestampToMs(parts[startIndex]),
        endMs: _assTimestampToMs(parts[endIndex]),
        text: text,
      ));
    }
    return SubtitleParseResult(
      format: 'ass',
      segments: _segmentsFromLines(lines),
    );
  }

  static List<String> _splitAssDialogue(String value, int fieldCount) {
    final result = <String>[];
    var start = 0;
    for (var i = 0; i < value.length && result.length < fieldCount - 1; i++) {
      if (value[i] == ',') {
        result.add(value.substring(start, i));
        start = i + 1;
      }
    }
    result.add(value.substring(start));
    return result;
  }

  static SubtitleParseResult _parseLrc(String content) {
    final metadata = <String, String>{};
    final entries = <({int startMs, String text})>[];
    final offset = <int>[0];

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final metaMatch = RegExp(r'^\[(ti|ar|al|by|offset):(.*)\]$').firstMatch(
        line,
      );
      if (metaMatch != null) {
        final key = metaMatch.group(1)!.toLowerCase();
        final value = metaMatch.group(2)!.trim();
        if (key == 'offset') {
          offset[0] = int.tryParse(value) ?? 0;
        } else {
          metadata[key] = value;
        }
        continue;
      }

      final timeTags = RegExp(
        r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
      ).allMatches(line).toList();
      if (timeTags.isEmpty) {
        continue;
      }
      var text = line.substring(timeTags.last.end).trim();
      text = text
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .trim();
      if (text.isEmpty) {
        continue;
      }
      for (final tag in timeTags) {
        final minutes = int.parse(tag.group(1)!);
        final seconds = int.parse(tag.group(2)!);
        final fraction = tag.group(3);
        final ms = fraction == null
            ? 0
            : fraction.length == 1
            ? int.parse(fraction) * 100
            : fraction.length == 2
            ? int.parse(fraction) * 10
            : int.parse(fraction);
        entries.add((
          startMs: ((minutes * 60 + seconds) * 1000 + ms),
          text: text,
        ));
      }
    }

    entries.sort((a, b) => a.startMs.compareTo(b.startMs));
    final adjustedOffset = -offset[0];
    final segments = <ContentSegment>[];
    for (var i = 0; i < entries.length; i++) {
      final start = (entries[i].startMs + adjustedOffset).clamp(
        0,
        1 << 62,
      ).toInt();
      final end = i + 1 < entries.length
          ? (entries[i + 1].startMs + adjustedOffset).clamp(
              start,
              1 << 62,
            ).toInt()
          : start + 4000;
      segments.add(
        ContentSegment(
          index: i,
          startMs: start,
          endMs: end,
          text: entries[i].text,
        ),
      );
    }
    return SubtitleParseResult(
      format: 'lrc',
      segments: segments,
      metadata: metadata,
    );
  }
}
