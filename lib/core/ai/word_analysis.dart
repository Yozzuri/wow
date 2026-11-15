import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_client.dart';
import 'ai_settings.dart';
import '../language/languages.dart';

class WordAnalysis {
  const WordAnalysis({
    required this.surface,
    required this.lemma,
    this.reading,
    this.pos,
    this.inflectionChanged = false,
    this.inflectionSummary = '',
    this.inflectionExplanation = '',
    this.lemmaSentence,
    this.usage = '',
    this.meaning = '',
    this.examples = const [],
    this.detailMarkdown = '',
  });

  final String surface;
  final String lemma;
  final String? reading;
  final String? pos;
  final bool inflectionChanged;
  final String inflectionSummary;
  final String inflectionExplanation;
  final String? lemmaSentence;
  final String usage;
  final String meaning;
  final List<String> examples;
  final String detailMarkdown;

  String get inflectionMarkdown {
    if (!inflectionChanged) {
      return '';
    }
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

  static const int _version = 1;
  static const Duration _ttl = Duration(days: 30);

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/word_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _hash(String value) => sha1.convert(utf8.encode(value)).toString();

  String _sentenceHash(String sentence) => _hash(sentence.trim());

  Future<Map<String, dynamic>?> _read(String name) async {
    final dir = await _directory();
    final file = File('${dir.path}/$name.json');
    if (!await file.exists()) {
      return null;
    }
    final stat = await file.stat();
    if (DateTime.now().difference(stat.modified) > _ttl) {
      return null;
    }
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
      jsonEncode({...data, 'version': _version, 'cachedAt': DateTime.now().toIso8601String()}),
    );
  }

  String _dictKey(String language, String lemma) =>
      'dict_${_hash('$_version|$language|$lemma')}';

  String _formKey(String language, String surface) =>
      'form_${_hash('$_version|$language|$surface')}';

  String _contextKey(
    String language,
    String surface,
    String lemma,
    String sentence,
  ) => 'ctx_${_hash('$_version|$language|$surface|$lemma|${_sentenceHash(sentence)}')}';

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
    final lemma = (lemmaHint != null && lemmaHint.trim().isNotEmpty)
        ? lemmaHint.trim()
        : await _lemmaFor(language, surface);
    if (lemma == null || lemma.isEmpty) {
      return null;
    }
    final dict = await _read(_dictKey(language, lemma));
    final context = await _read(
      _contextKey(language, surface, lemma, sentence),
    );
    if (dict == null || context == null) {
      return null;
    }
    return _assemble(surface, lemma, dict, context);
  }

  WordAnalysis _assemble(
    String surface,
    String lemma,
    Map<String, dynamic> dict,
    Map<String, dynamic> context,
  ) {
    return WordAnalysis(
      surface: surface,
      lemma: lemma,
      reading: (context['reading'] as String?) ?? (dict['reading'] as String?),
      pos: dict['pos'] as String?,
      inflectionChanged: context['changed'] as bool? ?? false,
      inflectionSummary: context['summary'] as String? ?? '',
      inflectionExplanation: context['explanation'] as String? ?? '',
      lemmaSentence: context['lemmaSentence'] as String?,
      usage: dict['usage'] as String? ?? '',
      meaning: context['meaning'] as String? ?? '',
      examples:
          (dict['examples'] as List?)?.whereType<String>().toList() ?? const [],
      detailMarkdown: dict['detail'] as String? ?? '',
    );
  }

  Future<void> save(WordAnalysis analysis, String language, String sentence) async {
    await _write(_formKey(language, analysis.surface), {
      'lemma': analysis.lemma,
    });
    await _write(_dictKey(language, analysis.lemma), {
      'lemma': analysis.lemma,
      'reading': analysis.reading,
      'pos': analysis.pos,
      'usage': analysis.usage,
      'examples': analysis.examples,
      'detail': analysis.detailMarkdown,
    });
    await _write(
      _contextKey(language, analysis.surface, analysis.lemma, sentence),
      {
        'reading': analysis.reading,
        'changed': analysis.inflectionChanged,
        'summary': analysis.inflectionSummary,
        'explanation': analysis.inflectionExplanation,
        'lemmaSentence': analysis.lemmaSentence,
        'meaning': analysis.meaning,
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
      if (await file.exists()) {
        await file.delete();
      }
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
      if (cached != null) {
        return cached;
      }
    } else {
      await _cache.clear(
        language: language,
        surface: word,
        sentence: sentence,
        lemmaHint: lemmaHint,
      );
    }
    final client = AiClient(config);
    final raw = await client.chat(
      messages: _messages(word, sentence, language, lemmaHint),
      maxTokens: 1400,
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
            'Return ONLY one JSON object, without markdown fences, with this shape: '
            '{"lemma":"dictionary/base form","reading":"pronunciation or reading",'
            '"pos":"part of speech","inflection":{"changed":true,'
            '"summary":"surface -> lemma","explanation":"what inflection was applied and why"},'
            '"lemmaSentence":"the original sentence with the target word replaced by its lemma, '
            'adjusted to stay grammatical","usage":"how the lemma is used",'
            '"meaning":"meaning in the original sentence","examples":["short example"],'
            '"detail":"Markdown explanation with nuance and extra examples"}. '
            'If the word is already a dictionary form, set changed=false, summary="" and '
            'explanation="". Do not wrap JSON in code fences.',
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

WordAnalysis parseWordAnalysis(
  String raw, {
  required String surface,
  required String sentence,
  String? lemmaHint,
}) {
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
    return _fallback(raw, surface, sentence, lemmaHint);
  }
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! Map) {
      return _fallback(raw, surface, sentence, lemmaHint);
    }
    final map = decoded.cast<String, dynamic>();
    final lemma = (map['lemma'] as String?)?.trim();
    final inflection = (map['inflection'] as Map?)?.cast<String, dynamic>();
    final examples =
        (map['examples'] as List?)?.whereType<String>().toList() ?? const [];
    final detail = (map['detail'] as String? ?? '').trim();
    final resolvedLemma = (lemma == null || lemma.isEmpty)
        ? (lemmaHint ?? surface)
        : lemma;
    final changed = inflection?['changed'] as bool? ??
        (resolvedLemma != surface);
    return WordAnalysis(
      surface: surface,
      lemma: resolvedLemma,
      reading: (map['reading'] as String?)?.trim(),
      pos: (map['pos'] as String?)?.trim(),
      inflectionChanged: changed,
      inflectionSummary: inflection?['summary'] as String? ?? '',
      inflectionExplanation: inflection?['explanation'] as String? ?? '',
      lemmaSentence: (map['lemmaSentence'] as String?)?.trim(),
      usage: (map['usage'] as String? ?? '').trim(),
      meaning: (map['meaning'] as String? ?? '').trim(),
      examples: examples,
      detailMarkdown: detail,
    );
  } catch (_) {
    return _fallback(raw, surface, sentence, lemmaHint);
  }
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
  return WordAnalysis(
    surface: surface,
    lemma: lemma,
    inflectionChanged: lemma != surface,
    inflectionSummary: lemma != surface ? '$surface → $lemma' : '',
    lemmaSentence: _replaceWord(sentence, surface, lemma),
    detailMarkdown: raw.trim(),
  );
}

String _replaceWord(String sentence, String surface, String lemma) {
  if (surface == lemma) {
    return sentence;
  }
  final index = sentence.indexOf(surface);
  if (index < 0) {
    return sentence;
  }
  return sentence.replaceRange(index, index + surface.length, lemma);
}
