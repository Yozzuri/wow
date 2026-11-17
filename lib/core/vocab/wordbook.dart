import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ai/word_analysis.dart';

class WordbookEntry {
  const WordbookEntry({
    required this.word,
    this.lemma,
    this.reading,
    this.pitchAccent,
    this.pos,
    this.meaning = '',
    this.usage = '',
    this.example = '',
    this.surfaceReading,
    this.lemmaReading,
    this.relation = '',
    this.senses = const [],
    this.examples = const [],
    this.forms = const [],
    this.detail = '',
  });

  final String word;
  final String? lemma;
  final String? reading;
  final String? pitchAccent;

  /// Legacy flat fields, kept for old wordbooks.
  final String? pos;
  final String meaning;
  final String usage;
  final String example;

  final String? surfaceReading;
  final String? lemmaReading;
  final String relation;
  final List<WordSense> senses;
  final List<String> examples;
  final List<WordFormInfo> forms;
  final String detail;

  String get headword {
    final value = (lemma ?? word).trim();
    return value.isEmpty ? word.trim() : value;
  }

  String get displayMeaning {
    if (senses.isEmpty) {
      return meaning;
    }
    return senses
        .map(
          (sense) => sense.pos.isEmpty
              ? sense.meaning
              : '${sense.pos} ${sense.meaning}',
        )
        .where((value) => value.trim().isNotEmpty)
        .join('；');
  }

  String? get displayPos {
    for (final sense in senses) {
      if (sense.pos.trim().isNotEmpty) {
        return sense.pos.trim();
      }
    }
    return pos;
  }

  String? get displayReading => surfaceReading ?? reading;

  String get primaryExample {
    for (final item in examples) {
      if (item.trim().isNotEmpty) {
        return item.trim();
      }
    }
    return example.trim();
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    if (lemma != null) 'lemma': lemma,
    if (reading != null) 'reading': reading,
    if (pitchAccent != null) 'pitchAccent': pitchAccent,
    if (pos != null) 'pos': pos,
    'meaning': meaning,
    'usage': usage,
    'example': example,
    if (surfaceReading != null) 'surfaceReading': surfaceReading,
    if (lemmaReading != null) 'lemmaReading': lemmaReading,
    if (relation.isNotEmpty) 'relation': relation,
    if (senses.isNotEmpty)
      'senses': senses.map((sense) => sense.toJson()).toList(),
    if (examples.isNotEmpty) 'examples': examples,
    if (forms.isNotEmpty) 'forms': forms.map((form) => form.toJson()).toList(),
    if (detail.isNotEmpty) 'detail': detail,
  };

  factory WordbookEntry.fromJson(Map<String, dynamic> json) {
    final word = (json['word'] as String? ?? '').trim();
    final senses = (json['senses'] as List?)
            ?.whereType<Map>()
            .map((item) => WordSense.fromJson(item.cast<String, dynamic>()))
            .where((sense) => sense.meaning.isNotEmpty)
            .toList() ??
        const <WordSense>[];
    final examples =
        (json['examples'] as List?)?.whereType<String>().toList() ?? const [];
    final forms = (json['forms'] as List?)
            ?.whereType<Map>()
            .map((item) => WordFormInfo.fromJson(item.cast<String, dynamic>()))
            .where((form) => form.value.isNotEmpty)
            .toList() ??
        const <WordFormInfo>[];
    return WordbookEntry(
      word: word,
      lemma: (json['lemma'] as String?)?.trim(),
      reading: (json['reading'] as String?)?.trim(),
      pitchAccent: (json['pitchAccent'] as String?)?.trim(),
      pos: (json['pos'] as String?)?.trim(),
      meaning: (json['meaning'] as String? ?? '').trim(),
      usage: (json['usage'] as String? ?? '').trim(),
      example: (json['example'] as String? ?? '').trim(),
      surfaceReading:
          (json['surfaceReading'] as String?)?.trim() ??
          (json['reading'] as String?)?.trim(),
      lemmaReading: (json['lemmaReading'] as String?)?.trim(),
      relation: (json['relation'] as String? ?? '').trim(),
      senses: senses,
      examples: examples,
      forms: forms,
      detail: (json['detail'] as String? ?? '').trim(),
    );
  }

