import 'dart:convert';

import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';
import '../../core/ai/chunk_cache.dart';
import '../../core/reading/chapter_detector.dart';
import '../../core/reading/reading_book.dart';
import '../../core/reading/reading_translation.dart';

class _ImportItem {
  _ImportItem({
    required this.name,
    required this.content,
    required this.language,
  });

  final String name;
  final String content;
  String language;

  String get title {
    final index = name.lastIndexOf('.');
    return index > 0 ? name.substring(0, index) : name;
  }
}

class ReadingImportScreen extends ConsumerStatefulWidget {
  const ReadingImportScreen({super.key});

  @override
  ConsumerState<ReadingImportScreen> createState() =>
      _ReadingImportScreenState();
}

class _ReadingImportScreenState extends ConsumerState<ReadingImportScreen> {
  static const _store = ReadingStore();

  final List<_ImportItem> _items = [];
  bool _merge = false;
  bool _importing = false;
  bool _preprocess = true;
  String? _progress;
  ChapterFallback _fallback = ChapterFallback.single;

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub', 'md'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) {
      return;
    }
    for (final file in result.files) {
      try {
        final bytes = file.bytes;
        if (bytes == null) {
          continue;
        }
        final isEpub = file.name.toLowerCase().endsWith('.epub');
        final content = isEpub
            ? await _extractEpub(bytes)
            : const Utf8Decoder(allowMalformed: true).convert(bytes);
        if (content.trim().isEmpty) {
          continue;
        }
        _items.add(
          _ImportItem(
            name: file.name,
            content: content,
            language: detectLanguage(content),
          ),
        );
      } catch (_) {
        // Skip unreadable files.
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<String> _extractEpub(List<int> bytes) async {
    final book = await EpubReader.readBook(bytes);
    final parts = <String>[];
    void collect(EpubChapter chapter) {
      final html = chapter.HtmlContent;
      if (html != null && html.trim().isNotEmpty) {
        final text = _stripHtml(html);
        if (text.isNotEmpty) {
          parts.add(text);
        }
      }
      for (final sub in chapter.SubChapters ?? <EpubChapter>[]) {
        collect(sub);
      }
    }

    for (final chapter in book.Chapters ?? <EpubChapter>[]) {
      collect(chapter);
    }
    return parts.join('\n\n');
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(
          RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
        .trim();
  }

  bool get _mixedLanguages =>
      _items.map((item) => item.language).toSet().length > 1;

  Future<void> _import() async {
    if (_items.isEmpty || _importing) {
      return;
    }
    if (_merge && _mixedLanguages) {
      return;
    }
    setState(() => _importing = true);
    final saved = <ReadingBook>[];
    try {
      final config = await ref.read(aiConfigProvider.future);
      final cache = const AiChunkCache();
      final contents = <String>[];
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (mounted) {
          setState(() => _progress = '准备文件 ${i + 1}/${_items.length}…');
        }
        if (_preprocess &&
            !readingLanguageFor(item.language).usesSpaces &&
            config.isConfigured) {
          contents.add(
            await _preprocessContent(item.content, item.language, config, cache),
          );
        } else {
          contents.add(item.content);
        }
      }
      if (_merge) {
        final buffer = StringBuffer();
        final chapters = <ReadingChapter>[];
        var start = 0;
        for (var i = 0; i < _items.length; i++) {
          final item = _items[i];
          buffer.write(contents[i]);
          final end = buffer.length;
          chapters.add(ReadingChapter(title: item.title, start: start, end: end));
          start = end + 2;
          buffer.write('\n\n');
        }
        final book = await _store.save(
          ReadingBook(
            id: '',
            title: _items.first.title,
            language: _items.first.language,
            content: buffer.toString().trim(),
            createdAt: DateTime.now(),
            chapters: chapters,
            sourceFiles: _items.map((item) => item.name).toList(),
          ),
        );
        saved.add(book);
      } else {
        for (var i = 0; i < _items.length; i++) {
          final item = _items[i];
          final content = contents[i];
          final chapters = detectChapters(
            content,
            fallback: _fallback,
          );
          final book = await _store.save(
            ReadingBook(
              id: '',
              title: item.title,
              language: item.language,
              content: content,
              createdAt: DateTime.now(),
              chapters: chapters,
              sourceFiles: [item.name],
            ),
          );
          saved.add(book);
        }
      }
      if (config.isConfigured) {
        for (final book in saved) {
          ReadingTranslationManager.instance.controllerFor(book, config);
        }
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _progress = null;
        });
      }
    }
  }

  Future<String> _preprocessContent(
    String content,
    String language,
    AiConfig config,
    AiChunkCache cache,
  ) async {
    final client = AiClient(config);
    final chunks = _planTextChunks(content);
    final outputs = List<String>.filled(chunks.length, '');
    var completed = 0;
    await runWithConcurrency(chunks, 3, (chunk, index) async {
      final key = cache.keyFor('reading-segment|v2', language, chunk);
      String? processed = await cache.read(key);
      if (processed == null) {
        try {
          processed = await client.segmentText(
            text: chunk,
            language: readingLanguageFor(language).label,
          );
          final cleaned = processed.trim();
          if (cleaned.isNotEmpty) {
            await cache.write(key, cleaned);
          }
        } catch (_) {
          processed = null;
        }
      }
      final cleaned = (processed ?? '').trim();
      outputs[index] = cleaned.isEmpty ? chunk : cleaned;
      completed++;
      if (mounted) {
        setState(
          () => _progress =
              'AI 分词预处理 $completed/${chunks.length}…',
        );
      }
    });
    final result = outputs.join('\n').trim();
    if (result.isEmpty || result.length < content.length * 0.3) {
      return content;
    }
    return result;
  }

  List<String> _planTextChunks(String content, {int maxChars = 1000}) {
    final paragraphs = content
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
    final chunks = <String>[];
    final buffer = StringBuffer();
    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) {
        chunks.add(value);
      }
      buffer.clear();
    }

    for (final paragraph in paragraphs) {
      if (buffer.isNotEmpty && buffer.length + paragraph.length > maxChars) {
        flush();
      }
      if (paragraph.length > maxChars) {
        final sentences = paragraph
            .split(RegExp(r'(?<=[.!?。！？])\s*'))
            .where((sentence) => sentence.trim().isNotEmpty);
        for (final sentence in sentences) {
          if (buffer.isNotEmpty && buffer.length + sentence.length > maxChars) {
            flush();
          }
          buffer.write(sentence);
          if (buffer.length >= maxChars) {
            flush();
          }
        }
      } else {
        buffer.writeln(paragraph);
      }
    }
    flush();
    return chunks;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入读物'),
        actions: [
          TextButton.icon(
            onPressed: _importing ? null : _pickFiles,
            icon: const Icon(Icons.add),
            label: const Text('添加文件'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.library_add_outlined,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text('选择 TXT 或 EPUB 文件'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _pickFiles,
                            icon: const Icon(Icons.file_open_outlined),
                            label: const Text('选择文件'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex--;
                        }
                        final item = _items.removeAt(oldIndex);
                        _items.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        key: ValueKey(item),
                        child: ListTile(
                          leading: const Icon(Icons.drag_handle),
                          title: Text(item.title),
                          subtitle: Text(
                            '${readingLanguageFor(item.language).label} · '
                            '${item.content.length} 字符'
                            '${_merge ? ' · ${_items.indexOf(item) + 1}' : ''}',
                          ),
                          trailing: IconButton(
                            tooltip: '移除',
                            onPressed: () => setState(() => _items.removeAt(index)),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('合并为一本书（按顺序分章）'),
                  subtitle: const Text('默认每个文件独立成书'),
                  value: _merge,
                  onChanged: (value) => setState(() => _merge = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI 预处理无空格语言'),
                  subtitle: const Text('日/中/泰插入分词空格，实验性'),
                  value: _preprocess,
                  onChanged: (value) => setState(() => _preprocess = value),
                ),
                if (!_merge)
                  Row(
                    children: [
                      const Expanded(child: Text('无章节时')),
                      DropdownButton<ChapterFallback>(
                        value: _fallback,
                        items: const [
                          DropdownMenuItem(
                            value: ChapterFallback.single,
                            child: Text('整本单章'),
                          ),
                          DropdownMenuItem(
                            value: ChapterFallback.pseudo,
                            child: Text('每 30 段伪章节'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _fallback = value);
                          }
                        },
                      ),
                    ],
                  ),
                if (_merge && _mixedLanguages)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '多个文件的识别语言不一致，无法合并；请关闭合并或只选同一语言。',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _items.isEmpty || _importing ||
                            (_merge && _mixedLanguages)
                        ? null
                        : _import,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _importing
                          ? (_progress ?? '处理中…')
                          : '导入 ${_items.length} 个文件'
                                '${_merge ? '（合并）' : ''}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
