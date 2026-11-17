import 'dart:convert';

import '../language/languages.dart';
import 'ai_client.dart';
import 'ai_settings.dart';
import 'chunk_cache.dart';

class SegmentationService {
  const SegmentationService();

  static const _cache = AiChunkCache();
  static const _promptVersion = 'segment|v1';

  Future<List<String>> segment({
    required AiConfig config,
    required String text,
    required String language,
    bool force = false,
  }) async {
    final source = text.trim();
    if (source.isEmpty || source.length > 2000) {
      return const [];
    }
    final key = _cache.keyFor(_promptVersion, language, source);
    if (!force) {
      final cached = await _cache.read(key);
      if (cached != null) {
        return _validate(_parse(cached), source);
      }
    }
    final raw = await AiClient(config).chat(
      messages: [
        {
          'role': 'system',
          'content':
              'You split text into natural word chunks for language learners. '
              'The text language is '
              '${readingLanguageFor(language).label} ($language). '
              'Return ONLY one JSON object without markdown fences: '
              '{"words":["chunk","chunk",...]}. '
              'Concatenating every chunk must reproduce the original text '
              'exactly, including spaces and punctuation. Split names, '
              'particles and compound words naturally; never split a word '
              'into single characters unless the language genuinely uses '
              'single-character words. Do not translate or annotate.',
        },
        {'role': 'user', 'content': source},
      ],
      maxTokens: 1600,
    );
    await _cache.write(key, raw);
    return _validate(_parse(raw), source);
  }

  List<String> _validate(List<String> words, String source) {
    if (words.isEmpty) {
      return words;
    }
    final joined = words.join().replaceAll(RegExp(r'\s+'), '');
    final original = source.replaceAll(RegExp(r'\s+'), '');
    return joined == original ? words : const [];
  }

  List<String> _parse(String raw) {
    var text = raw.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return const [];
    }
    text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const [];
      }
      final words = decoded['words'];
      if (words is! List) {
        return const [];
      }
      return words
          .whereType<String>()
          .where((word) => word.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
