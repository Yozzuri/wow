import 'package:flutter/material.dart';

import '../../core/text/tokenizer.dart';

class InteractiveLine extends StatelessWidget {
  const InteractiveLine({
    super.key,
    required this.text,
    required this.onWordTap,
    this.translation,
    this.baseStyle,
    this.wordStyle,
    this.translationStyle,
    this.textAlign = TextAlign.center,
    this.language = 'en',
  });

  final String text;
  final String? translation;
  final void Function(String word, String sentence) onWordTap;
  final TextStyle? baseStyle;
  final TextStyle? wordStyle;
  final TextStyle? translationStyle;
  final TextAlign textAlign;
  final String language;

  static const TextStyle defaultBaseStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    height: 1.35,
    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
  );

  @override
  Widget build(BuildContext context) {
    final base = baseStyle ?? defaultBaseStyle;
    final word = wordStyle ?? base.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFFFFD166),
      decorationStyle: TextDecorationStyle.dotted,
    );
    final translationTextStyle = translationStyle ??
        const TextStyle(color: Color(0xFFE6E6E6), fontSize: 14, height: 1.3);
    final alignment = switch (textAlign) {
      TextAlign.left || TextAlign.start => WrapAlignment.start,
      TextAlign.right || TextAlign.end => WrapAlignment.end,
      _ => WrapAlignment.center,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: alignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final chunk in textChunks(text, language: language))
              if (chunk.word == null)
                Text(chunk.text, style: base)
              else
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onWordTap(chunk.word!, text),
                  child: Text(chunk.text, style: word),
                ),
          ],
        ),
        if (translation != null && translation!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            translation!,
            textAlign: textAlign,
            style: translationTextStyle,
          ),
        ],
      ],
    );
  }
}
