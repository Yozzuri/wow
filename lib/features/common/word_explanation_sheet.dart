import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';

class WordExplanationSheet extends ConsumerStatefulWidget {
  const WordExplanationSheet({
    super.key,
    required this.word,
    required this.sentence,
    required this.language,
  });

  final String word;
  final String sentence;
  final String language;

  @override
  ConsumerState<WordExplanationSheet> createState() =>
      _WordExplanationSheetState();
}

class _WordExplanationSheetState extends ConsumerState<WordExplanationSheet> {
  String? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _explain();
  }

  Future<void> _explain() async {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text(widget.word, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              widget.sentence,
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
            else if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else
              SelectableText(_result ?? '', style: theme.textTheme.bodyMedium),
          ],
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
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => WordExplanationSheet(
      word: word,
      sentence: sentence,
      language: language,
    ),
  );
}
