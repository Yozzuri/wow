import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/content_document.dart';
import '../../core/text/normalize.dart';
import '../../core/vocab/checkin_store.dart';
import '../../core/vocab/daily_tasks.dart';
import '../../core/vocab/learning_plan.dart';
import '../../core/vocab/vocab_store.dart';
import '../common/word_explanation_sheet.dart';

const int _groupSize = 10;

enum _Phase { groups, done }

class _Group {
  const _Group({required this.entries, required this.isReview});
  final List<VocabEntry> entries;
  final bool isReview;
}

class LearnSessionPage extends ConsumerStatefulWidget {
  const LearnSessionPage({
    super.key,
    required this.newEntries,
    required this.reviewEntries,
    this.pool = const [],
  });

  final List<VocabEntry> newEntries;
  final List<VocabEntry> reviewEntries;
  final List<VocabEntry> pool;

  @override
  ConsumerState<LearnSessionPage> createState() => _LearnSessionPageState();
}

class _LearnSessionPageState extends ConsumerState<LearnSessionPage> {
  late final List<VocabEntry> _pool = _buildPool();
  late final List<_Group> _groups = _buildGroups();
  late final int _totalWords =
      widget.newEntries.length + widget.reviewEntries.length;

  _Phase _mode = _Phase.groups;
  int _groupIndex = 0;
  int _phase = 0;
  List<VocabEntry> _phaseWords = const [];
  int _wordIndex = 0;
  Map<String, int> _states = {};
  final Map<String, int> _mistakes = {};

  int _completedWords = 0;
  int _newCompleted = 0;
  int _reviewCompleted = 0;
  int _removed = 0;
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

  static const _phaseTitles = ['熟悉度', '词意选择', '词意选词', '拼写检验'];

  @override
  void initState() {
    super.initState();
    if (_groups.isEmpty) {
      _mode = _Phase.done;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishAll());
      return;
    }
    _startGroup(0);
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

  List<_Group> _buildGroups() {
    final groups = <_Group>[];
    final newList = [...widget.newEntries];
    for (var i = 0; i < newList.length; i += _groupSize) {
      groups.add(
        _Group(
          entries: newList.sublist(i, min(i + _groupSize, newList.length)),
          isReview: false,
        ),
      );
    }
    final reviewList = [...widget.reviewEntries];
    for (var i = 0; i < reviewList.length; i += _groupSize) {
      groups.add(
        _Group(
          entries: reviewList.sublist(
            i,
            min(i + _groupSize, reviewList.length),
          ),
          isReview: true,
        ),
      );
    }
    return groups;
  }

  _Group get _group => _groups[_groupIndex];
  VocabEntry? get _current =>
      _wordIndex < _phaseWords.length ? _phaseWords[_wordIndex] : null;

  void _startGroup(int index) {
    setState(() {
      _groupIndex = index;
      _phase = _group.isReview ? 1 : 0;
      _states = {
        for (final entry in _group.entries)
          entry.key: _group.isReview
              ? entry.learnState.clamp(1, 3)
              : entry.learnState.clamp(0, 3),
      };
      _mistakes.clear();
      _wordIndex = 0;
      _phaseWords = const [];
      _busy = false;
      _wrongChoice = null;
      _feedback = '';
      _spelling.clear();
    });
    _buildPhaseWords();
  }

  void _buildPhaseWords() {
    final words = _group.entries
        .where((entry) => _states[entry.key] == _phase)
        .toList();
    if (words.isEmpty) {
      _advancePhase();
      return;
    }
    setState(() {
      _phaseWords = words;
      _wordIndex = 0;
      _busy = false;
      _wrongChoice = null;
      _feedback = '';
      _spelling.clear();
    });
    _prepareWord();
  }

  void _advancePhase() {
    var next = _phase + 1;
    while (next <= 3 &&
        !_group.entries.any((entry) => _states[entry.key] == next)) {
      next++;
    }
    if (next > 3) {
      _nextGroup();
      return;
    }
    setState(() => _phase = next);
    _buildPhaseWords();
  }

  void _advanceWord() {
    if (_wordIndex + 1 < _phaseWords.length) {
      setState(() {
        _wordIndex++;
        _busy = false;
        _wrongChoice = null;
        _feedback = '';
        _spelling.clear();
      });
      _prepareWord();
      return;
    }
    _buildPhaseWords();
  }

  void _nextGroup() {
    if (_groupIndex + 1 < _groups.length) {
      _startGroup(_groupIndex + 1);
    } else {
      _finishAll();
    }
  }

