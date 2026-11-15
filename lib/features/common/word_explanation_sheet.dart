import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';
import '../../core/models/content_document.dart';
import '../../core/vocab/vocab_store.dart';

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
  String? _result;
  String? _error;
  late bool _loading;

  ContentToken? get _token => widget.token;

  bool get _hasLocalMeaning => (_token?.meaning ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loading = !_hasLocalMeaning;
    if (!_hasLocalMeaning) {
      _explain();
    }
  }

  Future<void> _explain() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final config = await ref.read(aiConfigProvider.future);
      if (!config.isConfigured) {
        if (mounted) {
          setState(() {
            _error = '尚未配置 AI 接口，请到「设置」页填写 Base URL、模型和 API Key。';
            _loading = false;
          });
        }
        return;
      }
      final result = await AiClient(config).explainWord(
        word: widget.word,
        sentence: widget.sentence,
        language: widget.language,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _addToVocab() async {
    final token = _token;
    final added = await ref
        .read(vocabStoreProvider)
        .addToken(
          word: token?.surface ?? widget.word,
          lemma: token?.lemma,
          pos: token?.pos,
          meaning: token?.meaning,
          sentence: widget.sentence,
          language: widget.language,
          sourceTitle: widget.sourceTitle ?? '',
        );
    if (!mounted) {
      return;
    }
    if (added) {
      ref.read(vocabVersionProvider.notifier).state++;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? '已加入生词本' : '这个单词已经在生词本里了')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final token = _token;
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
                  if ((token?.pos ?? '').isNotEmpty)
                    Chip(
                      label: Text(token!.pos!),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if ((token?.lemma ?? '').isNotEmpty &&
                  token!.lemma != widget.word.toLowerCase())
                Text(
                  '原形：${token.lemma}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                widget.sentence,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (_hasLocalMeaning) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    token!.meaning!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
              else if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else if (_result != null)
                SelectableText(
                  _result!,
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_result == null && !_loading)
                    TextButton.icon(
                      onPressed: _explain,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('AI 详解'),
                    ),
                  if (token != null && _hasLocalMeaning)
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

void showWordExplanation(
  BuildContext context, {
  required String word,
  required String sentence,
  required String language,
  ContentToken? token,
  String? sourceTitle,
}) {
  showModalBottomSheet<void>(
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
