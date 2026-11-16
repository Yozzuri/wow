import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/normalize.dart';
import '../../core/vocab/checkin_store.dart';
import '../../core/vocab/daily_tasks.dart';
import '../../core/vocab/learning_plan.dart';
import '../../core/vocab/vocab_store.dart';

enum _Phase { learning, review, done }

enum _Step { familiarity, meaning, word, spelling }

class LearnSessionPage extends ConsumerStatefulWidget {
  const LearnSessionPage({
    super.key,
    required this.newEntries,
    required this.reviewEntries,
    this.pool = const [],
  });

  final List<VocabEntry> newEntries;
  final List<VocabEntry> reviewEntries;

  /// All known entries, used to build distractor options.
  final List<VocabEntry> pool;

  @override
  ConsumerState<LearnSessionPage> createState() => _LearnSessionPageState();
}

class _LearnSessionPageState extends ConsumerState<LearnSessionPage> {
  late final List<VocabEntry> _learningQueue = [...widget.newEntries];
  late final List<VocabEntry> _reviewQueue = [...widget.reviewEntries];
  late final List<VocabEntry> _pool = _buildPool();

  late _Phase _phase;
  int _learningIndex = 0;
  int _reviewIndex = 0;
  int _stepIndex = 0;
  int _learnedCount = 0;
  int _reviewedCount = 0;
  int _removedCount = 0;
  int _mistakes = 0;
  ReviewGrade? _selfGrade;
  bool _busy = false;
  bool _finishing = false;
  bool _checkedIn = false;
  int _streak = 0;
  String? _wrongChoice;
  String _feedback = '';
  List<String> _meaningOptions = const [];
  List<String> _wordOptions = const [];
  final _spelling = TextEditingController();
  final _spellingFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (_learningQueue.isNotEmpty) {
      _phase = _Phase.learning;
    } else if (_reviewQueue.isNotEmpty) {
      _phase = _Phase.review;
    } else {
      _phase = _Phase.done;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishAll());
      return;
    }
    _prepareWord();
  }

  @override
  void dispose() {
    _spelling.dispose();
    _spellingFocus.dispose();
    super.dispose();
  }

  List<VocabEntry> _buildPool() {
    final byKey = <String, VocabEntry>{};
    for (final entry in [
      ...widget.newEntries,
      ...widget.reviewEntries,
      ...widget.pool,
    ]) {
      byKey[entry.key] = entry;
    }
    return byKey.values.toList();
  }

  VocabEntry? get _entry {
    switch (_phase) {
      case _Phase.learning:
        if (_learningIndex < _learningQueue.length) {
          return _learningQueue[_learningIndex];
        }
        return null;
      case _Phase.review:
        if (_reviewIndex < _reviewQueue.length) {
          return _reviewQueue[_reviewIndex];
        }
        return null;
      case _Phase.done:
        return null;
    }
  }

  List<_Step> get _steps {
    final entry = _entry;
    if (entry == null) {
      return const [];
    }
    return [
      _Step.familiarity,
      if (_meaningOptions.length > 1) _Step.meaning,
      if (_wordOptions.length > 1) _Step.word,
      _Step.spelling,
    ];
  }

  void _prepareWord() {
    final entry = _entry;
    if (entry == null) {
      return;
    }
    _stepIndex = 0;
    _mistakes = 0;
    _selfGrade = null;
    _wrongChoice = null;
    _feedback = '';
    _spelling.clear();
    _meaningOptions = _buildMeaningOptions(entry);
    _wordOptions = _buildWordOptions(entry);
    setState(() {});
  }

  Future<void> _handleFamiliarity(String choice) async {
    final entry = _entry;
    if (entry == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    if (_phase == _Phase.learning) {
      if (choice == 'too_easy') {
        await ref.read(vocabStoreProvider).remove(entry);
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _removedCount++;
        });
        _nextLearningWord();
        return;
      }
      setState(() => _busy = false);
      _advanceStep();
      return;
    }
    final grade = switch (choice) {
      'forgot' => ReviewGrade.forgot,
      'hard' => ReviewGrade.hard,
      _ => ReviewGrade.good,
    };
    setState(() {
      _selfGrade = grade;
      _busy = false;
    });
    _advanceStep();
  }

  void _advanceStep() {
    final steps = _steps;
    if (_stepIndex + 1 < steps.length) {
      setState(() {
        _stepIndex++;
        _wrongChoice = null;
        _feedback = '';
        _spelling.clear();
      });
    } else {
      _finishWord();
    }
  }

  Future<void> _finishWord() async {
    final entry = _entry;
    if (entry == null) {
      return;
    }
    if (_phase == _Phase.learning) {
      setState(() => _busy = true);
      final updated = await ref.read(vocabStoreProvider).markLearned(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _learnedCount++;
      });
      _reviewQueue.add(updated ?? entry);
      _nextLearningWord();
      return;
    }
    setState(() => _busy = true);
    await ref.read(vocabStoreProvider).review(entry, _gradeFor(entry));
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _reviewedCount++;
    });
    _nextReviewWord();
  }

  ReviewGrade _gradeFor(VocabEntry entry) {
    final byMistakes = _mistakes >= 2
        ? ReviewGrade.forgot
        : _mistakes == 1
        ? ReviewGrade.hard
        : ReviewGrade.good;
    final self = _selfGrade;
    if (self == null) {
      return byMistakes;
    }
    return _rank(self) <= _rank(byMistakes) ? self : byMistakes;
  }

  int _rank(ReviewGrade grade) => switch (grade) {
    ReviewGrade.forgot => 0,
    ReviewGrade.hard => 1,
    ReviewGrade.good => 2,
    ReviewGrade.easy => 3,
  };

  void _nextLearningWord() {
    if (_learningIndex + 1 < _learningQueue.length) {
      setState(() {
        _learningIndex++;
        _busy = false;
      });
      _prepareWord();
      return;
    }
    setState(() {
      _phase = _Phase.review;
      _reviewIndex = 0;
      _busy = false;
    });
    if (_reviewQueue.isEmpty) {
      _finishAll();
    } else {
      _prepareWord();
    }
  }

  void _nextReviewWord() {
    if (_reviewIndex + 1 < _reviewQueue.length) {
      setState(() {
        _reviewIndex++;
        _busy = false;
      });
      _prepareWord();
      return;
    }
    _finishAll();
  }

  Future<void> _finishAll() async {
    if (_phase != _Phase.done) {
      setState(() {
        _phase = _Phase.done;
        _finishing = true;
        _busy = false;
      });
    } else {
      setState(() => _finishing = true);
    }
    final store = ref.read(vocabStoreProvider);
    final plan = ref.read(learningPlanProvider);
    final entries = await store.load();
    final done = buildDailyTasks(entries, plan).isDone;
    var checkedIn = false;
    var streak = ref.read(checkinProvider).streak;
    if (done) {
      final status = await ref.read(checkinProvider.notifier).checkIn();
      checkedIn = true;
      streak = status.streak;
    } else {
      await ref.read(checkinProvider.notifier).refresh();
      streak = ref.read(checkinProvider).streak;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _checkedIn = checkedIn;
      _streak = streak;
      _finishing = false;
    });
  }

  void _chooseOption(String value, String correct) {
    if (_busy) {
      return;
    }
    if (normalizeForMatch(value) == normalizeForMatch(correct)) {
      setState(() {
        _wrongChoice = null;
        _feedback = '';
      });
      _advanceStep();
      return;
    }
    setState(() {
      _wrongChoice = value;
      _feedback = '不对，再试一次';
      _mistakes++;
    });
  }

  void _submitSpelling(String correct) {
    if (_busy) {
      return;
    }
    final answer = normalizeForMatch(_spelling.text);
    if (answer.isNotEmpty &&
        (answer == normalizeForMatch(correct) ||
            answer == normalizeForMatch(_entry?.word ?? ''))) {
      setState(() => _feedback = '');
      _advanceStep();
      return;
    }
    setState(() {
      _feedback = '拼写不正确，再试一次';
      _mistakes++;
    });
    _spelling.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _spelling.text.length,
    );
    _spellingFocus.requestFocus();
  }

  List<String> _buildMeaningOptions(VocabEntry entry) {
    final target = entry.meaning.trim();
    if (target.isEmpty) {
      return const [];
    }
    final targetKey = normalizeForMatch(target);
    final pool = <String>{};
    for (final item in _pool) {
      final meaning = item.meaning.trim();
      if (meaning.isEmpty) {
        continue;
      }
      if (normalizeForMatch(meaning) == targetKey) {
        continue;
      }
      pool.add(meaning);
    }
    final random = Random(entry.key.hashCode);
    final distractors = pool.toList()..shuffle(random);
    return [target, ...distractors.take(3)]..shuffle(random);
  }

  List<String> _buildWordOptions(VocabEntry entry) {
    final target = entry.lemma.trim();
    if (target.isEmpty) {
      return const [];
    }
    final candidates = _pool
        .where(
          (item) =>
              item.language == entry.language &&
              item.lemma.trim().isNotEmpty &&
              normalizeForMatch(item.lemma) != normalizeForMatch(target),
        )
        .toList();
    candidates.sort(
      (a, b) =>
          _similarity(target, a.lemma).compareTo(_similarity(target, b.lemma)),
    );
    final random = Random(entry.key.hashCode);
    final picks = candidates.take(3).map((item) => item.lemma).toList()
      ..shuffle(random);
    return [target, ...picks]..shuffle(random);
  }

  double _similarity(String target, String candidate) {
    final a = target.toLowerCase();
    final b = candidate.toLowerCase();
    var score = _editDistance(a, b) + (a.length - b.length).abs() * 0.5;
    if (a.isNotEmpty && b.isNotEmpty && a[0] == b[0]) {
      score -= 0.4;
    }
    return score;
  }

  int _editDistance(String a, String b) {
    if (a == b) {
      return 0;
    }
    if (a.isEmpty) {
      return b.length;
    }
    if (b.isEmpty) {
      return a.length;
    }
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce(min);
      }
      previous = current;
    }
    return previous[b.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_phase == _Phase.done) {
      return _DoneView(
        theme: theme,
        checkedIn: _checkedIn,
        streak: _streak,
        learned: _learnedCount,
        reviewed: _reviewedCount,
        finishing: _finishing,
      );
    }
    final entry = _entry;
    if (entry == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final steps = _steps;
    final step = steps[_stepIndex.clamp(0, steps.length - 1)];
    final total = widget.newEntries.length + widget.reviewEntries.length;
    final completed = _learnedCount + _reviewedCount + _removedCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _phase == _Phase.learning
              ? '新学 ${_learningIndex + 1}/${_learningQueue.length}'
              : '复习 ${_reviewIndex + 1}/${_reviewQueue.length}',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (completed / total).clamp(0.0, 1.0),
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (step == _Step.familiarity || step == _Step.meaning)
              _WordHeader(entry: entry)
            else
              Text(
                step == _Step.word ? '看释义选单词' : '看释义拼写单词',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 24),
            if (step == _Step.familiarity)
              _FamiliarityStep(
                isLearning: _phase == _Phase.learning,
                busy: _busy,
                onSelect: _handleFamiliarity,
              )
            else if (step == _Step.meaning)
              _ChoiceStep(
                title: '选出最符合句意的释义',
                prompt: '',
                options: _meaningOptions,
                wrongChoice: _wrongChoice,
                feedback: _feedback,
                onSelect: (value) => _chooseOption(value, entry.meaning),
              )
            else if (step == _Step.word)
              _ChoiceStep(
                title: '选出与该释义对应的单词',
                prompt: entry.meaning,
                options: _wordOptions,
                wrongChoice: _wrongChoice,
                feedback: _feedback,
                onSelect: (value) => _chooseOption(value, entry.lemma),
              )
            else
              _SpellingStep(
                entry: entry,
                controller: _spelling,
                focusNode: _spellingFocus,
                feedback: _feedback,
                onSubmit: () => _submitSpelling(entry.lemma),
              ),
          ],
        ),
      ),
    );
  }
}

