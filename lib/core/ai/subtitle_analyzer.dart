import 'dart:convert';

import 'ai_client.dart';
import 'ai_settings.dart';
import 'chunk_cache.dart';
import '../language/languages.dart';
import '../models/content_document.dart';

class AnalyzedSegment {
  const AnalyzedSegment({
    this.translation,
    this.tokens = const [],
    this.grammar = const [],
    this.phrases = const [],
  });

  final String? translation;
  final List<ContentToken> tokens;
  final List<GrammarNote> grammar;
  final List<ContentPhrase> phrases;
}

class SubtitleAnalyzer {
  const SubtitleAnalyzer();

  static const _cache = AiChunkCache();
  static const _promptVersion = 'v3';

  Future<List<ContentSegment>> analyze({
    required AiConfig config,
    required ContentDocument document,
    int batchSize = 10,
    int maxChars = 1500,
    int concurrency = 3,
    bool force = false,
    void Function(
      Map<int, AnalyzedSegment> batch,
      int completed,
      int total,
      int failed,
    )? onBatch,
  }) async {
    final chunks = _planChunks(
      document.segments,
      maxSegments: batchSize,
      maxChars: maxChars,
    );
    final client = AiClient(config);
    final language = document.meta.language;
    final results = <int, Map<int, AnalyzedSegment>>{};
    var completed = 0;
    var failed = 0;
    await runWithConcurrency(chunks, concurrency, (chunk, index) async {
      try {
        final analyzed = await _analyzeChunk(
          client,
          chunk,
          language,
          force: force,
        );
        results[index] = analyzed;
        completed++;
        onBatch?.call(analyzed, completed, chunks.length, failed);
      } catch (_) {
        failed++;
        completed++;
        onBatch?.call(const {}, completed, chunks.length, failed);
      }
    });
    if (chunks.isNotEmpty && results.isEmpty) {
      throw const FormatException('AI 解析失败，请重试或检查接口');
    }
    final byIndex = <int, AnalyzedSegment>{};
    for (final map in results.values) {
      byIndex.addAll(map);
    }
    return _apply(document, byIndex).segments;
  }

  ContentDocument _apply(
    ContentDocument document,
    Map<int, AnalyzedSegment> analyzed,
  ) {
    return document.copyWith(
      segments: document.segments.map((segment) {
        final result = analyzed[segment.index];
        if (result == null) {
          return segment;
        }
        return segment.copyWith(
          translation: result.translation,
          tokens: result.tokens.isEmpty ? segment.tokens : result.tokens,
          grammar: result.grammar.isEmpty ? segment.grammar : result.grammar,
          phrases: result.phrases.isEmpty ? segment.phrases : result.phrases,
        );
      }).toList(),
    );
  }

  List<List<ContentSegment>> _planChunks(
    List<ContentSegment> segments, {
    required int maxSegments,
    required int maxChars,
  }) {
    final chunks = <List<ContentSegment>>[];
    var current = <ContentSegment>[];
    var chars = 0;
    for (final segment in segments) {
      final length = segment.text.length;
      if (current.isNotEmpty &&
          (current.length >= maxSegments || chars + length > maxChars)) {
        chunks.add(current);
        current = <ContentSegment>[];
        chars = 0;
      }
      current.add(segment);
      chars += length;
      if (length > maxChars) {
        chunks.add(current);
        current = <ContentSegment>[];
        chars = 0;
      }
    }
    if (current.isNotEmpty) {
      chunks.add(current);
    }
    return chunks;
  }

  Future<Map<int, AnalyzedSegment>> _analyzeChunk(
    AiClient client,
    List<ContentSegment> chunk,
    String language, {
    int depth = 0,
    bool force = false,
  }) async {
    final payload = jsonEncode(
      chunk.map((segment) => {'index': segment.index, 'text': segment.text}).toList(),
    );
    final cacheKey = _cache.keyFor(
      'subtitle|$_promptVersion',
      language,
      payload,
    );
    final cached = force ? null : await _cache.read(cacheKey);
    if (cached != null) {
      try {
        return parseAnalysisResponse(cached);
      } catch (_) {
        // Fall through to a fresh request.
      }
    }
    try {
      final raw = await _requestWithRetry(client, chunk, language);
      await _cache.write(cacheKey, raw);
      return parseAnalysisResponse(raw);
    } on FormatException {
      if (chunk.length <= 1 || depth >= 2) {
        rethrow;
      }
      final middle = chunk.length ~/ 2;
      final merged = <int, AnalyzedSegment>{};
      await runWithConcurrency(
        [chunk.sublist(0, middle), chunk.sublist(middle)],
        2,
        (part, _) async {
          merged.addAll(
            await _analyzeChunk(
              client,
              part,
              language,
              depth: depth + 1,
              force: force,
            ),
          );
        },
      );
      return merged;
    }
  }

  Future<String> _requestWithRetry(
    AiClient client,
    List<ContentSegment> batch,
    String language,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final raw = await client.chat(
          messages: _messages(batch, language),
          maxTokens: 2600,
        );
        parseAnalysisResponse(raw);
        return raw;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const FormatException('AI 未返回可解析的 JSON');
  }

