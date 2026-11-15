import 'package:flutter/material.dart';

import '../../core/models/content_document.dart';

class SegmentNotes extends StatelessWidget {
  const SegmentNotes({
    super.key,
    required this.segment,
    required this.onPhraseTap,
    this.textColor,
    this.chipColor,
  });

  final ContentSegment segment;
  final void Function(ContentPhrase phrase) onPhraseTap;
  final Color? textColor;
  final Color? chipColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = textColor ?? theme.colorScheme.onSurfaceVariant;
    if (segment.grammar.isEmpty && segment.phrases.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final note in segment.grammar)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '语法：${note.pattern} — ${note.explanation}',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        if (segment.phrases.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final phrase in segment.phrases)
                ActionChip(
                  label: Text(phrase.text),
                  tooltip: phrase.meaning ?? phrase.usage,
                  onPressed: () => onPhraseTap(phrase),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: chipColor,
                ),
            ],
          ),
      ],
    );
  }
}