  void _prepareWord() {
    final entry = _current;
    if (entry == null) return;
    _meaningOptions = _buildMeaningOptions(entry);
    _wordOptions = _buildWordOptions(entry);
    setState(() {});
  }

  Future<void> _onFamiliarity(String choice) async {
    final entry = _current;
    if (entry == null || _busy) return;
    setState(() => _busy = true);
    if (choice == 'too_easy') {
      await ref.read(vocabStoreProvider).remove(entry);
      if (!mounted) return;
      _states[entry.key] = -1;
      _removed++;
      _completedWords++;
      setState(() => _busy = false);
      _advanceWord();
      return;
    }
    final known = choice == 'known';
    final next = ((_states[entry.key] ?? 0) + (known ? 1 : -1)).clamp(0, 3);
    await ref.read(vocabStoreProvider).updateLearnState(entry, next);
    if (!mounted) return;
    _states[entry.key] = next;
    setState(() => _busy = false);
    if (!known) {
      await _showAnalysis(entry);
      if (!mounted) return;
    }
    _advanceWord();
  }

  Future<void> _onChoice(String value, String correct) async {
    final entry = _current;
    if (entry == null || _busy) return;
    if (normalizeForMatch(value) == normalizeForMatch(correct)) {
      await _advanceState(entry);
      return;
    }
    _mistakes[entry.key] = (_mistakes[entry.key] ?? 0) + 1;
    setState(() {
      _wrongChoice = value;
      _feedback = '答错了，看完解析再试一次';
    });
    await _showAnalysis(entry);
  }

