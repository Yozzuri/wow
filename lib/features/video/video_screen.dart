import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:video_player/video_player.dart';

import '../../core/ai/ai_settings.dart';
import '../../core/ai/subtitle_analyzer.dart';
import '../../core/models/content_document.dart';
import '../../core/storage/content_store.dart';
import '../../core/subtitle/subtitle_parser.dart';
import '../../core/vocab/vocab_store.dart';
import '../common/interactive_line.dart';
import '../common/word_explanation_sheet.dart';

class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({super.key});

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  VideoPlayerController? _controller;
  ContentDocument? _document;
  String? _videoName;
  String? _subtitleName;
  bool _busy = false;
  bool _analyzing = false;
  double _speed = 1.0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    final file = (result != null && result.files.isNotEmpty)
        ? result.files.first
        : null;
    if (file == null || file.path == null) {
      return;
    }
    setState(() => _busy = true);
    VideoPlayerController? next;
    try {
      next = VideoPlayerController.file(File(file.path!));
      await next.initialize();
      await _controller?.dispose();
      await next.setLooping(false);
      await next.setPlaybackSpeed(_speed);
      await next.play();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _videoName = file.name;
        _document = null;
        _subtitleName = null;
      });
    } catch (error) {
      await next?.dispose();
      if (mounted) {
        _showMessage('无法播放该视频：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickSubtitle() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa', 'lrc', 'txt'],
      withData: true,
    );
    final file = (result != null && result.files.isNotEmpty)
        ? result.files.first
        : null;
    if (file == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final raw = String.fromCharCodes(bytes);
      final text = _decodeUtf8(bytes, fallback: raw);
      final parsed = SubtitleParser.parse(text, fileName: file.name);
      if (parsed.segments.isEmpty) {
        _showMessage('没有解析到字幕内容');
        return;
      }
      final title = _stripExtension(_videoName ?? '未命名视频');
      final document = ContentDocument(
        meta: ContentMeta(
          title: title,
          source: _videoName,
          language: 'en',
          durationMs: _controller?.value.duration.inMilliseconds,
        ),
        segments: parsed.segments,
      );
      setState(() {
        _document = document;
        _subtitleName = '${file.name} · ${parsed.format.toUpperCase()}';
      });
      final cached = await const ContentStore().loadAnalysis(document);
      if (cached != null && mounted) {
        setState(() => _document = cached);
        _showMessage('已载入 ${cached.segments.length} 条字幕（含 AI 解析缓存）');
      } else {
        _showMessage('已载入 ${parsed.segments.length} 条字幕');
      }
    } catch (error) {
      _showMessage('字幕解析失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  static String _decodeUtf8(List<int> bytes, {required String fallback}) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (_) {
      return fallback;
    }
  }

  static String _stripExtension(String name) {
    final index = name.lastIndexOf('.');
    return index > 0 ? name.substring(0, index) : name;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  ContentToken? _tokenFor(String word, String sentence) {
    final document = _document;
    if (document == null) {
      return null;
    }
    for (final segment in document.segments) {
      if (segment.text != sentence) {
        continue;
      }
      for (final candidate in segment.tokens) {
        if (candidate.surface.toLowerCase() == word.toLowerCase()) {
          return candidate;
        }
      }
    }
    return null;
  }

  void _showWord(String word, String sentence) {
    showWordExplanation(
      context,
      word: word,
      sentence: sentence,
      language: _document?.meta.language ?? 'en',
      token: _tokenFor(word, sentence),
      sourceTitle: _document?.meta.title,
    );
  }

  void _showGrammar(ContentSegment segment) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('语法点', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  segment.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final note in segment.grammar) ...[
                  Text(note.pattern, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(note.explanation, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _analyzeSubtitle() async {
    final document = _document;
    if (document == null || _analyzing) {
      return;
    }
    final config = await ref.read(aiConfigProvider.future);
    if (!config.isConfigured) {
      _showMessage('请先在「设置」页配置 AI 接口');
      return;
    }
    if (!mounted) {
      return;
    }
    final progress = ValueNotifier<double>(0);
    var dialogShown = false;
    setState(() => _analyzing = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('AI 解析字幕'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('正在生成翻译、词汇与语法注释…'),
            const SizedBox(height: 12),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) =>
                  LinearProgressIndicator(value: value == 0 ? null : value),
            ),
          ],
        ),
      ),
    );
    dialogShown = true;
    try {
      final segments = await const SubtitleAnalyzer().analyze(
        config: config,
        document: document,
        onProgress: (value) => progress.value = value,
      );
      final enriched = document.copyWith(segments: segments);
      await const ContentStore().saveAnalysis(enriched);
      if (!mounted) {
        return;
      }
      setState(() => _document = enriched);
      if (dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      _showMessage('解析完成，已保存 JSON 缓存');
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      _showMessage('解析失败：$error');
    } finally {
      progress.dispose();
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }

  Future<void> _extractVocab() async {
    final document = _document;
    if (document == null) {
      return;
    }
    final added = await ref.read(vocabStoreProvider).addFromDocument(document);
    if (added > 0) {
      ref.read(vocabVersionProvider.notifier).state++;
    }
    _showMessage(added > 0 ? '已添加 $added 个生词' : '没有新的生词可添加');
  }

  Future<void> _changeSpeed(double speed) async {
    setState(() => _speed = speed);
    await _controller?.setPlaybackSpeed(speed);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _videoName == null ? '视频学习' : _stripExtension(_videoName!),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            enabled: _document != null && !_analyzing,
            onSelected: (value) {
              if (value == 'analyze') {
                _analyzeSubtitle();
              } else if (value == 'vocab') {
                _extractVocab();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'analyze',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome),
                  title: Text('AI 解析字幕'),
                ),
              ),
              PopupMenuItem(
                value: 'vocab',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.style_outlined),
                  title: Text('提取生词到生词本'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: '载入外挂字幕',
            onPressed: _busy ? null : _pickSubtitle,
            icon: const Icon(Icons.subtitles_outlined),
          ),
          IconButton(
            tooltip: '选择视频',
            onPressed: _busy ? null : _pickVideo,
            icon: const Icon(Icons.video_file_outlined),
          ),
        ],
      ),
      body: controller == null
          ? _EmptyState(onPickVideo: _busy ? null : _pickVideo)
          : Column(
              children: [
                _VideoStage(
                  controller: controller,
                  speed: _speed,
                  onSpeedChanged: _changeSpeed,
                ),
                if (_document == null)
                  Expanded(
                    child: _NoSubtitleHint(
                      onPickSubtitle: _busy ? null : _pickSubtitle,
                    ),
                  )
                else ...[
                  _SubtitleHeader(
                    title: _subtitleName ?? '字幕',
                    count: _document!.segments.length,
                    analyzing: _analyzing,
                    onAnalyze: _analyzeSubtitle,
                    onExtract: _extractVocab,
                  ),
                  Expanded(
                    child: _ScrollingSubtitles(
                      controller: controller,
                      document: _document!,
                      onWordTap: _showWord,
                      onGrammarTap: _showGrammar,
                    ),
                  ),
                ],
              ],
            ),
      floatingActionButton: _busy
          ? const FloatingActionButton(
              onPressed: null,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
    );
  }
}

