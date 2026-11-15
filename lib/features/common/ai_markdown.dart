import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AiMarkdown extends StatelessWidget {
  const AiMarkdown({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    final style = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 6),
      strong: base?.copyWith(fontWeight: FontWeight.w700),
      em: base?.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      listIndent: 18,
      h1: theme.textTheme.titleLarge,
      h2: theme.textTheme.titleMedium,
      h3: theme.textTheme.titleSmall,
      code: base?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      blockSpacing: 8,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: style,
    );
  }
}