  Future<void> _onSpelling(String correct) async {
    final entry = _current;
    if (entry == null || _busy) return;
    final answer = normalizeForMatch(_spelling.text);
    if (answer.isNotEmpty &&
        (answer == normalizeForMatch(correct) ||
            answer == normalizeForMatch(entry.word))) {
      await _advanceState(entry);
      return;
    }
    _mistakes[entry.key] = (_mistakes[entry.key] ?? 0) + 1;
    setState(() => _feedback = '拼写不正确，再试一次');
    _spelling.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _spelling.text.length,
    );
    _spellingFocus.requestFocus();
    await _showAnalysis(entry);
  }

  Future<void> _onForgot() async {
    final entry = _current;
    if (entry == null || _busy) return;
    _mistakes[entry.key] = (_mistakes[entry.key] ?? 0) + 1;
    await _showAnalysis(entry);
  }

  Future<void> _advanceState(VocabEntry entry) async {
    final next = (_states[entry.key] ?? 0) + 1;
    if (next >= 4) {
      await _completeWord(entry);
      return;
    }
    setState(() => _busy = true);
    await ref.read(vocabStoreProvider).updateLearnState(entry, next);
    if (!mounted) return;
    _states[entry.key] = next;
    setState(() => _busy = false);
    _advanceWord();
  }

  Future<void> _completeWord(VocabEntry entry) async {
    setState(() => _busy = true);
    final store = ref.read(vocabStoreProvider);
    if (entry.isNew) {
      await store.markLearned(entry);
      _newCompleted++;
    } else {
      await store.review(entry, _gradeFor(entry));
      _reviewCompleted++;
    }
    _states[entry.key] = 4;
    _completedWords++;
    if (!mounted) return;
    setState(() => _busy = false);
    _advanceWord();
  }

  ReviewGrade _gradeFor(VocabEntry entry) {
    final mistakes = _mistakes[entry.key] ?? 0;
    if (mistakes >= 2) return ReviewGrade.forgot;
    if (mistakes == 1) return ReviewGrade.hard;
    return ReviewGrade.good;
  }

  Future<void> _showAnalysis(VocabEntry entry) async {
    await showWordExplanation(
      context,
      word: entry.word.trim().isEmpty ? entry.lemma : entry.word,
      sentence: entry.sentence,
      language: entry.language,
      token: ContentToken(
        surface: entry.word,
        lemma: entry.lemma,
        pos: entry.pos,
        meaning: entry.meaning,
      ),
      sourceTitle: entry.sourceTitle,
    );
  }

  List<String> _buildMeaningOptions(VocabEntry entry) {
    final target = entry.meaning.trim();
    if (target.isEmpty) return const [];
    final targetKey = normalizeForMatch(target);
    final pool = <String>{};
    for (final item in _pool) {
      final meaning = item.meaning.trim();
      if (meaning.isEmpty) continue;
      if (normalizeForMatch(meaning) == targetKey) continue;
      pool.add(meaning);
    }
    final random = Random(entry.key.hashCode);
    final distractors = pool.toList()..shuffle(random);
    return [target, ...distractors.take(3)]..shuffle(random);
  }

  List<String> _buildWordOptions(VocabEntry entry) {
    final target = entry.lemma.trim();
    if (target.isEmpty) return const [];
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
    if (a.isNotEmpty && b.isNotEmpty && a[0] == b[0]) score -= 0.4;
    return score;
  }

  int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
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

  Future<void> _finishAll() async {
    if (_mode != _Phase.done) {
      setState(() {
        _mode = _Phase.done;
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
    if (!mounted) return;
    setState(() {
      _checkedIn = checkedIn;
      _streak = streak;
      _finishing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_mode == _Phase.done) {
      return _DoneView(
        theme: theme,
        checkedIn: _checkedIn,
        streak: _streak,
        learned: _newCompleted,
        reviewed: _reviewCompleted,
        removed: _removed,
        finishing: _finishing,
      );
    }
    final entry = _current;
    if (entry == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '第 ${_groupIndex + 1}/${_groups.length} 组 · '
          '${_group.isReview ? '复习' : '新学'}',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: _totalWords == 0
                    ? 0
                    : (_completedWords / _totalWords).clamp(0.0, 1.0),
                minHeight: 4,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Text(
                      _phaseTitles[_phase],
                      style: theme.textTheme.labelLarge,
                    ),
                    const Spacer(),
                    Text(
                      '${_wordIndex + 1}/${_phaseWords.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (_phase <= 1)
              _WordHeader(entry: entry)
            else
              Text(
                _phase == 2 ? '看释义选单词' : '看释义拼写单词',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 20),
            if (_phase == 0)
              _FamiliarityStep(busy: _busy, onSelect: _onFamiliarity)
            else if (_phase == 1)
              _meaningOptions.length < 2
                  ? _MissingDataStep(
                      message: '这个词条缺少可选释义，跳过词意选择。',
                      onSkip: () => _advanceState(entry),
                    )
                  : _ChoiceStep(
                      title: '选出最符合句意的释义',
                      prompt: '',
                      options: _meaningOptions,
                      wrongChoice: _wrongChoice,
                      feedback: _feedback,
                      onSelect: (value) => _onChoice(value, entry.meaning),
                    )
            else if (_phase == 2)
              _wordOptions.length < 2
                  ? _MissingDataStep(
                      message: '词库里缺少同语言的相近单词，跳过选词。',
                      onSkip: () => _advanceState(entry),
                    )
                  : _ChoiceStep(
                      title: '选出与该释义对应的单词',
                      prompt: entry.meaning,
                      options: _wordOptions,
                      wrongChoice: _wrongChoice,
                      feedback: _feedback,
                      onSelect: (value) => _onChoice(value, entry.lemma),
                    )
            else
              _SpellingStep(
                entry: entry,
                controller: _spelling,
                focusNode: _spellingFocus,
                feedback: _feedback,
                onSubmit: () => _onSpelling(entry.lemma),
                onForgot: _onForgot,
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
        if (entry.sentence.isNotEmpty) ...[
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
  const _FamiliarityStep({required this.busy, required this.onSelect});

  final bool busy;
  final void Function(String choice) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const options = [
      (
        key: 'unknown',
        label: '不认识',
        hint: '状态 -1，稍后再测',
        icon: Icons.help_outline,
      ),
      (key: 'fuzzy', label: '模糊', hint: '状态 -1，稍后再测', icon: Icons.blur_on),
      (
        key: 'known',
        label: '认识',
        hint: '状态 +1，进入词意选择',
        icon: Icons.lightbulb_outline,
      ),
      (
        key: 'too_easy',
        label: '过于简单',
        hint: '移出生词本，不再学习',
        icon: Icons.done_all,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('你对这个单词熟悉吗？', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '本组 10 个词会先统一过熟悉度，全部达到下一状态后再进入词意选择。',
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

class _MissingDataStep extends StatelessWidget {
  const _MissingDataStep({required this.message, required this.onSkip});

  final String message;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onSkip, child: const Text('跳过这一步')),
        ),
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
    required this.onForgot,
  });

  final VocabEntry entry;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String feedback;
  final VoidCallback onSubmit;
  final VoidCallback onForgot;

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
        Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: onSubmit, child: const Text('提交')),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: onForgot, child: const Text('不记得')),
          ],
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
    required this.removed,
    required this.finishing,
  });

  final ThemeData theme;
  final bool checkedIn;
  final int streak;
  final int learned;
  final int reviewed;
  final int removed;
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
                  '新学 $learned 个 · 复习 $reviewed 个'
                  '${removed > 0 ? ' · 移出 $removed 个' : ''}',
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