class _VideoStage extends StatelessWidget {
  const _VideoStage({
    required this.controller,
    required this.speed,
    required this.onSpeedChanged,
  });

  final VideoPlayerController controller;
  final double speed;
  final ValueChanged<double> onSpeedChanged;

  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        final positionMs = durationMs > 0
            ? value.position.inMilliseconds.clamp(0, durationMs)
            : 0;
        final aspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
        return AspectRatio(
          aspectRatio: aspect.clamp(1.15, 2.4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: VideoPlayer(controller),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: positionMs.toDouble().clamp(
                            0,
                            durationMs > 0 ? durationMs.toDouble() : 1,
                          ),
                          max: durationMs > 0 ? durationMs.toDouble() : 1,
                          onChanged: durationMs > 0
                              ? (next) => controller.seekTo(
                                  Duration(milliseconds: next.toInt()),
                                )
                              : null,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            color: Colors.white,
                            onPressed: () => value.isPlaying
                                ? controller.pause()
                                : controller.play(),
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatMs(positionMs)} / ${_formatMs(durationMs)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          PopupMenuButton<double>(
                            initialValue: speed,
                            tooltip: '播放速度',
                            onSelected: onSpeedChanged,
                            itemBuilder: (context) => [
                              for (final item in _speeds)
                                PopupMenuItem(
                                  value: item,
                                  child: Text(
                                    item == 1.0
                                        ? '1.0x（正常）'
                                        : '${item}x',
                                  ),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.speed,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${speed}x',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubtitleHeader extends StatelessWidget {
  const _SubtitleHeader({
    required this.title,
    required this.count,
    required this.analyzing,
    required this.onAnalyze,
    required this.onExtract,
  });

  final String title;
  final int count;
  final bool analyzing;
  final VoidCallback onAnalyze;
  final VoidCallback onExtract;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('字幕 · $count 条', style: theme.textTheme.titleSmall),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '提取生词',
            onPressed: onExtract,
            icon: const Icon(Icons.style_outlined),
          ),
          if (analyzing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'AI 解析字幕',
              onPressed: onAnalyze,
              icon: const Icon(Icons.auto_awesome),
            ),
        ],
      ),
    );
  }
}

