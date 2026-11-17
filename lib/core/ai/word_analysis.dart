import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../language/languages.dart';
import 'ai_client.dart';
import 'ai_settings.dart';

enum WordFormKind { lemma, inflected, independent }

class WordSense {
  const WordSense({required this.pos, required this.meaning});
  final String pos;
  final String meaning;
  Map<String, dynamic> toJson() => {'pos': pos, 'meaning': meaning};
  factory WordSense.fromJson(Map<String, dynamic> json) => WordSense(
    pos: (json['pos'] as String? ?? '').trim(),
    meaning: (json['meaning'] as String? ?? '').trim(),
  );
}

class WordFormInfo {
  const WordFormInfo({required this.label, required this.value});
  final String label;
  final String value;
  Map<String, dynamic> toJson() => {'label': label, 'value': value};
  factory WordFormInfo.fromJson(Map<String, dynamic> json) => WordFormInfo(
    label: (json['label'] as String? ?? '').trim(),
    value: (json['value'] as String? ?? '').trim(),
  );
}

class WordAnalysis {
  const WordAnalysis({
    required this.surface,
    required this.lemma,
    this.kind = WordFormKind.lemma,
    this.surfaceReading,
    this.lemmaReading,
    this.relation = '',
    this.senses = const [],
    this.forms = const [],
    this.inflectionChanged = false,
    this.inflectionSummary = '',
    this.inflectionExplanation = '',
    this.lemmaSentence,
    this.usage = '',
    this.examples = const [],
    this.detailMarkdown = '',
  });

  final String surface;
  final String lemma;
  final WordFormKind kind;
  final String? surfaceReading;
  final String? lemmaReading;
  final String relation;
  final List<WordSense> senses;
  final List<WordFormInfo> forms;
  final bool inflectionChanged;
  final String inflectionSummary;
  final String inflectionExplanation;
  final String? lemmaSentence;
  final String usage;
  final List<String> examples;
  final String detailMarkdown;

  String? get reading => surfaceReading ?? lemmaReading;
  bool get isIndependent => kind == WordFormKind.independent;
  bool get isInflected => kind == WordFormKind.inflected;

  String get meaningSummary => senses
      .map(
        (sense) =>
            sense.pos.isEmpty ? sense.meaning : '${sense.pos} ${sense.meaning}',
      )
      .where((text) => text.trim().isNotEmpty)
      .join('；');

  String get meaning => meaningSummary;

  String? get pos {
    for (final sense in senses) {
      if (sense.pos.trim().isNotEmpty) return sense.pos.trim();
    }
    return null;
  }

  String get inflectionMarkdown {
    if (!inflectionChanged) return '';
    final buffer = StringBuffer('> **变形说明**');
    if (inflectionSummary.trim().isNotEmpty) {
      buffer.write('\n> ${inflectionSummary.trim()}');
    }
    if (inflectionExplanation.trim().isNotEmpty) {
      buffer.write('\n> ${inflectionExplanation.trim()}');
    }
    return buffer.toString();
  }
}

class WordAnalysisCache {
  const WordAnalysisCache();
  static const int _version = 2;
  static const Duration _ttl = Duration(days: 30);

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/word_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _hash(String value) => sha1.convert(utf8.encode(value)).toString();
  String _sentenceHash(String sentence) => _hash(sentence.trim());

