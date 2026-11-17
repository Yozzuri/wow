import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/word_analysis.dart';
import '../models/content_document.dart';
import '../text/normalize.dart';

enum ReviewGrade { forgot, hard, good, easy }

/// Ebbinghaus-style review ladder used for learned words.
const List<int> ebbinghausIntervals = [1, 2, 4, 7, 15, 30, 60, 120, 240, 365];

/// Returns the interval and the new stage after grading a review.
({int stage, int intervalDays}) ebbinghausSchedule(
  int stage,
  ReviewGrade grade,
) {
  final last = ebbinghausIntervals.length - 1;
  switch (grade) {
    case ReviewGrade.forgot:
      return (stage: 0, intervalDays: ebbinghausIntervals.first);
    case ReviewGrade.hard:
      final next = (stage - 1).clamp(0, last);
      return (stage: next, intervalDays: ebbinghausIntervals[next]);
    case ReviewGrade.good:
      final next = (stage + 1).clamp(0, last);
      return (stage: next, intervalDays: ebbinghausIntervals[stage]);
    case ReviewGrade.easy:
      final next = (stage + 2).clamp(0, last);
      return (stage: next, intervalDays: ebbinghausIntervals[next]);
  }
}

class VocabEntry {
  const VocabEntry({
    required this.key,
    required this.word,
    required this.lemma,
    required this.meaning,
    required this.sentence,
    required this.sourceTitle,
    required this.createdAt,
    required this.dueAt,
    this.pos,
    this.translation,
    this.reading,
    this.inflection,
    this.lemmaSentence,
    this.language = 'en',
    this.intervalDays = 0,
    this.ease = 2.5,
    this.reps = 0,
    this.lapses = 0,
    this.learned = false,
    this.learnedAt,
    this.lastReviewedAt,
    this.learnState = 0,
    this.senses = const [],
    this.forms = const [],
    this.usage = '',
    this.examples = const [],
    this.surfaceReading,
    this.lemmaReading,
    this.relation = '',
  });

  final String key;
  final String word;
  final String lemma;
  final String? pos;
  final String? reading;
  final String? inflection;
  final String? lemmaSentence;
  final String meaning;
  final String sentence;
  final String? translation;
  final String sourceTitle;
  final String language;
  final DateTime createdAt;
  final DateTime dueAt;
  final int intervalDays;
  final double ease;
  final int reps;
  final int lapses;
  final bool learned;
  final DateTime? learnedAt;
  final DateTime? lastReviewedAt;

  /// In-session learning progress: 0 familiarity, 1 meaning,
  /// 2 word choice, 3 spelling. Persisted so quitting keeps progress.
  final int learnState;
  final List<WordSense> senses;
  final List<WordFormInfo> forms;
  final String usage;
  final List<String> examples;
  final String? surfaceReading;
  final String? lemmaReading;
  final String relation;

  List<WordSense> get allSenses {
    if (senses.isNotEmpty) {
      return senses;
    }
    if (meaning.trim().isEmpty) {
      return const [];
    }
    return [WordSense(pos: pos ?? '', meaning: meaning)];
  }

  String get displayMeaning => allSenses
      .map(
        (sense) => sense.pos.isEmpty
            ? sense.meaning
            : '${sense.pos} ${sense.meaning}',
      )
      .where((value) => value.trim().isNotEmpty)
      .join('；');

  String? get displayPos {
    for (final sense in allSenses) {
      if (sense.pos.trim().isNotEmpty) {
        return sense.pos.trim();
      }
    }
    return pos;
  }

