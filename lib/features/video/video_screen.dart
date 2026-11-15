import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';
import '../../core/models/content_document.dart';
import '../../core/subtitle/subtitle_parser.dart';
import '../../core/text/tokenizer.dart';

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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
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
    final result = await FilePicker.platform.pickFiles(
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
      _showMessage('已载入 ${parsed.segments.length} 条字幕');
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

  void _showWord(String word, String sentence) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => WordExplanationSheet(
        word: word,
        sentence: sentence,
        language: _document?.meta.language ?? 'en',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_videoName == null ? '视频学习' : _stripExtension(_videoName!)),
        actions: [
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
                Expanded(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        ),
                        if (_document != null)
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: controller,
                            builder: (context, value, _) {
                              final segment = _document!.segmentAt(
                                value.position.inMilliseconds,
                              );
                              if (segment == null) {
                                return const SizedBox.shrink();
                              }
                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: _SubtitleOverlay(
                                  segment: segment,
                                  onWordTap: _showWord,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: theme.colorScheme.surfaceContainer,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: () => value.isPlaying
                                  ? controller.pause()
                                  : controller.play(),
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_formatMs(value.position.inMilliseconds)} / '
                              '${_formatMs(value.duration.inMilliseconds)}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const Spacer(),
                            Flexible(
                              child: Text(
                                _subtitleName ?? '未载入字幕',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
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
              '支持外挂 SRT / VTT / ASS / LRC 字幕，播放时同步高亮并支持点词查询。',
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

class _SubtitleOverlay extends StatefulWidget {
  const _SubtitleOverlay({required this.segment, required this.onWordTap});

  final ContentSegment segment;
  final void Function(String word, String sentence) onWordTap;

  @override
  State<_SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<_SubtitleOverlay> {
  final List<TapGestureRecognizer> _recognizers = [];
  String? _cachedText;
  List<InlineSpan> _spans = const [];

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
    final text = widget.segment.text;
    if (_cachedText == text) {
      return;
    }
    _cachedText = text;
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    for (final token in tokenizeLine(text)) {
      if (isWordToken(token)) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onWordTap(token, text);
        _recognizers.add(recognizer);
        spans.add(TextSpan(text: token, style: wordStyle, recognizer: recognizer));
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }
    }
    _spans = spans;
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = const TextStyle(
      color: Colors.white,
      fontSize: 18,
      height: 1.35,
      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
    );
    final wordStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFFFFD166),
      decorationStyle: TextDecorationStyle.dotted,
    );
    _ensureSpans(baseStyle, wordStyle);
    final translation = widget.segment.translation;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
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
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(children: _spans),
          ),
          if (translation != null && translation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              translation,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE6E6E6),
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
