import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';
import 'ai_markdown.dart';

class SentenceExplanationSheet extends ConsumerStatefulWidget {
  const SentenceExplanationSheet({
    super.key,
    required this.sentence,
    required this.language,
  });

  final String sentence;
  final String language;

  @override
  ConsumerState<SentenceExplanationSheet> createState() =>
      _SentenceExplanationSheetState();
}

class _SentenceExplanationSheetState
    extends ConsumerState<SentenceExplanationSheet> {
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
      final result = await AiClient(config).explainSentence(
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('句子解析', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                widget.sentence,
                style: theme.textTheme.bodyMedium?.copyWith(
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
                AiMarkdown(data: _result ?? ''),
            ],
          ),
        ),
      ),
    );
  }
}

void showSentenceExplanation(
  BuildContext context, {
  required String sentence,
  required String language,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) =>
        SentenceExplanationSheet(sentence: sentence, language: language),
  );
}