class _WordHeader extends StatelessWidget {
  const _WordHeader({required this.entry});

  final VocabEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                entry.lemma,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if ((entry.pos ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Chip(
                  label: Text(entry.pos!),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        if ((entry.reading ?? '').isNotEmpty)
          Text(
            entry.reading!,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        if ((entry.inflection ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              entry.inflection!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if ((entry.sentence).isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(entry.sentence, style: theme.textTheme.bodyLarge),
        ],
        if ((entry.translation ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            entry.translation!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _FamiliarityStep extends StatelessWidget {
  const _FamiliarityStep({
    required this.isLearning,
    required this.busy,
    required this.onSelect,
  });

  final bool isLearning;
  final bool busy;
  final void Function(String choice) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = isLearning
        ? const [
            (
              key: 'unknown',
              label: '不认识',
              hint: '从头学这个单词',
              icon: Icons.help_outline,
            ),
            (
              key: 'known',
              label: '认识',
              hint: '有印象，直接进入学习',
              icon: Icons.lightbulb_outline,
            ),
            (
              key: 'too_easy',
              label: '过于简单',
              hint: '移出生词本，不再学习',
              icon: Icons.done_all,
            ),
          ]
        : const [
            (key: 'forgot', label: '忘记', hint: '完全想不起来', icon: Icons.close),
            (
              key: 'hard',
              label: '模糊',
              hint: '想起来一部分',
              icon: Icons.change_history,
            ),
            (key: 'good', label: '记得', hint: '能想起意思', icon: Icons.check),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isLearning ? '你对这个单词熟悉吗？' : '先回忆一下这个单词',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          '选择后进入词意、选词和拼写检验。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final option in options) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => onSelect(option.key),
              icon: Icon(option.icon),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label),
                    Text(
                      option.hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ChoiceStep extends StatelessWidget {
  const _ChoiceStep({
    required this.title,
    required this.prompt,
    required this.options,
    required this.wrongChoice,
    required this.feedback,
    required this.onSelect,
  });

  final String title;
  final String prompt;
  final List<String> options;
  final String? wrongChoice;
  final String feedback;
  final void Function(String value) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (prompt.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(prompt, style: theme.textTheme.bodyLarge),
          ),
        const SizedBox(height: 16),
        for (final option in options) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                side: wrongChoice == option
                    ? BorderSide(color: theme.colorScheme.error, width: 2)
                    : null,
              ),
              onPressed: () => onSelect(option),
              child: Text(option),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (feedback.isNotEmpty)
          Text(
            feedback,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

class _SpellingStep extends StatelessWidget {
  const _SpellingStep({
    required this.entry,
    required this.controller,
    required this.focusNode,
    required this.feedback,
    required this.onSubmit,
  });

  final VocabEntry entry;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String feedback;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('根据释义和读音拼写单词', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.meaning.isEmpty ? '（没有释义）' : entry.meaning,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              if ((entry.reading ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry.reading!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
              if ((entry.inflection ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  entry.inflection!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '输入单词',
            errorText: feedback.isEmpty ? null : feedback,
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onSubmit, child: const Text('提交')),
        ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.theme,
    required this.checkedIn,
    required this.streak,
    required this.learned,
    required this.reviewed,
    required this.finishing,
  });

  final ThemeData theme;
  final bool checkedIn;
  final int streak;
  final int learned;
  final int reviewed;
  final bool finishing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日任务')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                checkedIn
                    ? Icons.local_fire_department
                    : Icons.check_circle_outline,
                size: 76,
                color: checkedIn
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                checkedIn ? '打卡成功' : '本轮完成',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              if (finishing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                Text(
                  '新学 $learned 个 · 复习 $reviewed 个',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (checkedIn) ...[
                  const SizedBox(height: 12),
                  Text(
                    '连续打卡 $streak 天',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('返回词汇'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
