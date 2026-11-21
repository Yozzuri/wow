import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/challenge/challenge_store.dart';
import '../../core/challenge/challenge_widget_sync.dart';
import '../../core/challenge/rank_store.dart';
import '../../core/text/normalize.dart';
import '../../core/vocab/vocab_store.dart';

class ChallengeSessionPage extends ConsumerStatefulWidget {
  const ChallengeSessionPage({
    super.key,
    required this.entries,
    required this.difficulty,
    required this.count,
    this.ranked = false,
  });

  final List<VocabEntry> entries;
  final ChallengeDifficulty difficulty;
  final int count;
  final bool ranked;

  @override
  ConsumerState<ChallengeSessionPage> createState() =>
      _ChallengeSessionPageState();
}

class _ChallengeSessionPageState extends ConsumerState<ChallengeSessionPage>
    with SingleTickerProviderStateMixin {
  late final List<VocabEntry> _words;
  late final AnimationController _timer;

  final _input = TextEditingController();
  final _focus = FocusNode();

  int _index = 0;
  int _correct = 0;
  double _speedSum = 0;
  bool _advancing = false;
  bool _finished = false;
  double _score = 0;
  ChallengeAverages? _averages;
  RankState? _rankState;
  int _rankDelta = 0;

  ChallengeDifficulty get _difficulty => widget.difficulty;

  VocabEntry? get _current =>
      _index < _words.length ? _words[_index] : null;

  String get _target {
    final entry = _current;
    if (entry == null) {
      return '';
    }
    final lemma = entry.lemma.trim();
    return lemma.isEmpty ? entry.word.trim() : lemma;
  }

  String get _reading {
    final entry = _current;
    if (entry == null) {
      return '';
    }
    return (entry.surfaceReading ??
            entry.reading ??
            entry.lemmaReading ??
            '')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    final pool = [...widget.entries]..shuffle(Random());
    _words = pool.take(min(widget.count, pool.length)).toList();
    _timer = AnimationController(vsync: this);
    _timer.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _skipWord();
      }
    });
    _startWord();
  }

  @override
  void dispose() {
    _timer.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startWord() {
    final entry = _current;
    if (entry == null) {
      _finish();
      return;
    }
    _advancing = false;
    _input.clear();
    _timer
      ..stop()
      ..duration = Duration(
        milliseconds: (_difficulty.secondsFor(_index) * 1000).round(),
      )
      ..value = 0
      ..forward();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  void _onInputChanged(String value) {
    if (_advancing || _finished || _target.isEmpty) {
      return;
    }
    final answer = normalizeForMatch(value);
    if (answer.isEmpty || answer != normalizeForMatch(_target)) {
      return;
    }
    _advancing = true;
    _correct++;
    _speedSum += (1 - _timer.value).clamp(0.0, 1.0);
    _timer.stop();
    _nextWord();
  }

  void _skipWord() {
    if (_advancing || _finished) {
      return;
    }
    _advancing = true;
    _timer.stop();
    _nextWord();
  }

  void _nextWord() {
    if (_index + 1 >= _words.length) {
      _finish();
      return;
    }
    _index++;
    _startWord();
  }

  Future<void> _finish() async {
    if (_finished) {
      return;
    }
    final total = _words.length;
    final rate = total == 0 ? 0.0 : _correct / total;
    final speed = _correct == 0 ? 0.0 : _speedSum / _correct;
    final raw = 10 * (0.7 * rate + 0.3 * speed);
    final score = double.parse(raw.clamp(0.0, 10.0).toStringAsFixed(1));
    setState(() {
      _finished = true;
      _score = score;
    });
    _timer.stop();
    final averages = await const ChallengeStore().record(_difficulty, score);
    RankState? rankState;
    var rankDelta = 0;
    if (widget.ranked && _difficulty.affectsRank) {
      rankDelta = rankDeltaFor(_difficulty, score);
      rankState = await const RankStore().applyResult(_difficulty, score);
    }
    await ChallengeWidgetSync.sync();
    if (!mounted) {
      return;
    }
    setState(() {
      _averages = averages;
      _rankState = rankState;
      _rankDelta = rankDelta;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_finished) {
      return _ResultView(
        difficulty: _difficulty,
        score: _score,
        correct: _correct,
        total: _words.length,
        averages: _averages,
        rankState: _rankState,
        rankDelta: _rankDelta,
        ranked: widget.ranked,
        onRetry: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (context) => ChallengeSessionPage(
                entries: widget.entries,
                difficulty: _difficulty,
                count: widget.count,
                ranked: widget.ranked,
              ),
            ),
          );
        },
      );
    }
    final entry = _current;
    if (entry == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final meaning = entry.displayMeaning.trim();
    final reading = _reading;
    return Scaffold(
      appBar: AppBar(
        title: Text('拼写挑战 · ${_difficulty.label}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _words.isEmpty ? 0 : _index / _words.length,
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Text(
                  '第 ${_index + 1} / ${_words.length} 题',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '答对 $_correct',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: _timer,
              builder: (context, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 1 - _timer.value,
                  minHeight: 6,
                  color: _timer.value > 0.6
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meaning.isEmpty ? '（暂无释义）' : meaning,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      height: 1.4,
                    ),
                  ),
                  if (reading.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      reading,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _input,
              focusNode: _focus,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '拼写单词',
                hintText: '拼写正确会自动进入下一题',
              ),
              onChanged: _onInputChanged,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _skipWord,
                    child: const Text('跳过'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.difficulty,
    required this.score,
    required this.correct,
    required this.total,
    required this.averages,
    required this.rankState,
    required this.rankDelta,
    required this.ranked,
    required this.onRetry,
  });

  final ChallengeDifficulty difficulty;
  final double score;
  final int correct;
  final int total;
  final ChallengeAverages? averages;
  final RankState? rankState;
  final int rankDelta;
  final bool ranked;
  final VoidCallback onRetry;

  String _format(double? value) =>
      value == null ? '--' : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('挑战结果 · ${difficulty.label}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  score.toStringAsFixed(1),
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '综合评分 / 10.0',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '答对 $correct / $total',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (ranked) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('排位', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    if (!difficulty.affectsRank)
                      Text(
                        '训练难度不计入排位，本次段位没有变化。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rankState?.displayText ?? '--',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            rankDelta >= 0
                                ? '+$rankDelta'
                                : '$rankDelta',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: rankDelta >= 0
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '排位积分',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
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
                            _format(averages?.averageFor(item)),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('再来一次'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
