import '../ai/ai_settings.dart';
import '../ai/chunk_cache.dart';
import '../ai/word_analysis.dart';
import 'wordbook.dart';

class WordbookEnricher {
  const WordbookEnricher();

  Future<Wordbook> enrich({
    required AiConfig config,
    required Wordbook book,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = List<WordbookEntry?>.filled(book.entries.length, null);
    var done = 0;
    await runWithConcurrency(book.entries, 2, (entry, index) async {
      try {
        final analysis = await const WordAnalyzer().analyze(
          config: config,
          word: entry.headword,
          sentence: entry.primaryExample,
          language: book.language,
          lemmaHint: entry.headword,
        );
        results[index] = WordbookEntry.fromAnalysis(analysis, fallback: entry);
      } catch (_) {
        results[index] = entry;
      }
      done++;
      onProgress?.call(done, book.entries.length);
    });
    return Wordbook(
      id: book.id,
      name: book.name,
      language: book.language,
      createdAt: book.createdAt,
      entries: results.whereType<WordbookEntry>().toList(),
    );
  }
}
