import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/text/tokenizer.dart';

class InteractiveLine extends StatefulWidget {
  const InteractiveLine({
    super.key,
    required this.text,
    required this.onWordTap,
    this.translation,
    this.baseStyle,
    this.wordStyle,
    this.translationStyle,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final String? translation;
  final void Function(String word, String sentence) onWordTap;
  final TextStyle? baseStyle;
  final TextStyle? wordStyle;
  final TextStyle? translationStyle;
  final TextAlign textAlign;

  @override
  State<InteractiveLine> createState() => _InteractiveLineState();
}

class _InteractiveLineState extends State<InteractiveLine> {
  final List<TapGestureRecognizer> _recognizers = [];
  String? _cachedText;
  List<InlineSpan> _spans = const [];

  static const TextStyle defaultBaseStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    height: 1.35,
    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
  );

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _ensureSpans(TextStyle baseStyle, TextStyle wordStyle) {
    if (_cachedText == widget.text) {
      return;
    }
    _cachedText = widget.text;
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    for (final token in tokenizeLine(widget.text)) {
      if (isWordToken(token)) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onWordTap(token, widget.text);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(text: token, style: wordStyle, recognizer: recognizer),
        );
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }
    }
    _spans = spans;
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.baseStyle ?? defaultBaseStyle;
    final wordStyle =
        widget.wordStyle ??
        baseStyle.copyWith(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFFFFD166),
          decorationStyle: TextDecorationStyle.dotted,
        );
    _ensureSpans(baseStyle, wordStyle);
    final translation = widget.translation;
    final translationStyle =
        widget.translationStyle ??
        const TextStyle(color: Color(0xFFE6E6E6), fontSize: 14, height: 1.3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: widget.textAlign,
          text: TextSpan(children: _spans),
        ),
        if (translation != null && translation.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            translation,
            textAlign: widget.textAlign,
            style: translationStyle,
          ),
        ],
      ],
    );
  }
}
