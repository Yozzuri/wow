import 'dart:convert';

import '../language/languages.dart';
import '../models/content_document.dart';
import 'ai_client.dart';
import 'ai_settings.dart';
import 'chunk_cache.dart';

class PhraseExtractor {
  const PhraseExtractor();

  static const _cache = AiChunkCache();
  static const _promptVersion = 'reading_phrase|v1';

  Future<List<ContentPhrase>> extract({
    required AiConfig config,
    required String paragraph,
    required String language,
    bool force = false,
  }) async {
    if (paragraph.trim().isEmpty) {
      return const [];
    }
    final cacheKey = _cache.keyFor(_promptVersion, language, paragraph);
    if (!force) {
      final cached = await _cache.read(cacheKey);
      if (cached != null) {
        return parseReadingPhrases(cached);
      }
    }
    final raw = await AiClient(config).chat(
      messages: [
        {
          'role': 'system',
          'content':
              'You extract reusable phrases for language learners. '
              'Answer in Chinese. The text language is '
              '${readingLanguageFor(language).label} ($language). '
              'Return ONLY one JSON object without markdown fences: '
              '{"phrases":[{"pattern":"take ... to do ...",'
              '"example":"literal fragment from the text",'
              '"meaning":"short Chinese meaning",'
              '"usage":"short usage note"}]}. '
              'Extract 2-5 useful phrases. Normalize each phrase into a '
              'reusable pattern with ... placeholders instead of copying the '
              'literal fragment. example must be an exact substring of the '
              'text. Apply the same normalization to every language. '
              'If there is nothing useful, return {"phrases":[]}.',
        },
        {'role': 'user', 'content': paragraph},
      ],
      maxTokens: 1200,
    );
    await _cache.write(cacheKey, raw);
    return parseReadingPhrases(raw);
  }
}

List<ContentPhrase> parseReadingPhrases(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final newline = text.indexOf('\n');
    if (newline >= 0) {
      text = text.substring(newline + 1);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return const [];
  }
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! Map) {
      return const [];
    }
    final list = decoded['phrases'];
    if (list is! List) {
      return const [];
    }
    return list
        .whereType<Map>()
        .map((item) => ContentPhrase.fromJson(item.cast<String, dynamic>()))
        .where((phrase) => phrase.text.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}
