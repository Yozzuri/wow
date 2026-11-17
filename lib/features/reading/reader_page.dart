import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_settings.dart';
import '../../core/ai/chunk_cache.dart';
import '../../core/ai/phrase_extractor.dart';
import '../../core/ai/segmentation_service.dart';
import '../../core/models/content_document.dart';
import '../../core/reading/reading_book.dart';
import '../../core/reading/reading_translation.dart';
import '../../core/text/tokenizer_settings.dart';
import '../common/interactive_line.dart';
import '../common/sentence_explanation_sheet.dart';
import '../common/word_explanation_sheet.dart';

enum LookupMode { word, sentence, phrase }

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.book});

  final ReadingBook book;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  static const _scrimKey = 'reading_scrim_opacity';

  LookupMode _mode = LookupMode.word;
  int _chapterIndex = 0;
  double _scrimOpacity = 0.7;
  ReadingTranslationController? _translation;
  final ScrollController _scrollController = ScrollController();
  final Map<String, List<ContentPhrase>> _phrases = {};
  final Set<String> _phrasePending = {};
  final Set<String> _phraseFailed = {};
  final Map<String, List<String>> _segmented = {};
  final Set<String> _segmenting = {};
  final Set<String> _segmentFailed = {};

  ReadingBook get _book => widget.book;
  String get _language => _book.language;

  @override
  void initState() {
    super.initState();
    _loadScrim();
    _startTranslation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVisibleSegments();
    });
  }

  @override
  void dispose() {
    _translation?.removeListener(_onTranslationChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadScrim() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_scrimKey);
    if (mounted && value != null) {
      setState(() => _scrimOpacity = value.clamp(0.3, 0.85));
    }
  }

  Future<void> _saveScrim(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrimKey, value);
  }

  Future<void> _startTranslation() async {
    final config = await ref.read(aiConfigProvider.future);
    if (!mounted || !config.isConfigured) {
      return;
    }
    final controller = ReadingTranslationManager.instance.controllerFor(
      _book,
      config,
    );
    _translation?.removeListener(_onTranslationChanged);
    _translation = controller..addListener(_onTranslationChanged);
    if (mounted) {
      setState(() {});
    }
  }

  void _onTranslationChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<ReadingChapter> get _chapters => _book.effectiveChapters;

  ReadingChapter get _chapter =>
      _chapters[_chapterIndex.clamp(0, _chapters.length - 1)];

  List<String> get _paragraphs => _book.content
      .substring(
        _chapter.start.clamp(0, _book.content.length),
        _chapter.end.clamp(0, _book.content.length),
      )
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

  Future<void> _loadSegments(String paragraph) async {
    if (_segmenting.contains(paragraph) ||
        _segmented.containsKey(paragraph) ||
        _segmentFailed.contains(paragraph)) {
      return;
    }
    final config = await ref.read(aiConfigProvider.future);
    if (!mounted || !config.isConfigured) {
      return;
    }
    setState(() => _segmenting.add(paragraph));
    try {
      final words = await const SegmentationService().segment(
        config: config,
        text: paragraph,
        language: _language,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (words.isNotEmpty) {
          _segmented[paragraph] = words;
        } else {
          _segmentFailed.add(paragraph);
        }
        _segmenting.remove(paragraph);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _segmentFailed.add(paragraph);
        _segmenting.remove(paragraph);
      });
    }
  }

  Future<void> _loadVisibleSegments() async {
    if (ref.read(tokenizerModeProvider).mode != TokenizerMode.ai) {
      return;
    }
    final paragraphs = _paragraphs.take(12).toList();
    await runWithConcurrency(
      paragraphs,
      2,
      (paragraph, _) => _loadSegments(paragraph),
    );
  }

  Future<void> _loadPhrases(String paragraph, {bool force = false}) async {
    if (_phrasePending.contains(paragraph)) {
      return;
    }
    if (!force &&
        (_phrases.containsKey(paragraph) || _phraseFailed.contains(paragraph))) {
      return;
    }
    final config = await ref.read(aiConfigProvider.future);
    if (!mounted || !config.isConfigured) {
      return;
    }
    setState(() {
      _phrasePending.add(paragraph);
      _phraseFailed.remove(paragraph);
    });
    try {
      final phrases = await const PhraseExtractor().extract(
        config: config,
        paragraph: paragraph,
        language: _language,
        force: force,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _phrases[paragraph] = phrases;
        _phrasePending.remove(paragraph);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phraseFailed.add(paragraph);
        _phrasePending.remove(paragraph);
      });
    }
  }

  Future<void> _loadVisiblePhrases() async {
    if (_mode != LookupMode.phrase) {
      return;
    }
    final paragraphs = _paragraphs.take(12).toList();
    await runWithConcurrency(
      paragraphs,
      2,
      (paragraph, _) => _loadPhrases(paragraph),
    );
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) {
      return;
    }
    setState(() => _chapterIndex = index);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadVisiblePhrases();
    _loadVisibleSegments();
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

  Widget _buildParagraph(
    String paragraph,
    Color textColor,
    Color secondaryColor,
  ) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.7,
      color: textColor,
    );
    switch (_mode) {
      case LookupMode.word || LookupMode.phrase:
        return InteractiveLine(
          text: paragraph,
          onWordTap: _lookupWord,
          textAlign: TextAlign.left,
          language: _language,
          chunks: ref.read(tokenizerModeProvider).mode == TokenizerMode.ai
              ? _segmented[paragraph]
              : null,
          baseStyle: baseStyle,
          wordStyle: baseStyle?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: textColor,
          ),
        );
      case LookupMode.sentence:
        return Wrap(
          runSpacing: 4,
          children: [
            for (final sentence in _sentenceChunks(paragraph))
              InkWell(
                onTap: () => _lookupSentence(sentence),
                child: Text('$sentence ', style: baseStyle),
              ),
          ],
        );
    }
  }

  Widget _buildPhraseRow(
    String paragraph,
    Color textColor,
    Color secondaryColor,
  ) {
    final theme = Theme.of(context);
    final phrases = _phrases[paragraph];
    if (_phrasePending.contains(paragraph)) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'AI 提取短语中…',
            style: theme.textTheme.bodySmall?.copyWith(color: secondaryColor),
          ),
        ],
      );
    }
    if (phrases == null || phrases.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _loadPhrases(paragraph, force: true),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: Text(
            _phraseFailed.contains(paragraph) ? '重新提取短语' : 'AI 提取短语',
          ),
          style: TextButton.styleFrom(
            foregroundColor: textColor,
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final phrase in phrases)
          ActionChip(
            label: Text(phrase.text),
            tooltip: phrase.meaning ?? phrase.usage,
            onPressed: () =>
                _showPhraseDetails(phrase, paragraph, textColor, secondaryColor),
            visualDensity: VisualDensity.compact,
            backgroundColor: textColor.withValues(alpha: 0.08),
            labelStyle: TextStyle(color: textColor),
            side: BorderSide(color: secondaryColor.withValues(alpha: 0.3)),
          ),
      ],
    );
  }

  Future<void> _showPhraseDetails(
    ContentPhrase phrase,
    String paragraph,
    Color textColor,
    Color secondaryColor,
  ) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(phrase.text, style: theme.textTheme.headlineSmall),
              if ((phrase.example ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('原文：${phrase.example}', style: theme.textTheme.bodyMedium),
              ],
              if ((phrase.meaning ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(phrase.meaning!, style: theme.textTheme.bodyLarge),
              ],
              if ((phrase.usage ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  phrase.usage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryColor,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _lookupPhrase(phrase.example ?? phrase.text, paragraph);
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('查看例句中的词'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showScrimSheet() async {
    var value = _scrimOpacity;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('阅读遮罩', style: Theme.of(context).textTheme.titleMedium),
                Row(
                  children: [
                    const Text('透明度'),
                    Expanded(
                      child: Slider(
                        value: value,
                        min: 0.3,
                        max: 0.85,
                        divisions: 11,
                        label: '${(value * 100).round()}%',
                        onChanged: (next) {
                          setSheetState(() => value = next);
                          setState(() => _scrimOpacity = next);
                        },
                        onChangeEnd: _saveScrim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showChapters() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < _chapters.length; i++)
              ListTile(
                title: Text(_chapters[i].title),
                selected: i == _chapterIndex,
                onTap: () => Navigator.of(context).pop(i),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      _goToChapter(selected);
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.platformBrightnessOf(context);
    final isDark = media == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryColor = textColor.withValues(alpha: 0.6);
    final scrimColor = isDark ? Colors.black : Colors.white;
    final paragraphs = _paragraphs;
    final translation = _translation;
    final theme = Theme.of(context);
    ref.watch(tokenizerModeProvider);
    ref.listen<TokenizerSettings>(tokenizerModeProvider, (previous, next) {
      if (next.mode == TokenizerMode.ai) {
        _loadVisibleSegments();
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(_book.title),
        actions: [
          if (_chapters.length > 1)
            IconButton(
              tooltip: '章节目录',
              onPressed: _showChapters,
              icon: const Icon(Icons.list_alt),
            ),
          IconButton(
            tooltip: '阅读遮罩',
            onPressed: _showScrimSheet,
            icon: const Icon(Icons.contrast),
          ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scrimColor.withValues(alpha: _scrimOpacity)),
          Column(
            children: [
              if (_chapters.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '上一章',
                        onPressed: _chapterIndex == 0
                            ? null
                            : () => _goToChapter(_chapterIndex - 1),
                        icon: Icon(Icons.chevron_left, color: secondaryColor),
                      ),
                      Expanded(
                        child: Text(
                          _chapter.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: secondaryColor,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '下一章',
                        onPressed: _chapterIndex == _chapters.length - 1
                            ? null
                            : () => _goToChapter(_chapterIndex + 1),
                        icon: Icon(Icons.chevron_right, color: secondaryColor),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SelectionArea(
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    itemCount: paragraphs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 18),
                    itemBuilder: (context, index) {
                      final paragraph = paragraphs[index];
                      final translated = translation?.translationFor(paragraph);
                      final pending =
                          translation?.running == true && translated == null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildParagraph(
                            paragraph,
                            textColor,
                            secondaryColor,
                          ),
                          if (translated != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              translated,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondaryColor,
                                height: 1.5,
                              ),
                            ),
                          ] else if (pending) ...[
                            const SizedBox(height: 4),
                            Text(
                              '翻译中…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondaryColor.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                          if (_mode == LookupMode.phrase) ...[
                            const SizedBox(height: 8),
                            _buildPhraseRow(
                              paragraph,
                              textColor,
                              secondaryColor,
                            ),
                          ],
                          if (translation != null &&
                              translation.failed > 0 &&
                              translated == null &&
                              !pending)
                            const SizedBox.shrink(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: scrimColor.withValues(alpha: 0.92),
          child: SegmentedButton<LookupMode>(
            showSelectedIcon: false,
            style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(textColor),
              side: WidgetStatePropertyAll(
                BorderSide(color: secondaryColor.withValues(alpha: 0.4)),
              ),
            ),
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
            onSelectionChanged: (selection) {
              setState(() => _mode = selection.first);
              _loadVisiblePhrases();
            },
          ),
        ),
      ),
    );
  }
}
