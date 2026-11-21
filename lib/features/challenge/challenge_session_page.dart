import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/challenge/challenge_store.dart';
import '../../core/challenge/challenge_widget_sync.dart';
import '../../core/challenge/rank_store.dart';
import '../../core/text/japanese_kana.dart';
import '../../core/text/normalize.dart';
import '../../core/vocab/vocab_store.dart';

class ChallengeSessionPage extends ConsumerStatefulWidget {
  const ChallengeSessionPage({
    super.key,
    required this.entries,
    required this.difficulty,
    required this.count,
    this.ranked = false,
    this.specificLanguage = false,
  });

  final List<VocabEntry> entries;
  final ChallengeDifficulty difficulty;
  final int count;
  final bool ranked;
  final bool specificLanguage;

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
  RankPointsBreakdown? _breakdown;

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

  String get _kanaReading {
    final entry = _current;
    if (entry == null || entry.language != 'ja') {
      return '';
    }
    return japaneseKanaOf(_reading);
  }

  bool _isCorrect(String value) {
    final answer = normalizeForMatch(value);
    if (answer.isEmpty) {
      return false;
    }
    if (answer == normalizeForMatch(_target)) {
      return true;
    }
    // Japanese words can also be spelled in hiragana.
    final kana = _kanaReading;
    if (kana.isEmpty) {
      return false;
    }
    final typedKana = japaneseKanaOf(value);
    return typedKana.isNotEmpty && typedKana == kana;
  }

  void _onInputChanged(String value) {
    if (_advancing || _finished || _target.isEmpty) {
      return;
    }
    if (!_isCorrect(value)) {
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
    RankPointsBreakdown? breakdown;
    if (widget.ranked && _difficulty.affectsRank) {
      breakdown = rankPointsFor(
        difficulty: _difficulty,
        score: score,
        specificLanguage: widget.specificLanguage,
      );
      rankState = await const RankStore().applyPoints(breakdown.finalPoints);
    }
    await ChallengeWidgetSync.sync();
    if (!mounted) {
      return;
    }
    setState(() {
      _averages = averages;
      _rankState = rankState;
      _breakdown = breakdown;
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
        breakdown: _breakdown,
        ranked: widget.ranked,
        onRetry: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (context) => ChallengeSessionPage(
                entries: widget.entries,
                difficulty: _difficulty,
                count: widget.count,
                ranked: widget.ranked,
                specificLanguage: widget.specificLanguage,
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
              decoration: InputDecoration(
                labelText: '拼写单词',
                hintText: '拼写正确会自动进入下一题',
                helperText: _kanaReading.isEmpty ? null : '日语也可以用平假名拼写',
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
    required this.breakdown,
    required this.ranked,
    required this.onRetry,
  });

  final ChallengeDifficulty difficulty;
  final double score;
  final int correct;
  final int total;
  final ChallengeAverages? averages;
  final RankState? rankState;
  final RankPointsBreakdown? breakdown;
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
                        '训练模式将不结算排位积分',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else if (breakdown != null) ...[
                      _RankPointsFlow(breakdown: breakdown!),
                      const SizedBox(height: 8),
                      Text(
                        rankState?.displayText ?? '--',
                        style: theme.textTheme.titleMedium,
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

class _RankPointsFlow extends StatefulWidget {
  const _RankPointsFlow({required this.breakdown});

  final RankPointsBreakdown breakdown;

  @override
  State<_RankPointsFlow> createState() => _RankPointsFlowState();
}

class _RankPointsFlowState extends State<_RankPointsFlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _value;
  bool _stepsShown = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _value = Tween<double>(
      begin: 0,
      end: widget.breakdown.base.toDouble(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward().whenComplete(() {
      if (mounted) {
        setState(() => _stepsShown = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _multiplier(double value) => '×${value.toStringAsFixed(1)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdown = widget.breakdown;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _value,
          builder: (context, _) => Text(
            '${_value.value.round()}',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: breakdown.finalPoints >= 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
        ),
        Text('基础段位分', style: muted),
        if (_stepsShown) ...[
          const SizedBox(height: 6),
          Text(
            '语种倍率 ${_multiplier(breakdown.languageMultiplier)}→ ${breakdown.afterLanguage}',
            style: muted,
          ),
          Text(
            '难度加成 ${_multiplier(breakdown.difficultyMultiplier)}→ ${breakdown.finalPoints}',
            style: muted,
          ),
          const SizedBox(height: 4),
          Text(
            '本次 ${breakdown.finalPoints >= 0 ? '+' : ''}${breakdown.finalPoints}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: breakdown.finalPoints >= 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
