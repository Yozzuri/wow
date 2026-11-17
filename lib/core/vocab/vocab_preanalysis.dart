import '../ai/ai_settings.dart';
import '../ai/chunk_cache.dart';
import '../ai/word_analysis.dart';
import 'vocab_store.dart';

class VocabPreAnalyzer {
  const VocabPreAnalyzer();

  Future<int> analyze({
    required AiConfig config,
    required List<VocabEntry> entries,
    void Function(int done, int total)? onProgress,
  }) async {
    final unique = <String, VocabEntry>{};
    for (final entry in entries) {
      final key = '${entry.language}|${entry.word}|${entry.sentence}';
      unique.putIfAbsent(key, () => entry);
    }
    final list = unique.values.toList();
    var done = 0;
    await runWithConcurrency(list, 2, (entry, _) async {
      try {
        await const WordAnalyzer().analyze(
          config: config,
          word: entry.word.trim().isEmpty ? entry.lemma : entry.word,
          sentence: entry.sentence,
          language: entry.language,
          lemmaHint: entry.lemma,
        );
      } catch (_) {
        // Keep going; individual failures should not abort the batch.
      }
      done++;
      onProgress?.call(done, list.length);
    });
    return list.length;
  }
}
