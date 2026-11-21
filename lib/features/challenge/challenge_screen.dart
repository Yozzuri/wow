import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/challenge/challenge_store.dart';
import '../../core/challenge/rank_store.dart';
import '../../core/vocab/vocab_store.dart';
import 'challenge_session_page.dart';

class ChallengeScreen extends ConsumerStatefulWidget {
  const ChallengeScreen({super.key});

  @override
  ConsumerState<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends ConsumerState<ChallengeScreen> {
  static const _countOptions = [10, 20, 30, 50];

  int _count = 10;
  ChallengeDifficulty _difficulty = ChallengeDifficulty.regular;
  bool _ranked = false;
  List<VocabEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ref.read(vocabStoreProvider).load();
    final usable = entries
        .where((entry) => _targetOf(entry).isNotEmpty)
        .toList();
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = usable;
      _loading = false;
    });
  }

  static String _targetOf(VocabEntry entry) {
    final lemma = entry.lemma.trim();
    return lemma.isEmpty ? entry.word.trim() : lemma;
  }

  Future<void> _start() async {
    await _load();
    if (!mounted) {
      return;
    }
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生词本里还没有可拼写的单词')),
      );
      return;
    }
    final count = min(_count, _entries.length);
    if (count < _count) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('可用单词只有 $count 个，本次按 $count 题开始')),
      );
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChallengeSessionPage(
          entries: _entries,
          difficulty: _difficulty,
          count: count,
          ranked: _ranked,
        ),
      ),
    );
    ref.invalidate(challengeAveragesProvider);
    ref.invalidate(rankProvider);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final averages = ref.watch(challengeAveragesProvider);
    final rank = ref.watch(rankProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('挑战')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  '看读音和释义拼写单词。拼写正确立刻进入下一题，时间会逐题减少。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (rank.valueOrNull != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '当前段位',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                '第 ${rank.value!.season} 赛季',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            rank.value!.displayText,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rank.value!.isTopTier
                                ? '已到最高段位，继续积累星数'
                                : '距离下一颗星还差 ${rank.value!.pointsToNextStar} 分',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '赛季剩余 ${rank.value!.seasonDaysLeft.clamp(0, rankSeasonDays)} 天',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text('题目数量', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in _countOptions)
                      ChoiceChip(
                        label: Text('$option 题'),
                        selected: _count == option,
                        onSelected: (_) => setState(() => _count = option),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _entries.isEmpty
                      ? '生词本暂无可用单词'
                      : '当前可用 ${_entries.length} 个单词',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Text('难度', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final difficulty in ChallengeDifficulty.values)
                  _DifficultyCard(
                    difficulty: difficulty,
                    selected: _difficulty == difficulty,
                    average: averages.valueOrNull?.averageFor(difficulty),
                    onTap: () => setState(() => _difficulty = difficulty),
                  ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _ranked,
                  onChanged: (value) =>
                      setState(() => _ranked = value ?? false),
                  title: const Text('开启排位'),
                  subtitle: Text(
                    _difficulty.affectsRank
                        ? '本次成绩会加减排位积分'
                        : '训练难度可以开启，但不加也不扣排位积分',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始挑战'),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('各难度平均分', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        for (final item in ChallengeDifficulty.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(child: Text(item.label)),
                                Text(
                                  _formatAverage(
                                    averages.valueOrNull?.averageFor(item),
                                  ),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${averages.valueOrNull?.countFor(item) ?? 0} 次',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static String _formatAverage(double? value) =>
      value == null ? '--' : value.toStringAsFixed(1);
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.difficulty,
    required this.selected,
    required this.average,
    required this.onTap,
  });

  final ChallengeDifficulty difficulty;
  final bool selected;
  final double? average;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      difficulty.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      difficulty.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                average == null ? '--' : average!.toStringAsFixed(1),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