  Future<Map<String, dynamic>?> _read(String name) async {
    final dir = await _directory();
    final file = File('${dir.path}/$name.json');
    if (!await file.exists()) return null;
    final stat = await file.stat();
    if (DateTime.now().difference(stat.modified) > _ttl) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return (decoded as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String name, Map<String, dynamic> data) async {
    final dir = await _directory();
    final file = File('${dir.path}/$name.json');
    await file.writeAsString(
      jsonEncode({
        ...data,
        'version': _version,
        'cachedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  String _formKey(String language, String surface) =>
      'form_${_hash('$_version|$language|$surface')}';
  String _dictKey(String language, String lemma) =>
      'dict_${_hash('$_version|$language|$lemma')}';
  String _contextKey(
    String language,
    String surface,
    String lemma,
    String sentence,
  ) =>
      'ctx_${_hash('$_version|$language|$surface|$lemma|${_sentenceHash(sentence)}')}';

  Future<String?> _lemmaFor(String language, String surface) async {
    final form = await _read(_formKey(language, surface));
    return form?['lemma'] as String?;
  }

  Future<WordAnalysis?> load({
    required String language,
    required String surface,
    required String sentence,
    String? lemmaHint,
  }) async {
    final form = await _read(_formKey(language, surface));
    final cachedLemma = form?['lemma'] as String?;
    final lemma = (cachedLemma != null && cachedLemma.trim().isNotEmpty)
        ? cachedLemma.trim()
        : (lemmaHint != null && lemmaHint.trim().isNotEmpty)
        ? lemmaHint.trim()
        : null;
    if (lemma == null || lemma.isEmpty) return null;
    final dict = await _read(_dictKey(language, lemma));
    final context = await _read(
      _contextKey(language, surface, lemma, sentence),
    );
    if (dict == null || context == null) return null;
    return _assemble(surface, lemma, form ?? const {}, dict, context);
  }

  WordAnalysis _assemble(
    String surface,
    String lemma,
    Map<String, dynamic> form,
    Map<String, dynamic> dict,
    Map<String, dynamic> context,
  ) {
    final kindName = form['kind'] as String? ?? 'lemma';
    final kind = WordFormKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => WordFormKind.lemma,
    );
    return WordAnalysis(
      surface: surface,
      lemma: lemma,
      kind: kind,
      surfaceReading: form['surfaceReading'] as String?,
      lemmaReading: dict['lemmaReading'] as String?,
      relation: form['relation'] as String? ?? '',
      senses:
          (dict['senses'] as List?)
              ?.whereType<Map>()
              .map((item) => WordSense.fromJson(item.cast<String, dynamic>()))
              .where((sense) => sense.meaning.isNotEmpty)
              .toList() ??
          const [],
      forms:
          (dict['forms'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => WordFormInfo.fromJson(item.cast<String, dynamic>()),
              )
              .where((item) => item.value.isNotEmpty)
              .toList() ??
          const [],
      inflectionChanged: context['changed'] as bool? ?? false,
      inflectionSummary: context['summary'] as String? ?? '',
      inflectionExplanation: context['explanation'] as String? ?? '',
      lemmaSentence: context['lemmaSentence'] as String?,
      usage: dict['usage'] as String? ?? '',
      examples:
          (dict['examples'] as List?)?.whereType<String>().toList() ?? const [],
      detailMarkdown: dict['detail'] as String? ?? '',
    );
  }

  Future<void> save(
    WordAnalysis analysis,
    String language,
    String sentence,
  ) async {
    await _write(_formKey(language, analysis.surface), {
      'kind': analysis.kind.name,
      'lemma': analysis.lemma,
      'surfaceReading': analysis.surfaceReading,
      'relation': analysis.relation,
    });
    await _write(_dictKey(language, analysis.lemma), {
      'lemmaReading': analysis.lemmaReading,
      'senses': analysis.senses.map((sense) => sense.toJson()).toList(),
      'usage': analysis.usage,
      'examples': analysis.examples,
      'forms': analysis.forms.map((form) => form.toJson()).toList(),
      'detail': analysis.detailMarkdown,
    });
    await _write(
      _contextKey(language, analysis.surface, analysis.lemma, sentence),
      {
        'changed': analysis.inflectionChanged,
        'summary': analysis.inflectionSummary,
        'explanation': analysis.inflectionExplanation,
        'lemmaSentence': analysis.lemmaSentence,
      },
    );
  }

  Future<void> clear({
    required String language,
    required String surface,
    required String sentence,
    String? lemmaHint,
  }) async {
    final dir = await _directory();
    final lemma = (lemmaHint != null && lemmaHint.trim().isNotEmpty)
        ? lemmaHint.trim()
        : await _lemmaFor(language, surface);
    final files = <File>[
      File('${dir.path}/${_formKey(language, surface)}.json'),
    ];
    if (lemma != null && lemma.isNotEmpty) {
      files.add(
        File(
          '${dir.path}/${_contextKey(language, surface, lemma, sentence)}.json',
        ),
      );
    }
    for (final file in files) {
      if (await file.exists()) await file.delete();
    }
  }
}

class WordAnalyzer {
  const WordAnalyzer();
  static const WordAnalysisCache _cache = WordAnalysisCache();

  Future<WordAnalysis> analyze({
    required AiConfig config,
    required String word,
    required String sentence,
    required String language,
    String? lemmaHint,
    bool force = false,
  }) async {
    if (!force) {
      final cached = await _cache.load(
        language: language,
        surface: word,
        sentence: sentence,
        lemmaHint: lemmaHint,
      );
      if (cached != null) return cached;
    } else {
      await _cache.clear(
        language: language,
        surface: word,
        sentence: sentence,
        lemmaHint: lemmaHint,
      );
    }
    final raw = await AiClient(config).chat(
      messages: _messages(word, sentence, language, lemmaHint),
      maxTokens: 2000,
    );
    final analysis = parseWordAnalysis(
      raw,
      surface: word,
      sentence: sentence,
      lemmaHint: lemmaHint,
    );
    await _cache.save(analysis, language, sentence);
    return analysis;
  }

  List<Map<String, String>> _messages(
    String word,
    String sentence,
    String language,
    String? lemmaHint,
  ) {
    return [
      {
        'role': 'system',
        'content':
            'You are a precise multilingual dictionary and grammar tutor. '
            'Answer in Chinese. The target language is '
            '${readingLanguageFor(language).label} ($language). '
            'Return ONLY one JSON object, without markdown fences: '
            '{"classification":"lemma|inflected|independent",'
            '"lemma":"dictionary/base form",'
            '"surfaceReading":"pronunciation of the word as it appears",'
            '"lemmaReading":"pronunciation of the lemma",'
            '"relation":"for inflected or independent words, explain the relation in Chinese; empty for a plain lemma",'
            '"senses":[{"pos":"n.","meaning":"建筑物"}],'
            '"usage":"how the lemma is used, in Markdown",'
            '"examples":["short example"],'
            '"forms":[{"label":"过去式","value":"built"}],'
            '"inflection":{"changed":true,"summary":"surface -> lemma",'
            '"explanation":"what changed and why"},'
            '"lemmaSentence":"the original sentence with the target word replaced by its lemma",'
            '"detail":"Markdown nuance and extra examples"}. '
            'Decide classification first. Use "lemma" when the word is already '
            'a dictionary form. Use "inflected" for grammatical forms such as '
            'tense, number, case or politeness. Use "independent" when the '
            'surface has become its own lexical item, for example building as '
            'a noun or interested as an adjective; then lemma is the surface '
            'itself and relation explains its origin. '
            'senses must bind part of speech to meaning and list different '
            'parts of speech separately. '
            'forms must include every existing form: past tense, past '
            'participle, third-person singular, plural, present participle, '
            'comparative, superlative, adjective and noun derivations. '
            'For English readings use IPA between slashes. For Japanese use '
            'kana plus pitch accent, for example かぐや [1]. '
            'Do not wrap the JSON in code fences.',
      },
      {
        'role': 'user',
        'content': jsonEncode({
          'word': word,
          'sentence': sentence,
          if (lemmaHint != null && lemmaHint.isNotEmpty) 'lemmaHint': lemmaHint,
        }),
      },
    ];
  }
}

const String _fence = '\u0060\u0060\u0060';

WordAnalysis parseWordAnalysis(
  String raw, {
  required String surface,
  required String sentence,
  String? lemmaHint,
}) {
  var text = raw.trim();
  if (text.startsWith(_fence)) {
    final newline = text.indexOf('\n');
    if (newline >= 0) text = text.substring(newline + 1);
    if (text.endsWith(_fence)) text = text.substring(0, text.length - 3);
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return _fallback(raw, surface, sentence, lemmaHint);
  }
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! Map) return _fallback(raw, surface, sentence, lemmaHint);
    final map = decoded.cast<String, dynamic>();
    final rawLemma = (map['lemma'] as String?)?.trim();
    final kindName = (map['classification'] as String?)?.toLowerCase();
    var kind = switch (kindName) {
      'independent' => WordFormKind.independent,
      'inflected' => WordFormKind.inflected,
      'lemma' => WordFormKind.lemma,
      _ =>
        (rawLemma != null && rawLemma.isNotEmpty && rawLemma != surface)
            ? WordFormKind.inflected
            : WordFormKind.lemma,
    };
    var lemma = (rawLemma == null || rawLemma.isEmpty)
        ? (lemmaHint ?? surface)
        : rawLemma;
    if (kind == WordFormKind.independent) lemma = surface;
    if (kind == WordFormKind.lemma && lemma != surface) {
      kind = WordFormKind.inflected;
    }
    final senses = _parseSenses(map);
    final forms = _parseForms(map);
    final inflection = (map['inflection'] as Map?)?.cast<String, dynamic>();
    final changed = kind == WordFormKind.inflected;
    final examples =
        (map['examples'] as List?)?.whereType<String>().toList() ?? const [];
    return WordAnalysis(
      surface: surface,
      lemma: lemma,
      kind: kind,
      surfaceReading:
          (map['surfaceReading'] as String?)?.trim() ??
          (map['reading'] as String?)?.trim(),
      lemmaReading: (map['lemmaReading'] as String?)?.trim(),
      relation: (map['relation'] as String? ?? '').trim(),
      senses: senses.isEmpty && (map['meaning'] as String? ?? '').isNotEmpty
          ? [
              WordSense(
                pos: (map['pos'] as String? ?? '').trim(),
                meaning: (map['meaning'] as String).trim(),
              ),
            ]
          : senses,
      forms: forms,
      inflectionChanged: changed,
      inflectionSummary: changed
          ? (inflection?['summary'] as String? ?? '$surface → $lemma').trim()
          : '',
      inflectionExplanation: changed
          ? (inflection?['explanation'] as String? ?? '').trim()
          : '',
      lemmaSentence: (map['lemmaSentence'] as String?)?.trim(),
      usage: (map['usage'] as String? ?? '').trim(),
      examples: examples,
      detailMarkdown: (map['detail'] as String? ?? '').trim(),
    );
  } catch (_) {
    return _fallback(raw, surface, sentence, lemmaHint);
  }
}

List<WordSense> _parseSenses(Map<String, dynamic> map) {
  final raw = map['senses'];
  final senses = <WordSense>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) {
        final sense = WordSense.fromJson(item.cast<String, dynamic>());
        if (sense.meaning.isNotEmpty) senses.add(sense);
      } else if (item is String && item.trim().isNotEmpty) {
        senses.add(WordSense(pos: '', meaning: item.trim()));
      }
    }
  }
  return senses;
}