  bool get isNew => !learned;
  bool get isDue => !dueAt.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
    'key': key,
    'word': word,
    'lemma': lemma,
    'pos': pos,
    'reading': reading,
    'inflection': inflection,
    'lemmaSentence': lemmaSentence,
    'meaning': meaning,
    'sentence': sentence,
    'translation': translation,
    'sourceTitle': sourceTitle,
    'language': language,
    'createdAt': createdAt.toIso8601String(),
    'dueAt': dueAt.toIso8601String(),
    'intervalDays': intervalDays,
    'ease': ease,
    'reps': reps,
    'lapses': lapses,
    'learned': learned,
    if (learnedAt != null) 'learnedAt': learnedAt!.toIso8601String(),
    if (lastReviewedAt != null)
      'lastReviewedAt': lastReviewedAt!.toIso8601String(),
    'learnState': learnState,
    if (senses.isNotEmpty)
      'senses': senses.map((sense) => sense.toJson()).toList(),
    if (forms.isNotEmpty) 'forms': forms.map((form) => form.toJson()).toList(),
    if (usage.isNotEmpty) 'usage': usage,
    if (examples.isNotEmpty) 'examples': examples,
    if (surfaceReading != null) 'surfaceReading': surfaceReading,
    if (lemmaReading != null) 'lemmaReading': lemmaReading,
    if (relation.isNotEmpty) 'relation': relation,
  };

  factory VocabEntry.fromJson(Map<String, dynamic> json) => VocabEntry(
    key: json['key'] as String? ?? '',
    word: json['word'] as String? ?? '',
    lemma: json['lemma'] as String? ?? '',
    pos: json['pos'] as String?,
    reading: json['reading'] as String?,
    inflection: json['inflection'] as String?,
    lemmaSentence: json['lemmaSentence'] as String?,
    meaning: json['meaning'] as String? ?? '',
    sentence: json['sentence'] as String? ?? '',
    translation: json['translation'] as String?,
    sourceTitle: json['sourceTitle'] as String? ?? '',
    language: json['language'] as String? ?? 'en',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    dueAt: DateTime.tryParse(json['dueAt'] as String? ?? '') ?? DateTime.now(),
    intervalDays: json['intervalDays'] as int? ?? 0,
    ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
    reps: json['reps'] as int? ?? 0,
    lapses: json['lapses'] as int? ?? 0,
    learned:
        json['learned'] as bool? ??
        ((json['reps'] as int? ?? 0) > 0 ||
            (json['intervalDays'] as int? ?? 0) > 0),
    learnedAt: DateTime.tryParse(json['learnedAt'] as String? ?? ''),
    lastReviewedAt: DateTime.tryParse(json['lastReviewedAt'] as String? ?? ''),
    learnState: (json['learnState'] as int? ?? 0).clamp(0, 3),
    senses: (json['senses'] as List?)
            ?.whereType<Map>()
            .map((item) => WordSense.fromJson(item.cast<String, dynamic>()))
            .where((sense) => sense.meaning.isNotEmpty)
            .toList() ??
        const [],
    forms: (json['forms'] as List?)
            ?.whereType<Map>()
            .map((item) => WordFormInfo.fromJson(item.cast<String, dynamic>()))
            .where((form) => form.value.isNotEmpty)
            .toList() ??
        const [],
    usage: json['usage'] as String? ?? '',
    examples: (json['examples'] as List?)?.whereType<String>().toList() ?? const [],
    surfaceReading: json['surfaceReading'] as String?,
    lemmaReading: json['lemmaReading'] as String?,
    relation: json['relation'] as String? ?? '',
  );

  VocabEntry copyWith({
    DateTime? dueAt,
    int? intervalDays,
    double? ease,
    int? reps,
    int? lapses,
    bool? learned,
    DateTime? learnedAt,
    DateTime? lastReviewedAt,
    int? learnState,
  }) => VocabEntry(
    key: key,
    word: word,
    lemma: lemma,
    meaning: meaning,
    sentence: sentence,
    sourceTitle: sourceTitle,
    createdAt: createdAt,
    dueAt: dueAt ?? this.dueAt,
    pos: pos,
    translation: translation,
    reading: reading,
    inflection: inflection,
    lemmaSentence: lemmaSentence,
    language: language,
    intervalDays: intervalDays ?? this.intervalDays,
    ease: ease ?? this.ease,
    reps: reps ?? this.reps,
    lapses: lapses ?? this.lapses,
    learned: learned ?? this.learned,
    learnedAt: learnedAt ?? this.learnedAt,
    lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
    learnState: learnState ?? this.learnState,
    senses: senses,
    forms: forms,
    usage: usage,
    examples: examples,
    surfaceReading: surfaceReading,
    lemmaReading: lemmaReading,
    relation: relation,
  );

  VocabEntry copyWithAnalysis(WordAnalysis analysis) => VocabEntry(
    key: key,
    word: word,
    lemma: analysis.lemma,
    pos: analysis.pos,
    meaning: analysis.meaningSummary,
    sentence: sentence,
    translation: translation,
    reading: analysis.reading,
    inflection: analysis.isInflected
        ? analysis.inflectionMarkdown
        : (relation.isNotEmpty ? relation : inflection),
    lemmaSentence: analysis.lemmaSentence,
    sourceTitle: sourceTitle,
    language: language,
    createdAt: createdAt,
    dueAt: dueAt,
    intervalDays: intervalDays,
    ease: ease,
    reps: reps,
    lapses: lapses,
    learned: learned,
    learnedAt: learnedAt,
    lastReviewedAt: lastReviewedAt,
    learnState: learnState,
    senses: analysis.senses,
    forms: analysis.forms,
    usage: analysis.usage,
    examples: analysis.examples,
    surfaceReading: analysis.surfaceReading,
    lemmaReading: analysis.lemmaReading,
    relation: analysis.relation,
  );
}

