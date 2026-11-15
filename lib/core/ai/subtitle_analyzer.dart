import 'dart:convert';
import 'dart:math';

import 'ai_client.dart';
import 'ai_settings.dart';
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

  Future<List<ContentSegment>> analyze({
    required AiConfig config,
    required ContentDocument document,
    int batchSize = 10,
    void Function(double progress)? onProgress,
  }) async {
    final client = AiClient(config);
    final enriched = <ContentSegment>[];
    final total = document.segments.length;
    for (var start = 0; start < total; start += batchSize) {
      final end = min(start + batchSize, total);
      final batch = document.segments.sublist(start, end);
      final analyzed = await _analyzeBatch(
        client: client,
        batch: batch,
        language: document.meta.language,
      );
      for (final segment in batch) {
        final result = analyzed[segment.index];
        enriched.add(
          result == null
              ? segment
              : segment.copyWith(
                  translation: result.translation,
                  tokens: result.tokens.isEmpty
                      ? segment.tokens
                      : result.tokens,
                  grammar: result.grammar.isEmpty
                      ? segment.grammar
                      : result.grammar,
                  phrases: result.phrases.isEmpty
                      ? segment.phrases
                      : result.phrases,
                ),
        );
      }
      onProgress?.call(end / total);
    }
    return enriched;
  }

  Future<Map<int, AnalyzedSegment>> _analyzeBatch({
    required AiClient client,
    required List<ContentSegment> batch,
    required String language,
  }) async {
    try {
      final raw = await _requestWithRetry(
        client: client,
        batch: batch,
        language: language,
      );
      return parseAnalysisResponse(raw);
    } on FormatException {
      if (batch.length <= 1) {
        rethrow;
      }
      final middle = batch.length ~/ 2;
      final left = await _analyzeBatch(
        client: client,
        batch: batch.sublist(0, middle),
        language: language,
      );
      final right = await _analyzeBatch(
        client: client,
        batch: batch.sublist(middle),
        language: language,
      );
      return {...left, ...right};
    }
  }

  Future<String> _requestWithRetry({
    required AiClient client,
    required List<ContentSegment> batch,
    required String language,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await client.chat(
        messages: _messages(batch, language),
        maxTokens: 3200,
      );
      try {
        parseAnalysisResponse(raw);
        return raw;
      } on FormatException {
        if (attempt == 1) {
          rethrow;
        }
      }
    }
    throw FormatException('AI 未返回可解析的 JSON');
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
            '"phrases":[{"text":"multi-word phrase from the text","meaning":"short Chinese meaning","usage":"short usage note"}]}]}. '
            'Keep every input index exactly once. Include at most 8 useful content tokens, '
            '0-2 grammar notes and 0-4 useful phrases per segment. Phrases must appear '
            'in the original text. For Japanese, Chinese or Thai, segment tokens into '
            'natural words instead of single characters. Source language: '
            '${readingLanguageFor(language).label} ($language). Do not add commentary.',
      },
      {'role': 'user', 'content': jsonEncode(payload)},
    ];
  }
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
        final text = (rawPhrase['text'] as String?)?.trim();
        if (text == null || text.isEmpty) {
          continue;
        }
        phrases.add(
          ContentPhrase(
            text: text,
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
