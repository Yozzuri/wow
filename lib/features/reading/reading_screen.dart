import 'dart:convert';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';
import '../../core/reading/reading_book.dart';
import 'reader_page.dart';

class _ImportOptions {
  const _ImportOptions({required this.language, required this.preprocess});

  final String language;
  final bool preprocess;
}

class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  static const _store = ReadingStore();

  List<ReadingBook> _books = const [];
  bool _loading = true;
  bool _importing = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await _store.list();
    if (!mounted) {
      return;
    }
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  Future<_ImportOptions?> _askOptions() {
    var language = 'en';
    var preprocess = false;
    return showDialog<_ImportOptions>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final usesSpaces = readingLanguageFor(language).usesSpaces;
          return AlertDialog(
            title: const Text('导入读物'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: language,
                  decoration: const InputDecoration(labelText: '文本语言'),
                  items: [
                    for (final item in readingLanguages)
                      DropdownMenuItem(
                        value: item.code,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() {
                      language = value;
                      preprocess = !readingLanguageFor(value).usesSpaces;
                    });
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI 预处理分词'),
                  subtitle: Text(
                    usesSpaces
                        ? '该语言以空格分词，通常不需要预处理'
                        : '无空格语言，建议用 AI 插入分词空格',
                  ),
                  value: preprocess && !usesSpaces,
                  onChanged: usesSpaces
                      ? null
                      : (value) => setDialogState(() => preprocess = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _ImportOptions(language: language, preprocess: preprocess),
                ),
                child: const Text('选择文件'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importBook() async {
    final options = await _askOptions();
    if (options == null) {
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub'],
      withData: true,
    );
    final file = (result != null && result.files.isNotEmpty)
        ? result.files.first
        : null;
    if (file == null) {
      return;
    }
    setState(() {
      _importing = true;
      _progress = '读取文件…';
    });
    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final isEpub = file.name.toLowerCase().endsWith('.epub');
      var content = isEpub
          ? await _extractEpub(bytes)
          : const Utf8Decoder(allowMalformed: true).convert(bytes);
      if (content.trim().isEmpty) {
        throw const FormatException('文件内容为空');
      }
      if (options.preprocess && !readingLanguageFor(options.language).usesSpaces) {
        content = await _preprocessWithAi(content, options.language);
      }
      final title = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;
      final book = ReadingBook(
        id: '',
        title: title,
        language: options.language,
        content: content,
        createdAt: DateTime.now(),
        preprocessed: options.preprocess,
      );
      await _store.save(book);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导入读物：$title')));
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

  Future<String> _preprocessWithAi(String content, String language) async {
    final config = await ref.read(aiConfigProvider.future);
    if (!config.isConfigured) {
      throw StateError('需要先在设置中配置 AI 接口');
    }
    final client = AiClient(config);
    final chunks = <String>[];
    const size = 1200;
    for (var start = 0; start < content.length; start += size) {
      final end = (start + size).clamp(0, content.length);
      chunks.add(content.substring(start, end));
    }
    final output = StringBuffer();
    for (var index = 0; index < chunks.length; index++) {
      if (mounted) {
        setState(() => _progress = 'AI 分词预处理 ${index + 1}/${chunks.length}…');
      }
      try {
        final processed = await client.segmentText(
          text: chunks[index],
          language: readingLanguageFor(language).label,
        );
        final cleaned = processed.trim();
        output.write(cleaned.isEmpty ? chunks[index] : cleaned);
      } catch (_) {
        output.write(chunks[index]);
      }
      output.write('\n');
    }
    final result = output.toString().trim();
    if (result.isEmpty || result.length < content.length * 0.3) {
      return content;
    }
    return result;
  }

  Future<void> _deleteBook(ReadingBook book) async {
    await _store.delete(book);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读'),
        actions: [
          IconButton(
            tooltip: '导入读物',
            onPressed: _importing ? null : _importBook,
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_importing)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_progress ?? '处理中…')),
                        ],
                      ),
                    ),
                  ),
                if (_books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Column(
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 72,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text('导入 TXT 或 EPUB 开始阅读', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          '支持点词、点句、点短语三种查阅方式。EPUB 为实验性功能。',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _importing ? null : _importBook,
                          icon: const Icon(Icons.add),
                          label: const Text('导入读物'),
                        ),
                      ],
                    ),
                  )
                else
                  ..._books.map(
                    (book) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: Text(book.title),
                      subtitle: Text(
                        '${readingLanguageFor(book.language).label} · ${book.characterCount} 字符'
                        '${book.preprocessed ? ' · 已 AI 预处理' : ''}',
                      ),
                      trailing: IconButton(
                        tooltip: '删除',
                        onPressed: () => _deleteBook(book),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => ReaderPage(book: book),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