  List<Map<String, String>> _messages(
    List<ContentSegment> batch,
    String language,
  ) {
    final payload = batch
        .map(
          (segment) => {
            'index': segment.index,
            'text': segment.text,
          },
        )
        .toList();
    return [
      {
        'role': 'system',
        'content':
            'You annotate subtitles for language learners. '
            'Return ONLY one JSON object without markdown fences: '
            '{"segments":[{"index":0,"translation":"Chinese translation",'
            '"tokens":[{"surface":"word as in text","lemma":"base form",'
            '"pos":"part of speech","meaning":"short Chinese meaning in context"}],'
            '"grammar":[{"pattern":"pattern","explanation":"short Chinese explanation"}],'
            '"phrases":[{"pattern":"take ... to do ...","example":"literal fragment from the text","meaning":"short Chinese meaning","usage":"short usage note"}]}]}. '
            'Keep every input index exactly once. Include at most 8 useful content tokens, '
            '0-2 grammar notes and 0-4 useful phrases per segment. Normalize each phrase into '
            'a reusable pattern with ... placeholders, for example take ... to do ...; do not '
            'copy the literal fragment as the pattern. The literal occurrence goes in example '
            'and must appear in the original text. Apply the same normalization to every language. '
            'For Japanese, Chinese or Thai, segment tokens into '
            'natural words instead of single characters. Source language: '
            '${readingLanguageFor(language).label} ($language). Do not add commentary.',
      },
      {'role': 'user', 'content': jsonEncode(payload)},
    ];
  }
}

ContentDocument applyAnalysis(
  ContentDocument document,
  Map<int, AnalyzedSegment> analyzed,
) {
  return document.copyWith(
    segments: document.segments.map((segment) {
      final result = analyzed[segment.index];
      if (result == null) {
        return segment;
      }
      return segment.copyWith(
        translation: result.translation,
        tokens: result.tokens.isEmpty ? segment.tokens : result.tokens,
        grammar: result.grammar.isEmpty ? segment.grammar : result.grammar,
        phrases: result.phrases.isEmpty ? segment.phrases : result.phrases,
      );
    }).toList(),
  );
}

Map<int, AnalyzedSegment> parseAnalysisResponse(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline >= 0) {
      text = text.substring(firstNewline + 1);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('AI 返回内容中没有 JSON');
  }
  var jsonText = text.substring(start, end + 1);
  dynamic decoded;
  try {
    decoded = jsonDecode(jsonText);
  } on FormatException {
    jsonText = jsonText
        .replaceAll(RegExp(r',\s*([}\]])'), r'$1')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    decoded = jsonDecode(jsonText);
  }
  final List segments;
  if (decoded is List) {
    segments = decoded;
  } else if (decoded is Map) {
    final rawSegments = decoded['segments'];
    if (rawSegments is! List) {
      throw const FormatException('AI JSON 缺少 segments 数组');
    }
    segments = rawSegments;
  } else {
    throw const FormatException('AI JSON 顶层不是对象');
  }
  final result = <int, AnalyzedSegment>{};
  for (final item in segments) {
    if (item is! Map) {
      continue;
    }
    final index = item['index'];
    if (index is! num) {
      continue;
    }
    final tokens = <ContentToken>[];
    final rawTokens = item['tokens'];
    if (rawTokens is List) {
      for (final rawToken in rawTokens) {
        if (rawToken is! Map) {
          continue;
        }
        final surface = (rawToken['surface'] as String?)?.trim();
        if (surface == null || surface.isEmpty) {
          continue;
        }
        tokens.add(
          ContentToken(
            surface: surface,
            lemma: (rawToken['lemma'] as String?)?.trim(),
            pos: (rawToken['pos'] as String?)?.trim(),
            meaning: (rawToken['meaning'] as String?)?.trim(),
          ),
        );
      }
    }
    final grammar = <GrammarNote>[];
    final rawGrammar = item['grammar'];
    if (rawGrammar is List) {
      for (final rawNote in rawGrammar) {
        if (rawNote is! Map) {
          continue;
        }
        final pattern = (rawNote['pattern'] as String?)?.trim();
        final explanation = (rawNote['explanation'] as String?)?.trim();
        if (pattern == null ||
            pattern.isEmpty ||
            explanation == null ||
            explanation.isEmpty) {
          continue;
        }
        grammar.add(GrammarNote(pattern: pattern, explanation: explanation));
      }
    }
    final phrases = <ContentPhrase>[];
    final rawPhrases = item['phrases'];
    if (rawPhrases is List) {
      for (final rawPhrase in rawPhrases) {
        if (rawPhrase is! Map) {
          continue;
        }
        final text =
            (rawPhrase['pattern'] as String?)?.trim() ??
            (rawPhrase['text'] as String?)?.trim();
        if (text == null || text.isEmpty) {
          continue;
        }
        phrases.add(
          ContentPhrase(
            text: text,
            example: (rawPhrase['example'] as String?)?.trim(),
            meaning: (rawPhrase['meaning'] as String?)?.trim(),
            usage: (rawPhrase['usage'] as String?)?.trim(),
          ),
        );
      }
    }
    final translation = (item['translation'] as String?)?.trim();
    final resolvedTranslation = (translation == null || translation.isEmpty)
        ? null
        : translation;
    if (resolvedTranslation == null &&
        tokens.isEmpty &&
        grammar.isEmpty &&
        phrases.isEmpty) {
      continue;
    }
    result[index.toInt()] = AnalyzedSegment(
      translation: resolvedTranslation,
      tokens: tokens,
      grammar: grammar,
      phrases: phrases,
    );
  }
  if (result.isEmpty) {
    throw const FormatException('AI JSON 中没有有效的字幕段');
  }
  return result;
}
