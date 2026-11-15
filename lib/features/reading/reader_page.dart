import 'package:flutter/material.dart';

import '../../core/models/content_document.dart';
import '../../core/reading/reading_book.dart';
import '../../core/text/tokenizer.dart';
import '../common/interactive_line.dart';
import '../common/sentence_explanation_sheet.dart';
import '../common/word_explanation_sheet.dart';

enum LookupMode { word, sentence, phrase }

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.book});

  final ReadingBook book;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  LookupMode _mode = LookupMode.word;

  String get _language => widget.book.language;

  List<String> get _paragraphs => widget.book.content
      .split(RegExp(r'\n+'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();

  void _lookupWord(String word, String sentence) {
    showWordExplanation(
      context,
      word: word,
      sentence: sentence,
      language: _language,
    );
  }

  void _lookupSentence(String sentence) {
    showSentenceExplanation(context, sentence: sentence, language: _language);
  }

  void _lookupPhrase(String phrase, String sentence) {
    showWordExplanation(
      context,
      word: phrase,
      sentence: sentence,
      language: _language,
      token: ContentToken(
        surface: phrase,
        lemma: phrase,
        pos: 'phrase',
      ),
    );
  }

  List<String> _sentenceChunks(String paragraph) {
    final chunks = paragraph
        .split(RegExp(r'(?<=[.!?。！？])\s*'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();
    return chunks.isEmpty ? [paragraph] : chunks;
  }

  List<String> _phraseChunks(String paragraph) {
    final chunks = paragraph
        .split(RegExp(r'(?<=[,;:，；：])\s*'))
        .map((phrase) => phrase.trim())
        .where((phrase) => phrase.isNotEmpty)
        .toList();
    if (chunks.length > 1) {
      return chunks;
    }
    final tokens = tokenizeLine(paragraph);
    if (tokens.isEmpty) {
      return [paragraph];
    }
    final result = <String>[];
    final buffer = StringBuffer();
    var wordCount = 0;
    for (final token in tokens) {
      buffer.write(token);
      if (isWordToken(token)) {
        wordCount++;
      }
      if (wordCount >= 3) {
        result.add(buffer.toString().trim());
        buffer.clear();
        wordCount = 0;
      }
    }
    if (buffer.toString().trim().isNotEmpty) {
      result.add(buffer.toString().trim());
    }
    return result.isEmpty ? [paragraph] : result;
  }

  Widget _buildParagraph(String paragraph) {
    final theme = Theme.of(context);
    switch (_mode) {
      case LookupMode.word:
        return InteractiveLine(
          text: paragraph,
          onWordTap: _lookupWord,
          textAlign: TextAlign.left,
          language: _language,
          baseStyle: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
          wordStyle: theme.textTheme.bodyLarge?.copyWith(
            height: 1.7,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: theme.colorScheme.primary,
          ),
        );
      case LookupMode.sentence:
        return Wrap(
          runSpacing: 4,
          children: [
            for (final sentence in _sentenceChunks(paragraph))
              InkWell(
                onTap: () => _lookupSentence(sentence),
                child: Text(
                  '$sentence ',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                ),
              ),
          ],
        );
      case LookupMode.phrase:
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final phrase in _phraseChunks(paragraph))
              ActionChip(
                label: Text(phrase.replaceAll('\n', ' ')),
                onPressed: () => _lookupPhrase(phrase, paragraph),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paragraphs = _paragraphs;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                label: Text(readingLanguageFor(_language).label),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: SelectionArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          itemCount: paragraphs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 18),
          itemBuilder: (context, index) => _buildParagraph(paragraphs[index]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.colorScheme.surface.withValues(alpha: 0.9),
          child: SegmentedButton<LookupMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: LookupMode.word,
                icon: Icon(Icons.text_fields),
                label: Text('点词'),
              ),
              ButtonSegment(
                value: LookupMode.sentence,
                icon: Icon(Icons.short_text),
                label: Text('点句'),
              ),
              ButtonSegment(
                value: LookupMode.phrase,
                icon: Icon(Icons.sell_outlined),
                label: Text('点短语'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
          ),
        ),
      ),
    );
  }
}
