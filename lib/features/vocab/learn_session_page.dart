import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vocab/vocab_store.dart';

class LearnSessionPage extends ConsumerStatefulWidget {
  const LearnSessionPage({super.key, required this.entries});

  final List<VocabEntry> entries;

  @override
  ConsumerState<LearnSessionPage> createState() => _LearnSessionPageState();
}

class _LearnSessionPageState extends ConsumerState<LearnSessionPage> {
  late final List<VocabEntry> _queue = [...widget.entries];
  int _index = 0;
  bool _revealed = false;
  bool _saving = false;

  VocabEntry get _current => _queue[_index];

  Future<void> _rate(ReviewGrade grade) async {
    setState(() => _saving = true);
    await ref.read(vocabStoreProvider).review(_current, grade);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _revealed = false;
      _index++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = _index >= _queue.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(finished ? '学习完成' : '学习 ${_index + 1}/${_queue.length}'),
      ),
      body: finished
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text('本轮学习完成', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '共复习 ${_queue.length} 个词条',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                LinearProgressIndicator(
                  value: (_index + 1) / _queue.length,
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _current.lemma,
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    if ((_current.pos ?? '').isNotEmpty)
                      Chip(
                        label: Text(_current.pos!),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _current.sentence,
                  style: theme.textTheme.bodyLarge,
                ),
                if ((_current.sourceTitle).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '来自：${_current.sourceTitle}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                if (!_revealed)
                  FilledButton(
                    onPressed: () => setState(() => _revealed = true),
                    child: const Text('显示释义'),
                  )
                else ...[
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
                          _current.meaning.isEmpty
                              ? '（没有释义）'
                              : _current.meaning,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        if ((_current.translation ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _current.translation!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
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
    );
  }
}
