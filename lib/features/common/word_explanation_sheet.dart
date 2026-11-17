import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_settings.dart';
import '../../core/ai/word_analysis.dart';
import '../../core/models/content_document.dart';
import '../../core/vocab/vocab_store.dart';
import 'ai_markdown.dart';

class WordExplanationSheet extends ConsumerStatefulWidget {
  const WordExplanationSheet({
    super.key,
    required this.word,
    required this.sentence,
    required this.language,
    this.token,
    this.sourceTitle,
  });

  final String word;
  final String sentence;
  final String language;
  final ContentToken? token;
  final String? sourceTitle;

  @override
  ConsumerState<WordExplanationSheet> createState() =>
      _WordExplanationSheetState();
}

class _WordExplanationSheetState extends ConsumerState<WordExplanationSheet> {
  WordAnalysis? _analysis;
  String? _error;
  bool _loading = true;
  int _requestId = 0;

  ContentToken? get _token => widget.token;

  WordAnalysis _localFallback() {
    final hint = (_token?.lemma ?? '').trim();
    final lemma = hint.isEmpty ? widget.word : hint;
    final changed = lemma != widget.word;
    final pos = (_token?.pos ?? '').trim();
    final meaning = (_token?.meaning ?? '').trim();
    return WordAnalysis(
      surface: widget.word,
      lemma: lemma,
      kind: changed ? WordFormKind.inflected : WordFormKind.lemma,
      inflectionChanged: changed,
      inflectionSummary: changed ? '${widget.word} → $lemma' : '',
      lemmaSentence: changed
          ? widget.sentence.replaceFirst(widget.word, lemma)
          : widget.sentence,
      senses: meaning.isEmpty
          ? const []
          : [WordSense(pos: pos, meaning: meaning)],
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final requestId = ++_requestId;
    try {
      final config = await ref.read(aiConfigProvider.future);
      if (!config.isConfigured) {
        if (mounted && requestId == _requestId) {
          setState(() {
            _analysis = _localFallback();
            _error = '尚未配置 AI 接口，显示本地词典信息。';
            _loading = false;
          });
        }
        return;
      }
      final result = await const WordAnalyzer().analyze(
        config: config,
        word: widget.word,
        sentence: widget.sentence,
        language: widget.language,
        lemmaHint: _analysis?.lemma ?? _token?.lemma,
        force: force,
      );
      if (mounted && requestId == _requestId) {
        setState(() {
          _analysis = result;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _analysis = _localFallback();
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _addToVocab() async {
    final analysis = _analysis ?? _localFallback();
    final added = await ref
        .read(vocabStoreProvider)
        .addToken(
          word: analysis.surface,
          lemma: analysis.lemma,
          pos: analysis.pos,
          meaning: analysis.meaningSummary.isNotEmpty
              ? analysis.meaningSummary
              : _token?.meaning,
          sentence: widget.sentence,
          reading: analysis.reading,
          inflection: analysis.isInflected
              ? analysis.inflectionMarkdown
              : analysis.isIndependent
              ? analysis.relation
              : null,
          lemmaSentence: analysis.lemmaSentence,
          language: widget.language,
          sourceTitle: widget.sourceTitle ?? '',
        );
    if (!mounted) return;
    if (added) {
      ref.read(vocabVersionProvider.notifier).state++;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(added ? '已加入生词本' : '这个单词已经在生词本里了')));
  }

  String _kindLabel(WordFormKind kind) => switch (kind) {
    WordFormKind.lemma => '原型',
    WordFormKind.inflected => '变形',
    WordFormKind.independent => '独立派生词',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = _analysis;
    final lemma = analysis?.lemma ?? _token?.lemma ?? widget.word;
    final reading = analysis?.reading ?? '';
    final senses = analysis?.senses ?? const <WordSense>[];
    final forms = analysis?.forms ?? const <WordFormInfo>[];
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      widget.word,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  if (analysis != null)
                    Chip(
                      label: Text(_kindLabel(analysis.kind)),
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    tooltip: '重新生成并缓存',
                    onPressed: _loading ? null : () => _load(force: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Text(
                '原型：$lemma${reading.isEmpty ? '' : ' · 读音：$reading'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((analysis?.relation ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(analysis!.relation),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                analysis?.lemmaSentence ?? widget.sentence,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('AI 解析中…'),
                  ],
                )
              else ...[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (senses.isNotEmpty) ...[
                  Text('释义', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  for (final sense in senses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (sense.pos.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                sense.pos,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              sense.meaning,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                if ((analysis?.usage ?? '').isNotEmpty) ...[
                  Text('用法', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  AiMarkdown(data: analysis!.usage),
                  const SizedBox(height: 12),
                ],
                if ((analysis?.examples ?? const []).isNotEmpty) ...[
                  Text('例句', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  AiMarkdown(
                    data: analysis!.examples
                        .map((example) => '- $example')
                        .join('\n'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (forms.isNotEmpty) ...[
                  Text('词形变化', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final form in forms)
                        Chip(
                          label: Text(
                            form.label.isEmpty
                                ? form.value
                                : '${form.label} ${form.value}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (analysis != null &&
                    analysis.inflectionMarkdown.isNotEmpty) ...[
                  AiMarkdown(data: analysis.inflectionMarkdown),
                  const SizedBox(height: 12),
                ],
                if ((analysis?.detailMarkdown ?? '').isNotEmpty)
                  AiMarkdown(data: analysis!.detailMarkdown),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_error != null && !_loading)
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('AI 详解'),
                    ),
                  if (analysis != null)
                    FilledButton.tonalIcon(
                      onPressed: _addToVocab,
                      icon: const Icon(Icons.add),
                      label: const Text('加入生词本'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showWordExplanation(
  BuildContext context, {
  required String word,
  required String sentence,
  required String language,
  ContentToken? token,
  String? sourceTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => WordExplanationSheet(
      word: word,
      sentence: sentence,
      language: language,
      token: token,
      sourceTitle: sourceTitle,
    ),
  );
}
