import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/ai_client.dart';
import '../ai/ai_settings.dart';
import '../ai/chunk_cache.dart';
import 'reading_book.dart';

class ReadingTranslationStore {
  const ReadingTranslationStore();

  Future<File> _file(String bookId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/reading_translations');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$bookId.json');
  }

  String keyFor(String language, String target, String paragraph) {
    return sha1
        .convert(utf8.encode('$language|$target|$paragraph'))
        .toString();
  }

  Future<Map<String, String>> load(String bookId) async {
    final file = await _file(bookId);
    if (!await file.exists()) {
      return {};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      // Ignore broken translation caches.
    }
    return {};
  }

  Future<void> save(String bookId, Map<String, String> translations) async {
    final file = await _file(bookId);
    await file.writeAsString(jsonEncode(translations));
  }
}

class ReadingTranslationController extends ChangeNotifier {
  ReadingTranslationController(this.book, this.config);

  final ReadingBook book;
  final AiConfig config;
  final ReadingTranslationStore _store = const ReadingTranslationStore();
  final AiChunkCache _cache = const AiChunkCache();

  final Map<String, String> _translations = {};
  bool _running = false;
  int _completed = 0;
  int _total = 0;
  int _failed = 0;
  String? _error;

  bool get running => _running;
  int get completed => _completed;
  int get total => _total;
  int get failed => _failed;
  String? get error => _error;

  List<String> get paragraphs => book.content
      .split(RegExp(r'\n+'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();

  String? translationFor(String paragraph) => _translations[
    _store.keyFor(book.language, book.translationTarget, paragraph)
  ];

  bool get isComplete => _total > 0 && _translations.length >= _total;

  Future<void> start() async {
    if (_running) {
      return;
    }
    if (!config.isConfigured) {
      _error = '尚未配置 AI 接口';
      notifyListeners();
      return;
    }
    _running = true;
    _error = null;
    notifyListeners();
    _translations.addAll(await _store.load(book.id));
    final allParagraphs = paragraphs;
    _total = allParagraphs.length;
    final pending = <({int index, String text})>[];
    for (var i = 0; i < allParagraphs.length; i++) {
      final key = _store.keyFor(
        book.language,
        book.translationTarget,
        allParagraphs[i],
      );
      if (!_translations.containsKey(key)) {
        pending.add((index: i, text: allParagraphs[i]));
      }
    }
    _completed = _total - pending.length;
    notifyListeners();
    if (pending.isEmpty) {
      _running = false;
      notifyListeners();
      return;
    }
    final chunks = <List<({int index, String text})>>[];
    var current = <({int index, String text})>[];
    var chars = 0;
    for (final paragraph in pending) {
      if (current.isNotEmpty && (current.length >= 6 || chars + paragraph.text.length > 1000)) {
        chunks.add(current);
        current = [];
        chars = 0;
      }
      current.add(paragraph);
      chars += paragraph.text.length;
    }
    if (current.isNotEmpty) {
      chunks.add(current);
    }
    final client = AiClient(config);
    await runWithConcurrency(chunks, 3, (chunk, _) async {
      try {
        final translated = await _translateChunk(client, chunk);
        for (final entry in translated.entries) {
          _translations[_store.keyFor(
            book.language,
            book.translationTarget,
            entry.key,
          )] = entry.value;
        }
        _completed += chunk.length;
        await _store.save(book.id, _translations);
      } catch (_) {
        _failed++;
      }
      notifyListeners();
    });
    _running = false;
    await _store.save(book.id, _translations);
    notifyListeners();
  }

  Future<Map<String, String>> _translateChunk(
    AiClient client,
    List<({int index, String text})> chunk,
  ) async {
    final payload = jsonEncode(
      chunk.map((entry) => {'index': entry.index, 'text': entry.text}).toList(),
    );
    final cacheKey = _cache.keyFor(
      'reading-translation|v1|${book.translationTarget}',
      book.language,
      payload,
    );
    final cached = await _cache.read(cacheKey);
    if (cached != null) {
      return _parseTranslations(cached, chunk);
    }
    final raw = await client.chat(
      messages: [
        {
          'role': 'system',
          'content':
              'You are a professional translator. Translate every numbered paragraph '
              'into Chinese. Return ONLY JSON: {"translations":[{"index":0,"text":"..."}]}. '
              'Keep the same indices. Do not add commentary. Source language: '
              '${readingLanguageFor(book.language).label}.',
        },
        {'role': 'user', 'content': payload},
      ],
      maxTokens: 2200,
    );
    await _cache.write(cacheKey, raw);
    return _parseTranslations(raw, chunk);
  }

  Map<String, String> _parseTranslations(
    String raw,
    List<({int index, String text})> chunk,
  ) {
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
      throw const FormatException('翻译返回内容不是 JSON');
    }
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! Map || decoded['translations'] is! List) {
      throw const FormatException('翻译 JSON 缺少 translations');
    }
    final byIndex = <int, String>{};
    for (final item in decoded['translations'] as List) {
      if (item is! Map) {
        continue;
      }
      final index = item['index'];
      final translated = (item['text'] as String?)?.trim();
      if (index is num && translated != null && translated.isNotEmpty) {
        byIndex[index.toInt()] = translated;
      }
    }
    final result = <String, String>{};
    for (final entry in chunk) {
      final translated = byIndex[entry.index];
      if (translated != null) {
        result[entry.text] = translated;
      }
    }
    if (result.isEmpty) {
      throw const FormatException('翻译 JSON 中没有有效段落');
    }
    return result;
  }
}

class ReadingTranslationManager {
  ReadingTranslationManager._();

  static final ReadingTranslationManager instance = ReadingTranslationManager._();

  final Map<String, ReadingTranslationController> _controllers = {};

  ReadingTranslationController controllerFor(ReadingBook book, AiConfig config) {
    final existing = _controllers[book.id];
    if (existing != null) {
      return existing;
    }
    final controller = ReadingTranslationController(book, config);
    _controllers[book.id] = controller;
    unawaited(controller.start());
    return controller;
  }

  ReadingTranslationController? existingFor(String bookId) => _controllers[bookId];
}
