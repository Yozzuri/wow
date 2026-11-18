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
    this.language = 'en',
    this.chunks,
  });

  final String text;
  final String? translation;
  final void Function(String word, String sentence) onWordTap;
  final TextStyle? baseStyle;
  final TextStyle? wordStyle;
  final TextStyle? translationStyle;
  final TextAlign textAlign;
  final String language;

  /// Optional pre-segmented chunks, for example from AI segmentation.
  final List<String>? chunks;

  static const TextStyle defaultBaseStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    height: 1.35,
    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
  );

  @override
  State<InteractiveLine> createState() => _InteractiveLineState();
}

class _InteractiveLineState extends State<InteractiveLine> {
  final List<TapGestureRecognizer> _recognizers = [];

  static final RegExp _wordPattern = RegExp(
    r'[A-Za-z\u00C0-\u024F\u0370-\u04FF\u1E00-\u1EFF'
    r'\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF'
    r'\u0E00-\u0E7F\u0600-\u06FF\uAC00-\uD7AF\u1100-\u11FF]+',
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

  String _wordFromChunk(String chunk) {
    final match = _wordPattern.firstMatch(chunk);
    return match?.group(0) ?? chunk.trim();
  }

  /// AI chunks may omit the original spacing. Walk the source text so any
  /// skipped characters (spaces, punctuation) are emitted as plain spans.
  List<TextChunk>? _chunksFromCustom(List<String> parts) {
    final text = widget.text;
    final result = <TextChunk>[];
    var cursor = 0;
    var matched = 0;
    for (final part in parts) {
      if (part.isEmpty) {
        continue;
      }
      final index = text.indexOf(part, cursor);
      if (index < 0) {
        continue;
      }
      if (index > cursor) {
        result.add(TextChunk(text.substring(cursor, index), null));
      }
      result.add(
        hasWordContent(part)
            ? TextChunk(part, _wordFromChunk(part))
            : TextChunk(part, null),
      );
      cursor = index + part.length;
      matched++;
    }
    if (matched == 0) {
      return null;
    }
    if (cursor < text.length) {
      result.add(TextChunk(text.substring(cursor), null));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseStyle ?? InteractiveLine.defaultBaseStyle;
    final word = widget.wordStyle ??
        base.copyWith(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFFFFD166),
          decorationStyle: TextDecorationStyle.dotted,
        );
    final translationTextStyle = widget.translationStyle ??
        const TextStyle(color: Color(0xFFE6E6E6), fontSize: 14, height: 1.3);

    final custom = widget.chunks == null
        ? null
        : _chunksFromCustom(widget.chunks!);
    final displayChunks = custom ??
        (widget.chunks == null
            ? textChunks(widget.text, language: widget.language)
            : [
                for (final chunk in widget.chunks!)
                  hasWordContent(chunk)
                      ? TextChunk(chunk, _wordFromChunk(chunk))
                      : TextChunk(chunk, null),
              ]);

    _disposeRecognizers();
    final spans = <InlineSpan>[];
    for (final chunk in displayChunks) {
      if (chunk.word == null) {
        spans.add(TextSpan(text: chunk.text, style: base));
        continue;
      }
      final wordText = chunk.word!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onWordTap(wordText, widget.text);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: chunk.text, style: word, recognizer: recognizer),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A single rich paragraph keeps the original spaces and wraps
        // naturally instead of laying every chunk out as its own widget.
        Text.rich(
          TextSpan(children: spans),
          textAlign: widget.textAlign,
        ),
        if (widget.translation != null && widget.translation!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.translation!,
            textAlign: widget.textAlign,
            style: translationTextStyle,
          ),
        ],
      ],
    );
  }
}
