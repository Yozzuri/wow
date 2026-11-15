import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vocab/vocab_store.dart';
import '../../core/vocab/wordbook.dart';
import 'learn_session_page.dart';
import 'wordbook_import_screen.dart';

class VocabScreen extends ConsumerStatefulWidget {
  const VocabScreen({super.key});

  @override
  ConsumerState<VocabScreen> createState() => _VocabScreenState();
}

class _VocabScreenState extends ConsumerState<VocabScreen> {
  static const _wordbookStore = WordbookStore();

  List<VocabEntry> _entries = const [];
  List<Wordbook> _wordbooks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ref.read(vocabStoreProvider).load();
    final wordbooks = await _wordbookStore.list();
    entries.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _wordbooks = wordbooks;
      _loading = false;
    });
  }

  Future<void> _review(VocabEntry entry) async {
    final rated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ReviewSheetBody(entry: entry),
    );
    if (rated == true) {
      await _load();
    }
  }

  Future<void> _startLearning(List<VocabEntry> queue) async {
    if (queue.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LearnSessionPage(entries: queue),
      ),
    );
    await _load();
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const WordbookImportScreen(),
      ),
    );
    await _load();
  }

  Future<void> _importJsonWordbook() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = (result != null && result.files.isNotEmpty)
        ? result.files.first
        : null;
    if (file == null) {
      return;
    }
    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final book = _wordbookStore.parseJson(
        utf8.decode(bytes, allowMalformed: true),
      );
      await _wordbookStore.save(book);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入词书：${book.name}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('词书导入失败：$error')));
      }
    }
  }

  Future<void> _deleteWordbook(Wordbook book) async {
    await _wordbookStore.delete(book);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(vocabVersionProvider, (previous, next) => _load());
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final dueReview = _entries
        .where((entry) => entry.reps > 0 && entry.isDue)
        .toList();
    final newEntries = _entries.where((entry) => entry.reps == 0).toList();
    final queue = [...dueReview, ...newEntries];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('词汇'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '学习'),
              Tab(text: '生词本'),
              Tab(text: '导入词书'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LearnTab(
              dueCount: dueReview.length,
              newCount: newEntries.length,
              totalCount: _entries.length,
              onStart: () => _startLearning(queue),
            ),
            _WordbookTab(
              entries: _entries,
              onReview: _review,
              onRefresh: _load,
              onStart: () => _startLearning(
                _entries.where((entry) => entry.isDue).toList(),
              ),
            ),
            _ImportTab(
              wordbooks: _wordbooks,
              onOpenImport: _openImport,
              onImportJson: _importJsonWordbook,
              onDelete: _deleteWordbook,
            ),
          ],
        ),
      ),
    );
  }
}

class _LearnTab extends StatelessWidget {
  const _LearnTab({
    required this.dueCount,
    required this.newCount,
    required this.totalCount,
    required this.onStart,
  });

  final int dueCount;
  final int newCount;
  final int totalCount;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQueue = dueCount + newCount > 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.today_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text('今日学习', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _CountTile(
                        value: dueCount,
                        label: '需复习',
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Expanded(
                      child: _CountTile(
                        value: newCount,
                        label: '需新学',
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: hasQueue ? onStart : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(hasQueue ? '开始学习' : '今天没有需要学习的词'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '生词本共 $totalCount 个词条。学习界面会先复习到期单词，再学习新词。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$value',
          style: theme.textTheme.displaySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _WordbookTab extends StatelessWidget {
  const _WordbookTab({
    required this.entries,
    required this.onReview,
    required this.onRefresh,
    required this.onStart,
  });

  final List<VocabEntry> entries;
  final void Function(VocabEntry entry) onReview;
  final Future<void> Function() onRefresh;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.style_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text('还没有生词', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '在视频里用 AI 解析字幕后，从右上角菜单「提取生词到生词本」。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final due = entries.where((entry) => entry.isDue).toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '到期 ${due.length} 个 · 共 ${entries.length} 个',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (due.isNotEmpty)
                FilledButton(
                  onPressed: onStart,
                  child: const Text('复习到期'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...entries.map((entry) {
            final isDue = entry.isDue;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: isDue
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  entry.lemma.isEmpty
                      ? '?'
                      : entry.lemma.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: isDue
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(entry.lemma, overflow: TextOverflow.ellipsis),
                  ),
                  if (isDue) ...[
                    const SizedBox(width: 8),
                    Badge(
                      label: const Text('到期'),
                      backgroundColor: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                entry.meaning.isEmpty
                    ? entry.sentence.replaceAll('\n', ' ')
                    : '${entry.meaning} · ${entry.sentence.replaceAll('\n', ' ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                isDue ? '现在' : _dueLabel(entry.dueAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => onReview(entry),
            );
          }),
        ],
      ),
    );
  }

  static String _dueLabel(DateTime dueAt) {
    final diff = dueAt.difference(DateTime.now());
    if (diff.inDays >= 1) {
      return '${diff.inDays} 天后';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours} 小时后';
    }
    return '${diff.inMinutes.clamp(1, 59)} 分钟后';
  }
}

class _ImportTab extends StatelessWidget {
  const _ImportTab({
    required this.wordbooks,
    required this.onOpenImport,
    required this.onImportJson,
    required this.onDelete,
  });

  final List<Wordbook> wordbooks;
  final VoidCallback onOpenImport;
  final VoidCallback onImportJson;
  final void Function(Wordbook book) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
            title: const Text('AI 转换词书'),
            subtitle: const Text('用提示词把 TXT 词书转换成标准 JSON，再导入'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenImport,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onImportJson,
          icon: const Icon(Icons.data_object),
          label: const Text('导入 JSON 词书'),
        ),
        const SizedBox(height: 16),
        Text('已导入词书', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (wordbooks.isEmpty)
          Text(
            '还没有导入词书。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...wordbooks.map(
            (book) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(book.name),
              subtitle: Text(
                '${book.language} · ${book.entries.length} 个词条',
              ),
              trailing: IconButton(
                tooltip: '删除',
                onPressed: () => onDelete(book),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewSheetBody extends ConsumerStatefulWidget {
  const _ReviewSheetBody({required this.entry});

  final VocabEntry entry;

  @override
  ConsumerState<_ReviewSheetBody> createState() => _ReviewSheetBodyState();
}

class _ReviewSheetBodyState extends ConsumerState<_ReviewSheetBody> {
  bool _revealed = false;
  bool _saving = false;

  Future<void> _rate(ReviewGrade grade) async {
    setState(() => _saving = true);
    await ref.read(vocabStoreProvider).review(widget.entry, grade);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.lemma,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  if ((entry.pos ?? '').isNotEmpty)
                    Chip(
                      label: Text(entry.pos!),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (entry.word.toLowerCase() != entry.lemma.toLowerCase())
                Text(
                  '原文：${entry.word}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 12),
              Text(entry.sentence, style: theme.textTheme.bodyLarge),
              if ((entry.translation ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  entry.translation!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (!_revealed)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _revealed = true),
                    child: const Text('显示释义'),
                  ),
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.meaning.isEmpty ? '（没有释义）' : entry.meaning,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _rate(ReviewGrade.forgot),
                        child: const Text('忘记'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _rate(ReviewGrade.hard),
                        child: const Text('模糊'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _rate(ReviewGrade.good),
                        child: const Text('记得'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _saving
                            ? null
                            : () => _rate(ReviewGrade.easy),
                        child: const Text('简单'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
