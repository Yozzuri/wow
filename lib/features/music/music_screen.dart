import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/lyrics_store.dart';
import '../../core/media/media_session_service.dart';
import '../../core/models/content_document.dart';
import '../../core/subtitle/subtitle_parser.dart';
import '../common/interactive_line.dart';
import '../common/word_explanation_sheet.dart';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen>
    with WidgetsBindingObserver {
  static const _store = LyricsStore();
  static const _service = MediaSessionService();

  Timer? _timer;
  bool _checkingAccess = true;
  bool _hasAccess = false;
  bool _importing = false;
  NowPlaying? _nowPlaying;
  List<LyricsEntry> _entries = const [];
  LyricsEntry? _matched;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _timer = Timer.periodic(
      const Duration(milliseconds: 1000),
      (_) => _poll(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    final access = await _service.hasAccess();
    if (mounted) {
      setState(() {
        _hasAccess = access;
        _checkingAccess = false;
      });
    }
    await _loadEntries();
    await _poll();
  }

  Future<void> _loadEntries() async {
    final entries = await _store.list();
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _matched = _nowPlaying == null
          ? null
          : _store.match(_nowPlaying!, entries);
    });
  }

  Future<void> _poll() async {
    if (!_hasAccess) {
      return;
    }
    final nowPlaying = await _service.getNowPlaying();
    if (!mounted) {
      return;
    }
    final changed =
        nowPlaying?.title != _nowPlaying?.title ||
        nowPlaying?.artist != _nowPlaying?.artist;
    setState(() {
      _nowPlaying = nowPlaying;
      if (changed) {
        _matched = nowPlaying == null
            ? null
            : _store.match(nowPlaying, _entries);
      }
    });
  }

  Future<void> _importLyrics() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc', 'txt'],
      withData: true,
    );
    final file = (result != null && result.files.isNotEmpty)
        ? result.files.first
        : null;
    if (file == null) {
      return;
    }
    setState(() => _importing = true);
    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
      final parsed = SubtitleParser.parse(text, fileName: file.name);
      if (parsed.segments.isEmpty) {
        _showMessage('没有解析到歌词内容');
        return;
      }
      final fallbackTitle = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;
      final title = (parsed.metadata['ti'] ?? '').trim().isNotEmpty
          ? parsed.metadata['ti']!.trim()
          : (_nowPlaying?.title ?? fallbackTitle);
      final artist = (parsed.metadata['ar'] ?? '').trim().isNotEmpty
          ? parsed.metadata['ar']!.trim()
          : (_nowPlaying?.artist ?? '');
      final document = ContentDocument(
        kind: ContentKind.music,
        meta: ContentMeta(
          title: title,
          source: artist,
          language: 'en',
          durationMs: _nowPlaying?.durationMs,
        ),
        segments: parsed.segments,
      );
      await _store.save(document);
      await _loadEntries();
      _showMessage('歌词已导入：$title');
    } catch (error) {
      _showMessage('歌词导入失败：$error');
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _deleteEntry(LyricsEntry entry) async {
    await _store.delete(entry);
    await _loadEntries();
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
    final matched = _matched;
    ContentToken? token;
    if (matched != null) {
      for (final segment in matched.document.segments) {
        if (segment.text != sentence) {
          continue;
        }
        for (final candidate in segment.tokens) {
          if (candidate.surface.toLowerCase() == word.toLowerCase()) {
            token = candidate;
            break;
          }
        }
        break;
      }
    }
    showWordExplanation(
      context,
      word: word,
      sentence: sentence,
      language: matched?.document.meta.language ?? 'en',
      token: token,
      sourceTitle: matched?.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐'),
        actions: [
          IconButton(
            tooltip: '导入 LRC 歌词',
            onPressed: _importing ? null : _importLyrics,
            icon: const Icon(Icons.lyrics_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_checkingAccess)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!_hasAccess)
              _AccessCard(onOpenSettings: _service.openSettings)
            else
              _NowPlayingCard(nowPlaying: _nowPlaying),
            const SizedBox(height: 16),
            Text('歌词', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildLyrics(theme),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('已导入歌词', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (_entries.isNotEmpty)
                  Text(
                    '${_entries.length} 首',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有导入歌词。播放歌曲后导入同名 LRC，会自动匹配。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ..._entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(entry.title),
                  subtitle: Text(
                    entry.artist.isEmpty ? '未知歌手' : entry.artist,
                  ),
                  trailing: IconButton(
                    tooltip: '删除',
                    onPressed: () => _deleteEntry(entry),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyrics(ThemeData theme) {
    final matched = _matched;
    if (matched == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nowPlaying == null ? '等待系统播放音乐…' : '未找到匹配的歌词',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '在网易云等 App 播放歌曲后，导入对应 LRC 文件即可同步显示。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _importing ? null : _importLyrics,
                icon: const Icon(Icons.lyrics_outlined),
                label: const Text('导入 LRC'),
              ),
            ],
          ),
        ),
      );
    }

    final document = matched.document;
    final position = _nowPlaying?.positionMs ?? 0;
    final active = document.segmentAt(position);
    final activeIndex = active?.index ?? -1;
    final nearby = <ContentSegment>[];
    if (activeIndex >= 0) {
      for (var offset = -2; offset <= 2; offset++) {
        final index = activeIndex + offset;
        if (index >= 0 && index < document.segments.length) {
          nearby.add(document.segments[index]);
        }
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${matched.title}${matched.artist.isEmpty ? '' : ' · ${matched.artist}'}',
              style: theme.textTheme.titleSmall,
            ),
            const Divider(height: 20),
            if (active == null)
              Text(
                document.segments.isNotEmpty &&
                        position > document.segments.last.endMs
                    ? '歌词已结束'
                    : '等待歌词时间轴…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InteractiveLine(
                  text: active.text,
                  translation: active.translation,
                  onWordTap: _showWord,
                  baseStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontSize: 20,
                    height: 1.4,
                  ),
                  wordStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontSize: 20,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.primary,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                  translationStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 14,
                  ),
                ),
              ),
            if (nearby.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...nearby
                  .where((segment) => segment.index != activeIndex)
                  .map(
                    (segment) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        segment.text.replaceAll('\n', ' '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.onOpenSettings});

  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text('需要通知使用权', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '为了读取系统当前播放的歌曲信息，请允许 LangLearn 访问通知。授权后回到本页即可。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('打开系统设置'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.nowPlaying});

  final NowPlaying? nowPlaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowPlaying = this.nowPlaying;
    if (nowPlaying == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.music_off_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('未检测到正在播放的音乐')),
            ],
          ),
        ),
      );
    }
    final duration = nowPlaying.durationMs;
    final progress = duration > 0
        ? (nowPlaying.positionMs / duration).clamp(0.0, 1.0)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    nowPlaying.isPlaying
                        ? Icons.graphic_eq
                        : Icons.pause_circle_outline,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nowPlaying.title ?? '未知歌曲',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          if ((nowPlaying.artist ?? '').isNotEmpty)
                            nowPlaying.artist!,
                          if ((nowPlaying.album ?? '').isNotEmpty)
                            nowPlaying.album!,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _formatMs(nowPlaying.positionMs),
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  Text(
                    _formatMs(duration),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
            if ((nowPlaying.packageName ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                nowPlaying.packageName!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
