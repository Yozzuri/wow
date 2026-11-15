import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/reading/reading_book.dart';
import 'reader_page.dart';
import 'reading_import_screen.dart';

class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  static const _store = ReadingStore();

  List<ReadingBook> _books = const [];
  bool _loading = true;

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

  Future<void> _import() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ReadingImportScreen(),
      ),
    );
    await _load();
  }

  Future<void> _delete(ReadingBook book) async {
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
            onPressed: _import,
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                      '支持多文件导入、章节、点词/点句/点短语和分段翻译。EPUB 为实验性功能。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.add),
                      label: const Text('导入读物'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._books.map(
                  (book) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(book.title),
                    subtitle: Text(
                      '${readingLanguageFor(book.language).label} · '
                      '${book.characterCount} 字符 · '
                      '${book.effectiveChapters.length} 章'
                      '${book.preprocessed ? ' · 已 AI 预处理' : ''}',
                    ),
                    trailing: IconButton(
                      tooltip: '删除',
                      onPressed: () => _delete(book),
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