class _ScrollingSubtitles extends StatefulWidget {
  const _ScrollingSubtitles({
    required this.controller,
    required this.document,
    required this.onWordTap,
    required this.onGrammarTap,
  });

  final VideoPlayerController controller;
  final ContentDocument document;
  final void Function(String word, String sentence) onWordTap;
  final void Function(ContentSegment segment) onGrammarTap;

  @override
  State<_ScrollingSubtitles> createState() => _ScrollingSubtitlesState();
}

class _ScrollingSubtitlesState extends State<_ScrollingSubtitles> {
  final ItemScrollController _scrollController = ItemScrollController();
  int _activeIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
    _onTick();
  }

  @override
  void didUpdateWidget(covariant _ScrollingSubtitles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
    }
    _onTick();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    final position = widget.controller.value.position.inMilliseconds;
    final segment = widget.document.segmentAt(position);
    final index = segment?.index ?? -1;
    if (index == _activeIndex) {
      return;
    }
    if (mounted) {
      setState(() => _activeIndex = index);
    } else {
      _activeIndex = index;
    }
    if (index >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.isAttached) {
          return;
        }
        _scrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          alignment: 0.28,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScrollablePositionedList.builder(
      itemScrollController: _scrollController,
      itemCount: widget.document.segments.length,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemBuilder: (context, index) {
        final segment = widget.document.segments[index];
        final isActive = index == _activeIndex;
        if (!isActive) {
          return InkWell(
            onTap: () => widget.controller.seekTo(
              Duration(milliseconds: segment.startMs),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                segment.text.replaceAll('\n', ' '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.62,
                  ),
                  height: 1.4,
                ),
              ),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InteractiveLine(
                text: segment.text,
                translation: segment.translation,
                onWordTap: widget.onWordTap,
                textAlign: TextAlign.left,
                baseStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontSize: 17,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
                wordStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontSize: 17,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
                translationStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(
                    alpha: 0.8,
                  ),
                ),
              ),
              if (segment.grammar.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.psychology_outlined, size: 16),
                    label: Text('语法 · ${segment.grammar.length}'),
                    onPressed: () => widget.onGrammarTap(segment),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoSubtitleHint extends StatelessWidget {
  const _NoSubtitleHint({required this.onPickSubtitle});

  final VoidCallback? onPickSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.subtitles_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('载入外挂字幕开始学习', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '支持 SRT / VTT / ASS / LRC，字幕会以滚动列表跟随播放进度。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPickSubtitle,
              icon: const Icon(Icons.subtitles_outlined),
              label: const Text('载入字幕'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatMs(int ms) {
  final duration = Duration(milliseconds: ms);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPickVideo});

  final VoidCallback? onPickVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_filter_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('从本地选择视频', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '视频在上方播放，字幕以滚动列表跟随，支持点词查询、倍速与 AI 解析。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPickVideo,
              icon: const Icon(Icons.video_file_outlined),
              label: const Text('选择视频'),
            ),
          ],
        ),
      ),
    );
  }
}
