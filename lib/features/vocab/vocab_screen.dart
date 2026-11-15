import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vocab/vocab_store.dart';
import '../common/placeholder_screen.dart';

class VocabScreen extends ConsumerStatefulWidget {
  const VocabScreen({super.key});

  @override
  ConsumerState<VocabScreen> createState() => _VocabScreenState();
}

class _VocabScreenState extends ConsumerState<VocabScreen> {
  List<VocabEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ref.read(vocabStoreProvider).load();
    entries.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
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

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(vocabVersionProvider, (previous, next) => _load());
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_entries.isEmpty) {
      return const PlaceholderScreen(
        title: '词汇',
        icon: Icons.style_outlined,
        description: '还没有生词。\n在视频里用 AI 解析字幕后，从右上角菜单「提取生词到生词本」。',
      );
    }
    final due = _entries.where((entry) => entry.isDue).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('词汇'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.school_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '到期 ${due.length} 个 · 共 ${_entries.length} 个',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (due.isNotEmpty)
                      FilledButton(
                        onPressed: () => _review(due.first),
                        child: const Text('开始复习'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ..._entries.map((entry) {
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
                      child: Text(
                        entry.lemma,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                onTap: () => _review(entry),
              );
            }),
          ],
        ),
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
    );
  }
}