class VocabStore {
  const VocabStore();

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/vocab');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/entries.json');
  }

  Future<List<VocabEntry>> load() async {
    final file = await _file();
    if (!await file.exists()) {
      return [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map((e) => VocabEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<VocabEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  String _keyFor(String lemma, String language) => sha1
      .convert(utf8.encode('${normalizeForMatch(lemma)}|$language'))
      .toString();

  Future<bool> addToken({
    required String word,
    String? lemma,
    String? pos,
    String? meaning,
    required String sentence,
    String? translation,
    String? reading,
    String? inflection,
    String? lemmaSentence,
    required String sourceTitle,
    String language = 'en',
    List<WordSense> senses = const [],
    List<WordFormInfo> forms = const [],
    String usage = '',
    List<String> examples = const [],
    String? surfaceReading,
    String? lemmaReading,
    String relation = '',
  }) async {
    final resolvedLemma = (lemma ?? word).trim();
    if (resolvedLemma.isEmpty) {
      return false;
    }
    final entries = await load();
    final key = _keyFor(resolvedLemma, language);
    if (entries.any((entry) => entry.key == key)) {
      return false;
    }
    final now = DateTime.now();
    entries.add(
      VocabEntry(
        key: key,
        word: word,
        lemma: resolvedLemma,
        pos: pos,
        meaning: meaning ?? '',
        sentence: sentence,
        translation: translation,
        reading: reading,
        inflection: inflection,
        lemmaSentence: lemmaSentence,
        sourceTitle: sourceTitle,
        language: language,
        createdAt: now,
        dueAt: now,
        senses: senses,
        forms: forms,
        usage: usage,
        examples: examples,
        surfaceReading: surfaceReading,
        lemmaReading: lemmaReading,
        relation: relation,
      ),
    );
    await _save(entries);
    return true;
  }

  Future<int> addFromDocument(ContentDocument document) async {
    final entries = await load();
    final existing = entries.map((entry) => entry.key).toSet();
    final now = DateTime.now();
    var added = 0;
    for (final segment in document.segments) {
      for (final token in segment.tokens) {
        final lemma = (token.lemma ?? token.surface).trim();
        if (lemma.isEmpty) {
          continue;
        }
        final key = _keyFor(lemma, document.meta.language);
        if (existing.contains(key)) {
          continue;
        }
        existing.add(key);
        entries.add(
          VocabEntry(
            key: key,
            word: token.surface,
            lemma: lemma,
            pos: token.pos,
            meaning: token.meaning ?? '',
            sentence: segment.text,
            translation: segment.translation,
            sourceTitle: document.meta.title,
            language: document.meta.language,
            createdAt: now,
            dueAt: now,
            senses: (token.meaning ?? '').trim().isEmpty
                ? const []
                : [
                    WordSense(
                      pos: token.pos ?? '',
                      meaning: token.meaning!.trim(),
                    ),
                  ],
          ),
        );
        added++;
      }
    }
    if (added > 0) {
      await _save(entries);
    }
    return added;
  }

  /// Marks a new word as learned. Its first review is due tomorrow.
  Future<VocabEntry?> markLearned(VocabEntry entry) async {
    final entries = await load();
    final index = entries.indexWhere((item) => item.key == entry.key);
    if (index < 0) {
      return null;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final updated = entry.copyWith(
      learned: true,
      learnedAt: now,
      dueAt: today.add(const Duration(days: 1)),
      intervalDays: 0,
      reps: 0,
      learnState: 0,
    );
    entries[index] = updated;
    await _save(entries);
    return updated;
  }

  Future<VocabEntry?> updateLearnState(VocabEntry entry, int state) async {
    final entries = await load();
    final index = entries.indexWhere((item) => item.key == entry.key);
    if (index < 0) {
      return null;
    }
    final updated = entry.copyWith(learnState: state.clamp(0, 3));
    entries[index] = updated;
    await _save(entries);
    return updated;
  }

  Future<VocabEntry?> updateAnalysis(
    VocabEntry entry,
    WordAnalysis analysis,
  ) async {
    final entries = await load();
    final index = entries.indexWhere((item) => item.key == entry.key);
    if (index < 0) {
      return null;
    }
    final updated = entry.copyWithAnalysis(analysis);
    entries[index] = updated;
    await _save(entries);
    return updated;
  }

  Future<void> remove(VocabEntry entry) async {
    final entries = await load();
    entries.removeWhere((item) => item.key == entry.key);
    await _save(entries);
  }

  Future<List<VocabEntry>> review(VocabEntry entry, ReviewGrade grade) async {
    final entries = await load();
    final index = entries.indexWhere((item) => item.key == entry.key);
    if (index < 0) {
      return entries;
    }
    final schedule = ebbinghausSchedule(entry.reps, grade);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final updated = entry.copyWith(
      learned: true,
      learnedAt: entry.learnedAt ?? now,
      lastReviewedAt: now,
      intervalDays: schedule.intervalDays,
      reps: schedule.stage,
      lapses: grade == ReviewGrade.forgot ? entry.lapses + 1 : entry.lapses,
      dueAt: today.add(Duration(days: schedule.intervalDays)),
      learnState: 0,
    );
    entries[index] = updated;
    await _save(entries);
    return entries;
  }
}

final vocabStoreProvider = Provider<VocabStore>((ref) => const VocabStore());
final vocabVersionProvider = StateProvider<int>((ref) => 0);