  factory WordbookEntry.fromAnalysis(
    WordAnalysis analysis, {
    WordbookEntry? fallback,
  }) {
    final surface = analysis.surface.trim().isEmpty
        ? (fallback?.word ?? analysis.lemma)
        : analysis.surface;
    return WordbookEntry(
      word: surface,
      lemma: analysis.lemma,
      reading: analysis.reading,
      pitchAccent: fallback?.pitchAccent,
      pos: analysis.pos,
      meaning: analysis.meaningSummary,
      usage: analysis.usage,
      example: analysis.examples.isNotEmpty
          ? analysis.examples.first
          : (fallback?.example ?? ''),
      surfaceReading: analysis.surfaceReading,
      lemmaReading: analysis.lemmaReading,
      relation: analysis.relation,
      senses: analysis.senses,
      examples: analysis.examples,
      forms: analysis.forms,
      detail: analysis.detailMarkdown,
    );
  }
}

class Wordbook {
  const Wordbook({
    required this.id,
    required this.name,
    required this.language,
    required this.createdAt,
    required this.entries,
  });

  final String id;
  final String name;
  final String language;
  final DateTime createdAt;
  final List<WordbookEntry> entries;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'language': language,
    'createdAt': createdAt.toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  factory Wordbook.fromJson(Map<String, dynamic> json) => Wordbook(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名词书',
    language: json['language'] as String? ?? 'en',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now(),
    entries:
        (json['entries'] as List?)
            ?.whereType<Map>()
            .map((entry) => WordbookEntry.fromJson(entry.cast<String, dynamic>()))
            .toList() ??
        const [],
  );
}

class WordbookStore {
  const WordbookStore();

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/wordbooks');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Wordbook> save(Wordbook wordbook) async {
    final dir = await _directory();
    final id = wordbook.id.isEmpty
        ? 'book_${DateTime.now().millisecondsSinceEpoch}'
        : wordbook.id;
    final saved = Wordbook(
      id: id,
      name: wordbook.name,
      language: wordbook.language,
      createdAt: wordbook.createdAt,
      entries: wordbook.entries,
    );
    final file = File('${dir.path}/$id.json');
    await file.writeAsString(jsonEncode(saved.toJson()));
    return saved;
  }

  Future<List<Wordbook>> list() async {
    final dir = await _directory();
    final books = <Wordbook>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        books.add(Wordbook.fromJson((json as Map).cast<String, dynamic>()));
      } catch (_) {
        // Ignore broken wordbook files.
      }
    }
    books.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
  }

  Future<void> delete(Wordbook wordbook) async {
    final dir = await _directory();
    final file = File('${dir.path}/${wordbook.id}.json');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Wordbook parseJson(String raw, {String fallbackLanguage = 'en'}) {
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
    if (start >= 0 && end > start) {
      text = text.substring(start, end + 1);
    }
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return Wordbook(
        id: 'book_${DateTime.now().millisecondsSinceEpoch}',
        name: '导入词书',
        language: fallbackLanguage,
        createdAt: DateTime.now(),
        entries: decoded
            .whereType<Map>()
            .map((entry) => WordbookEntry.fromJson(entry.cast<String, dynamic>()))
            .where((entry) => entry.word.isNotEmpty)
            .toList(),
      );
    }
    if (decoded is Map) {
      final map = decoded.cast<String, dynamic>();
      final entries = (map['entries'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => WordbookEntry.fromJson(entry.cast<String, dynamic>()))
          .where((entry) => entry.word.isNotEmpty)
          .toList();
      return Wordbook(
        id: 'book_${DateTime.now().millisecondsSinceEpoch}',
        name: map['name'] as String? ?? '导入词书',
        language: map['language'] as String? ?? fallbackLanguage,
        createdAt: DateTime.now(),
        entries: entries,
      );
    }
    throw const FormatException('不是有效的词书 JSON');
  }
}
