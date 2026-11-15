import 'package:flutter/material.dart';

import '../../core/language/languages.dart';
import '../../core/library/lyrics_search.dart';
import '../../core/library/lyrics_store.dart';
import '../../core/models/content_document.dart';
import '../../core/subtitle/subtitle_parser.dart';

class LyricsSearchSheet extends StatefulWidget {
  const LyricsSearchSheet({
    super.key,
    required this.initialTitle,
    required this.initialArtist,
    required this.onImported,
  });

  final String initialTitle;
  final String initialArtist;
  final Future<void> Function() onImported;

  @override
  State<LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends State<LyricsSearchSheet> {
  static const _service = LyricsSearchService();
  static const _store = LyricsStore();

  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  late final TextEditingController _artist = TextEditingController(
    text: widget.initialArtist,
  );
  List<LyricsSearchResult> _results = const [];
  bool _searching = false;
  bool _importing = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _service.search(
        title: _title.text,
        artist: _artist.text,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
          _error = results.isEmpty ? '没有找到可用歌词' : null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = '搜索失败：$error';
        });
      }
    }
  }

  Future<void> _importResult(LyricsSearchResult result) async {
    setState(() => _importing = true);
    try {
      var parsed = SubtitleParser.parse(
        result.lyrics,
        fileName: 'online.lrc',
      );
      if (parsed.segments.isEmpty) {
        final lines = result.lyrics
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        parsed = SubtitleParseResult(
          format: 'plain',
          segments: [
            for (var i = 0; i < lines.length; i++)
              ContentSegment(
                index: i,
                startMs: i * 4000,
                endMs: (i + 1) * 4000,
                text: lines[i],
              ),
          ],
        );
      }
      final language = detectLanguage(result.lyrics);
      final document = ContentDocument(
        kind: ContentKind.music,
        meta: ContentMeta(
          title: result.title,
          source: result.artist,
          language: language,
          durationMs: result.durationMs > 0 ? result.durationMs : null,
        ),
        segments: parsed.segments,
      );
      await _store.save(document);
      await widget.onImported();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = '导入失败：$error';
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
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('在线搜索歌词', style: theme.textTheme.titleMedium),
                const Spacer(),
                Chip(
                  label: const Text('实验性'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: '歌名'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _artist,
                    decoration: const InputDecoration(labelText: '歌手'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_searching ? '搜索中…' : '搜索'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 8),
            if (_importing)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final result in _results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        result.synced ? Icons.subtitles : Icons.notes,
                        color: result.synced
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(result.title),
                      subtitle: Text(
                        '${result.artist}${result.album.isEmpty ? '' : ' · ${result.album}'}'
                        ' · ${result.source}'
                        '${result.synced ? ' · 有时间轴' : ' · 无时间轴'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(_formatMs(result.durationMs)),
                      onTap: _importing ? null : () => _importResult(result),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMs(int ms) {
    if (ms <= 0) {
      return '--:--';
    }
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

Future<void> showLyricsSearchSheet(
  BuildContext context, {
  required String title,
  required String artist,
  required Future<void> Function() onImported,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => LyricsSearchSheet(
      initialTitle: title,
      initialArtist: artist,
      onImported: onImported,
    ),
  );
}
