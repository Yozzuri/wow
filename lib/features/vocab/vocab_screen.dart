import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/vocab/checkin_store.dart';
import '../../core/vocab/daily_tasks.dart';
import '../../core/vocab/learning_plan.dart';
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

  Future<void> _startDaily(DailyTasks tasks) async {
    if (tasks.total == 0) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LearnSessionPage(
          newEntries: tasks.newWords,
          reviewEntries: tasks.reviewWords,
          pool: _entries,
        ),
      ),
    );
    await ref.read(checkinProvider.notifier).refresh();
    await _load();
  }

  Future<void> _startExtra(DailyTasks tasks) async {
    if (tasks.extraReviewWords.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LearnSessionPage(
          newEntries: const [],
          reviewEntries: tasks.extraReviewWords,
          pool: _entries,
        ),
      ),
    );
    await ref.read(checkinProvider.notifier).refresh();
    await _load();
  }

  Future<void> _reviewSingle(VocabEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LearnSessionPage(
          newEntries: entry.isNew ? [entry] : const [],
          reviewEntries: entry.isNew ? const [] : [entry],
          pool: _entries,
        ),
      ),
    );
    await ref.read(checkinProvider.notifier).refresh();
    await _load();
  }

  Future<void> _checkIn() async {
    await ref.read(checkinProvider.notifier).checkIn();
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入词书：${book.name}')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('词书导入失败：$error')));
      }
    }
  }

  Future<void> _deleteWordbook(Wordbook book) async {
    await _wordbookStore.delete(book);
    await _load();
  }

  Future<void> _studyWordbook(Wordbook book) async {
    final store = ref.read(vocabStoreProvider);
    var added = 0;
    for (final entry in book.entries) {
      final inserted = await store.addToken(
        word: entry.word,
        lemma: entry.word,
        pos: entry.pos,
        meaning: entry.meaning.isEmpty ? entry.usage : entry.meaning,
        sentence: entry.example.isNotEmpty ? entry.example : entry.usage,
        reading: entry.reading,
        inflection: entry.pitchAccent == null
            ? null
            : '音调：${entry.pitchAccent}',
        language: book.language,
        sourceTitle: book.name,
      );
      if (inserted) {
        added++;
      }
    }
    if (added > 0) {
      ref.read(vocabVersionProvider.notifier).state++;
      await _load();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added > 0 ? '已加入学习队列：$added 个词条' : '词条已存在学习队列中'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(vocabVersionProvider, (previous, next) => _load());
    final plan = ref.watch(learningPlanProvider);
    final checkin = ref.watch(checkinProvider);
    final tasks = buildDailyTasks(_entries, plan);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
              tasks: tasks,
              totalCount: _entries.length,
              streak: checkin.streak,
              checkedInToday: checkin.checkedInToday,
              onStart: () => _startDaily(tasks),
              onContinueReview: tasks.extraReviewWords.isEmpty
                  ? null
                  : () => _startExtra(tasks),
              onCheckIn: _checkIn,
              onOpenPlan: () => context.go('/settings'),
            ),
            _WordbookTab(
              entries: _entries,
              onReview: _reviewSingle,
              onRefresh: _load,
              onStart: () =>
                  tasks.total > 0 ? _startDaily(tasks) : _startExtra(tasks),
            ),
            _ImportTab(
              wordbooks: _wordbooks,
              onOpenImport: _openImport,
              onImportJson: _importJsonWordbook,
              onDelete: _deleteWordbook,
              onStudy: _studyWordbook,
            ),
          ],
        ),
      ),
    );
  }
}

class _LearnTab extends StatelessWidget {
  const _LearnTab({
    required this.tasks,
    required this.totalCount,
    required this.streak,
    required this.checkedInToday,
    required this.onStart,
    required this.onContinueReview,
    required this.onCheckIn,
    required this.onOpenPlan,
  });

  final DailyTasks tasks;
  final int totalCount;
  final int streak;
  final bool checkedInToday;
  final VoidCallback onStart;
  final VoidCallback? onContinueReview;
  final VoidCallback onCheckIn;
  final VoidCallback onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = tasks.plan;
    final hasQueue = tasks.total > 0;
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
                    Expanded(
                      child: Text('今日学习', style: theme.textTheme.titleMedium),
                    ),
                    if (streak > 0 || checkedInToday)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              size: 16,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '连续 $streak 天',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _CountTile(
                        value: tasks.newWords.length,
                        label: '待新学',
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                    Expanded(
                      child: _CountTile(
                        value: tasks.reviewWords.length,
                        label: '待复习',
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '今日已学 ${tasks.newDoneToday}/${plan.newPerDay} · '
                  '已复习 ${tasks.reviewDoneToday}/${plan.reviewPerDay}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (tasks.extraReviewWords.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '今日计划之外还有 ${tasks.extraReviewWords.length} 个到期词',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: hasQueue ? onStart : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(hasQueue ? '开始今日任务' : '今日任务已完成'),
                  ),
                ),
                if (!hasQueue && onContinueReview != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onContinueReview,
                      icon: const Icon(Icons.refresh),
                      label: Text('继续复习剩余 ${tasks.extraReviewWords.length} 个'),
                    ),
                  ),
                ],
                if (!hasQueue && totalCount > 0 && !checkedInToday) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onCheckIn,
                      icon: const Icon(Icons.local_fire_department),
                      label: const Text('完成打卡'),
                    ),
                  ),
                ],
                if (checkedInToday) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '今日已打卡',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('学习计划'),
            subtitle: Text(
              '每日新学 ${plan.newPerDay} 个 · 每日复习 ${plan.reviewPerDay} 个',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenPlan,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '生词本共 $totalCount 个词条。每天先完成新学，再复习今天到期的单词，全部完成后打卡。',
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
    final due = entries.where((entry) => entry.learned && entry.isDue).length;
    final fresh = entries.where((entry) => entry.isNew).length;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '待学习 $fresh · 到期 $due · 共 ${entries.length}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (due + fresh > 0)
                FilledButton(onPressed: onStart, child: const Text('开始任务')),
            ],
          ),
          const SizedBox(height: 8),
          ...entries.map((entry) {
            final isDue = entry.learned && entry.isDue;
            final isNew = entry.isNew;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: isDue
                    ? theme.colorScheme.primaryContainer
                    : isNew
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  entry.lemma.isEmpty
                      ? '?'
                      : entry.lemma.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: isDue
                        ? theme.colorScheme.onPrimaryContainer
                        : isNew
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(entry.lemma, overflow: TextOverflow.ellipsis),
                  ),
                  if (isDue || isNew) ...[
                    const SizedBox(width: 8),
                    Badge(
                      label: Text(isDue ? '到期' : '待学习'),
                      backgroundColor: isDue
                          ? theme.colorScheme.primary
                          : theme.colorScheme.tertiary,
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
                isNew
                    ? '新词'
                    : isDue
                    ? '现在'
                    : _dueLabel(entry.dueAt),
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
    required this.onStudy,
  });

  final List<Wordbook> wordbooks;
  final VoidCallback onOpenImport;
  final VoidCallback onImportJson;
  final void Function(Wordbook book) onDelete;
  final void Function(Wordbook book) onStudy;

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
              subtitle: Text('${book.language} · ${book.entries.length} 个词条'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '加入学习',
                    onPressed: () => onStudy(book),
                    icon: const Icon(Icons.school_outlined),
                  ),
                  IconButton(
                    tooltip: '删除',
                    onPressed: () => onDelete(book),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