List<WordFormInfo> _parseForms(Map<String, dynamic> map) {
  final raw = map['forms'];
  final forms = <WordFormInfo>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) {
        final form = WordFormInfo.fromJson(item.cast<String, dynamic>());
        if (form.value.isNotEmpty) forms.add(form);
      } else if (item is String && item.trim().isNotEmpty) {
        forms.add(WordFormInfo(label: '', value: item.trim()));
      }
    }
  }
  return forms;
}

WordAnalysis _fallback(
  String raw,
  String surface,
  String sentence,
  String? lemmaHint,
) {
  final lemma = (lemmaHint != null && lemmaHint.trim().isNotEmpty)
      ? lemmaHint.trim()
      : surface;
  final changed = lemma != surface;
  return WordAnalysis(
    surface: surface,
    lemma: lemma,
    kind: changed ? WordFormKind.inflected : WordFormKind.lemma,
    inflectionChanged: changed,
    inflectionSummary: changed ? '$surface → $lemma' : '',
    lemmaSentence: _replaceWord(sentence, surface, lemma),
    detailMarkdown: raw.trim(),
  );
}

String _replaceWord(String sentence, String surface, String lemma) {
  if (surface == lemma) return sentence;
  final index = sentence.indexOf(surface);
  if (index < 0) return sentence;
  return sentence.replaceRange(index, index + surface.length, lemma);
}
