import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/ai/ai_settings.dart';
import '../../core/ai/subtitle_analyzer.dart';
import '../../core/library/lyrics_store.dart';
import '../../core/media/media_session_service.dart';
import '../../core/models/content_document.dart';
import '../../core/reading/reading_book.dart';
import '../../core/storage/content_store.dart';
import '../../core/subtitle/subtitle_parser.dart';
import '../../app/router.dart';
import '../common/interactive_line.dart';
import '../common/segment_notes.dart';
import '../common/word_explanation_sheet.dart';
import 'lyrics_search_sheet.dart';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen>
    with WidgetsBindingObserver {
  static const _store = LyricsStore();
  static const _service = MediaSessionService();

  StreamSubscription<NowPlaying?>? _eventSubscription;
  Timer? _ticker;
  Timer? _resyncTimer;
  bool _checkingAccess = true;
  bool _hasAccess = false;
  bool _importing = false;
  bool _visible = false;
  bool _foreground = true;
  NowPlaying? _nowPlaying;
  List<LyricsEntry> _entries = const [];
  LyricsEntry? _matched;
  String _language = 'en';
  final ValueNotifier<int> _position = ValueNotifier<int>(0);
  final ValueNotifier<int> _duration = ValueNotifier<int>(0);

  static const int _musicTabIndex = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visible = ref.read(currentTabIndexProvider) == _musicTabIndex;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSync();
    _position.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) {
      return;
    }
    _foreground = foreground;
    if (foreground) {
      _startSync();
    } else {
      _stopSync();
    }
  }

  Future<void> _bootstrap() async {
    final access = await _service.hasAccess();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasAccess = access;
      _checkingAccess = false;
    });
    await _loadEntries();
    if (access) {
      await _startSync();
    }
  }

  bool get _canSync => _hasAccess && _visible && _foreground;

  Future<void> _startSync() async {
    if (!_canSync) {
      return;
    }
    _stopSync();
    _eventSubscription = _service.events.listen(
      (nowPlaying) => _applyNowPlaying(nowPlaying),
      onError: (_) {},
    );
    await _syncOnce();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );
    _resyncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncOnce(),
    );
  }

  void _stopSync() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _ticker?.cancel();
    _ticker = null;
    _resyncTimer?.cancel();
    _resyncTimer = null;
  }

  Future<void> _syncOnce() async {
    if (!_canSync) {
      return;
    }
    final nowPlaying = await _service.getNowPlaying();
    if (!mounted || !_canSync) {
      return;
    }
    _applyNowPlaying(nowPlaying, force: true);
  }

  void _applyNowPlaying(NowPlaying? nowPlaying, {bool force = false}) {
    if (!mounted) {
      return;
    }
    final previous = _nowPlaying;
    final metadataChanged =
        force ||
        previous?.title != nowPlaying?.title ||
        previous?.artist != nowPlaying?.artist ||
        previous?.album != nowPlaying?.album ||
        previous?.packageName != nowPlaying?.packageName ||
        previous?.durationMs != nowPlaying?.durationMs ||
        previous?.isPlaying != nowPlaying?.isPlaying;
    _nowPlaying = nowPlaying;
    if (nowPlaying != null) {
      _position.value = nowPlaying.positionMs;
      _duration.value = nowPlaying.durationMs;
    } else {
      _position.value = 0;
      _duration.value = 0;
    }
    if (metadataChanged) {
      final titleChanged =
          previous?.title != nowPlaying?.title ||
          previous?.artist != nowPlaying?.artist;
      if (titleChanged) {
        _matched = nowPlaying == null
            ? null
            : _store.match(nowPlaying, _entries);
        if (_matched != null) {
          _language = _matched!.document.meta.language;
        }
      }
      if (_visible) {
        setState(() {});
      }
    }
  }

  void _tick() {
    if (!_canSync) {
      return;
    }
    final nowPlaying = _nowPlaying;
    if (nowPlaying == null || !nowPlaying.isPlaying) {
      return;
    }
    final duration = _duration.value;
    final next = _position.value + 200;
    _position.value = duration > 0 ? min(next, duration) : next;
  }

  Future<void> _loadEntries() async {
    final stored = await _store.list();
    final entries = <LyricsEntry>[];
    for (final entry in stored) {
      final cached = await const ContentStore().loadAnalysis(
        entry.document.withoutAnalysis(),
      );
      entries.add(
        cached == null
            ? entry
            : LyricsEntry(filePath: entry.filePath, document: cached),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _matched = _nowPlaying == null
          ? null
          : _store.match(_nowPlaying!, entries);
      if (_matched != null) {
        _language = _matched!.document.meta.language;
      }
    });
  }

  Future<void> _seek(int positionMs) async {
    _position.value = positionMs;
    await _service.seek(positionMs);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    unawaited(_syncOnce());
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
      final detected = detectLanguage(text);
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
          language: detected,
          durationMs: _nowPlaying?.durationMs,
        ),
        segments: parsed.segments,
      );
      await _store.save(document);
      if (mounted) {
        setState(() => _language = detected);
      }
      await _loadEntries();
      _showMessage(
        '歌词已导入：$title · ${readingLanguageFor(detected).label}',
      );
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

  Future<void> _changeLanguage(String code) async {
    setState(() => _language = code);
    final matched = _matched;
    if (matched == null) {
      return;
    }
    final base = matched.document.withoutAnalysis().copyWith(
      meta: matched.document.meta.copyWith(language: code),
    );
    final cached = await const ContentStore().loadAnalysis(base);
    await _store.save(cached ?? base);
    await _loadEntries();
    _showMessage(
      cached == null
          ? '歌词语言已设为 ${readingLanguageFor(code).label}，展开时会用该语言解析'
          : '歌词语言已设为 ${readingLanguageFor(code).label}，已载入缓存',
    );
  }

  Future<void> _searchOnline() async {
    await showLyricsSearchSheet(
      context,
      title: _nowPlaying?.title ?? _matched?.title ?? '',
      artist: _nowPlaying?.artist ?? _matched?.artist ?? '',
      onImported: () async {
        await _loadEntries();
        _showMessage('在线歌词已导入');
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onLyricsAnalyzed(ContentDocument document) {
    final matched = _matched;
    if (matched == null || !mounted) {
      return;
    }
    final updated = LyricsEntry(
      filePath: matched.filePath,
      document: document,
    );
    setState(() {
      _entries = [
        for (final entry in _entries)
          entry.filePath == matched.filePath ? updated : entry,
      ];
      _matched = updated;
    });
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
    ref.listen<int>(currentTabIndexProvider, (previous, next) {
      final visible = next == _musicTabIndex;
      if (visible == _visible) {
        return;
      }
      _visible = visible;
      if (visible) {
        _startSync();
        setState(() {});
      } else {
        _stopSync();
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '歌词语言',
            initialValue: _language,
            onSelected: _changeLanguage,
            itemBuilder: (context) => [
              for (final item in readingLanguages)
                PopupMenuItem(value: item.code, child: Text(item.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.translate, size: 20),
                  const SizedBox(width: 4),
                  Text(readingLanguageFor(_language).label),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '在线搜索歌词（实验性）',
            onPressed: _searchOnline,
            icon: const Icon(Icons.travel_explore),
          ),
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
      body: _checkingAccess
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '歌曲信息'),
                      Tab(text: '歌词'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Builder(
                          builder: (context) => _SongInfoTab(
                            hasAccess: _hasAccess,
                            nowPlaying: _nowPlaying,
                            position: _position,
                            duration: _duration,
                            entries: _entries,
                            hasMatch: _matched != null,
                            onOpenSettings: _service.openSettings,
                            onImport: _importLyrics,
                            onDelete: _deleteEntry,
                            onOpenLyrics: () =>
                                DefaultTabController.of(context).animateTo(1),
                          ),
                        ),
                        _ImmersiveLyricsTab(
                          matched: _matched,
                          nowPlaying: _nowPlaying,
                          position: _position,
                          hasAccess: _hasAccess,
                          onWordTap: _showWord,
                          onSeek: _seek,
                          onImport: _importLyrics,
                          onOpenSettings: _service.openSettings,
                          onAnalyzed: _onLyricsAnalyzed,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SongInfoTab extends StatelessWidget {
  const _SongInfoTab({
    required this.hasAccess,
    required this.nowPlaying,
    required this.position,
    required this.duration,
    required this.entries,
    required this.hasMatch,
    required this.onOpenSettings,
    required this.onImport,
    required this.onDelete,
    required this.onOpenLyrics,
  });

  final bool hasAccess;
  final NowPlaying? nowPlaying;
  final ValueListenable<int> position;
  final ValueListenable<int> duration;
  final List<LyricsEntry> entries;
  final bool hasMatch;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onImport;
  final Future<void> Function(LyricsEntry entry) onDelete;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onImport,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!hasAccess)
            _AccessCard(onOpenSettings: onOpenSettings)
          else
            _NowPlayingCard(
              nowPlaying: nowPlaying,
              position: position,
              duration: duration,
            ),
          if (hasMatch) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onOpenLyrics,
              icon: const Icon(Icons.queue_music),
              label: const Text('打开沉浸式歌词'),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text('已导入歌词', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (entries.isNotEmpty)
                Text(
                  '${entries.length} 首',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (entries.isEmpty)
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
            ...entries.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(entry.title),
                subtitle: Text(entry.artist.isEmpty ? '未知歌手' : entry.artist),
                trailing: IconButton(
                  tooltip: '删除',
                  onPressed: () => onDelete(entry),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.lyrics_outlined),
            label: const Text('导入 LRC 歌词'),
          ),
        ],
      ),
    );
  }
}

class _ImmersiveLyricsTab extends ConsumerStatefulWidget {
  const _ImmersiveLyricsTab({
    required this.matched,
    required this.nowPlaying,
    required this.position,
    required this.hasAccess,
    required this.onWordTap,
    required this.onSeek,
    required this.onImport,
    required this.onOpenSettings,
    this.onAnalyzed,
  });

  final LyricsEntry? matched;
  final NowPlaying? nowPlaying;
  final ValueListenable<int> position;
  final bool hasAccess;
  final void Function(String word, String sentence) onWordTap;
  final Future<void> Function(int positionMs) onSeek;
  final Future<void> Function() onImport;
  final Future<void> Function() onOpenSettings;

  /// Lets the parent refresh its cached entry so a rebuilt tab can reuse the
  /// analysis instead of requesting it again.
  final void Function(ContentDocument document)? onAnalyzed;

  @override
  ConsumerState<_ImmersiveLyricsTab> createState() =>
      _ImmersiveLyricsTabState();
}

class _ImmersiveLyricsTabState extends ConsumerState<_ImmersiveLyricsTab> {
  ContentDocument? _document;
  bool _expanded = false;
  bool _analyzing = false;
  int _analysisCompleted = 0;
  int _analysisTotal = 0;
  int _analysisFailed = 0;

  @override
  void initState() {
    super.initState();
    _document = widget.matched?.document;
    _expanded = _document?.hasRichAnalysis ?? false;
    if (!_expanded) {
      _restoreCachedAnalysis();
    }
  }

  @override
  void didUpdateWidget(covariant _ImmersiveLyricsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pathChanged =
        oldWidget.matched?.filePath != widget.matched?.filePath;
    final languageChanged =
        oldWidget.matched?.document.meta.language !=
            widget.matched?.document.meta.language;
    if (pathChanged || languageChanged) {
      _document = widget.matched?.document;
      _expanded = _document?.hasRichAnalysis ?? false;
      if (!_expanded) {
        _restoreCachedAnalysis();
      }
      return;
    }
    final incoming = widget.matched?.document;
    if (incoming != null &&
        incoming.hasRichAnalysis &&
        !(_document?.hasRichAnalysis ?? false)) {
      _document = incoming;
      _expanded = true;
    }
  }

  /// Lyrics files can lose their analysis when language or metadata changes,
  /// while the analysis cache still holds it. Reuse that instead of asking
  /// the model again.
  Future<void> _restoreCachedAnalysis() async {
    final document = _document;
    if (document == null || document.hasRichAnalysis) {
      return;
    }
    final cached = await const ContentStore().loadAnalysis(
      document.withoutAnalysis(),
    );
    if (!mounted || cached == null || !cached.hasRichAnalysis) {
      return;
    }
    setState(() {
      _document = cached;
      _expanded = true;
    });
    await const LyricsStore().save(cached);
    widget.onAnalyzed?.call(cached);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleNotes() async {
    final document = _document;
    if (document == null) {
      return;
    }
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    if (document.hasRichAnalysis) {
      setState(() => _expanded = true);
      return;
    }
    final cached = await const ContentStore().loadAnalysis(
      document.withoutAnalysis(),
    );
    if (cached != null && cached.hasRichAnalysis) {
      await const LyricsStore().save(cached);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = cached;
        _expanded = true;
      });
      widget.onAnalyzed?.call(cached);
      return;
    }
    await _runAnalysis(document, force: false);
  }

  Future<void> _regenerateAnalysis() async {
    final document = _document;
    if (document == null || _analyzing) {
      return;
    }
    await _runAnalysis(document, force: true);
  }

  Future<void> _runAnalysis(
    ContentDocument document, {
    required bool force,
  }) async {
    final config = await ref.read(aiConfigProvider.future);
    if (!mounted) {
      return;
    }
    if (!config.isConfigured) {
      _showMessage('请先在「设置」页配置 AI 接口');
      return;
    }
    setState(() {
      _analyzing = true;
      _analysisCompleted = 0;
      _analysisTotal = 0;
      _analysisFailed = 0;
    });
    try {
      final segments = await const SubtitleAnalyzer().analyze(
        config: config,
        document: document,
        force: force,
        onBatch: (batch, completed, total, failed) {
          if (!mounted) {
            return;
          }
          setState(() {
            _analysisCompleted = completed;
            _analysisTotal = total;
            _analysisFailed = failed;
            if (batch.isNotEmpty && _document != null) {
              _document = applyAnalysis(_document!, batch);
            }
          });
        },
      );
      final enriched = document.copyWith(segments: segments);
      await const ContentStore().saveAnalysis(enriched);
      await const LyricsStore().save(enriched);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = enriched;
        _expanded = true;
      });
      widget.onAnalyzed?.call(enriched);
      _showMessage(
        _analysisFailed > 0
            ? '解析完成 ${_analysisTotal - _analysisFailed}/$_analysisTotal，失败 $_analysisFailed 块'
            : 'AI 解析完成',
      );
    } catch (error) {
      _showMessage('AI 解析失败：$error');
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }

  void _showPhrase(ContentPhrase phrase, ContentSegment segment) {
    final meaning = [phrase.meaning, phrase.usage]
        .where((value) => value != null && value.isNotEmpty)
        .join(' · ');
    showWordExplanation(
      context,
      word: phrase.text,
      sentence: segment.text,
      language: _document?.meta.language ?? 'en',
      token: ContentToken(
        surface: phrase.text,
        lemma: phrase.text,
        pos: 'phrase',
        meaning: meaning.isEmpty ? null : meaning,
      ),
      sourceTitle: widget.matched?.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.matched == null || _document == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.queue_music,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                !widget.hasAccess
                    ? '授予通知使用权后即可读取系统播放的歌曲'
                    : widget.nowPlaying == null
                    ? '等待系统播放音乐…'
                    : '未找到匹配的歌词',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.hasAccess
                    ? widget.onImport
                    : widget.onOpenSettings,
                icon: Icon(
                  widget.hasAccess ? Icons.lyrics_outlined : Icons.settings,
                ),
                label: Text(
                  widget.hasAccess ? '导入 LRC 歌词' : '打开系统设置',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _ImmersiveLyrics(
      document: _document!,
      title: widget.matched!.title,
      artist: widget.matched!.artist,
      position: widget.position,
      durationMs: widget.nowPlaying?.durationMs ?? 0,
      expanded: _expanded,
      analyzing: _analyzing,
      analysisCompleted: _analysisCompleted,
      analysisTotal: _analysisTotal,
      analysisFailed: _analysisFailed,
      onToggleNotes: _toggleNotes,
      onRegenerate: _regenerateAnalysis,
      onPhraseTap: _showPhrase,
      onWordTap: widget.onWordTap,
      onSeek: widget.onSeek,
    );
  }
}

class _ImmersiveLyrics extends StatefulWidget {
  const _ImmersiveLyrics({
    required this.document,
    required this.title,
    required this.artist,
    required this.position,
    required this.durationMs,
    required this.expanded,
    required this.analyzing,
    required this.analysisCompleted,
    required this.analysisTotal,
    required this.analysisFailed,
    required this.onToggleNotes,
    required this.onRegenerate,
    required this.onPhraseTap,
    required this.onWordTap,
    required this.onSeek,
  });

  final ContentDocument document;
  final String title;
  final String artist;
  final ValueListenable<int> position;
  final int durationMs;
  final bool expanded;
  final bool analyzing;
  final int analysisCompleted;
  final int analysisTotal;
  final int analysisFailed;
  final VoidCallback onToggleNotes;
  final VoidCallback onRegenerate;
  final void Function(ContentPhrase phrase, ContentSegment segment) onPhraseTap;
  final void Function(String word, String sentence) onWordTap;
  final Future<void> Function(int positionMs) onSeek;

  @override
  State<_ImmersiveLyrics> createState() => _ImmersiveLyricsState();
}

class _ImmersiveLyricsState extends State<_ImmersiveLyrics> {
  final ItemScrollController _scrollController = ItemScrollController();
  int _activeIndex = -1;
  bool _following = true;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant _ImmersiveLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_onPositionChanged);
      widget.position.addListener(_onPositionChanged);
    }
    if (oldWidget.document != widget.document) {
      _activeIndex = -1;
    }
    _onPositionChanged();
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPositionChanged);
    _resumeTimer?.cancel();
    super.dispose();
  }

  int _indexFor(int positionMs) {
    final segment = widget.document.segmentAt(positionMs);
    if (segment != null) {
      return segment.index;
    }
    final segments = widget.document.segments;
    if (segments.isEmpty) {
      return -1;
    }
    // The last lyric often ends before the track does; keep it highlighted
    // instead of dropping the highlight for the rest of the song.
    if (positionMs > segments.last.endMs) {
      return segments.last.index;
    }
    return -1;
  }

  void _onPositionChanged() {
    final index = _indexFor(widget.position.value);
    if (index == _activeIndex) {
      return;
    }
    setState(() => _activeIndex = index);
    if (index >= 0 && _following) {
      _scrollTo(index);
    }
  }

  void _scrollTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.isAttached) {
        return;
      }
      _scrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.36,
      );
    });
  }

  void _pauseFollowing() {
    if (!_following) {
      return;
    }
    setState(() => _following = false);
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) {
        return;
      }
      setState(() => _following = true);
      if (_activeIndex >= 0) {
        _scrollTo(_activeIndex);
      }
    });
  }

  void _resumeFollowing() {
    _resumeTimer?.cancel();
    setState(() => _following = true);
    if (_activeIndex >= 0) {
      _scrollTo(_activeIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = widget.durationMs > 0
        ? widget.durationMs
        : widget.document.meta.durationMs ?? 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.artist.isNotEmpty)
                      Text(
                        widget.artist,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (widget.analyzing)
                      Text(
                        'AI 解析 ${widget.analysisCompleted}/${widget.analysisTotal}'
                        '${widget.analysisFailed > 0 ? ' · 失败 ${widget.analysisFailed}' : ''}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.analyzing)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                if (widget.expanded)
                  IconButton(
                    tooltip: '重新生成解析',
                    onPressed: widget.onRegenerate,
                    icon: const Icon(Icons.refresh),
                  ),
                IconButton(
                  tooltip: widget.expanded ? '收起语法与短语' : '展开语法与短语',
                  onPressed: widget.onToggleNotes,
                  icon: Icon(
                    widget.expanded ? Icons.unfold_less : Icons.unfold_more,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _pauseFollowing();
                  }
                  return false;
                },
                child: RepaintBoundary(
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _scrollController,
                    itemCount: widget.document.segments.length,
                    padding: const EdgeInsets.symmetric(vertical: 120),
                    itemBuilder: (context, index) {
                      final segment = widget.document.segments[index];
                      final isActive = index == _activeIndex;
                      if (isActive) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InteractiveLine(
                                text: segment.text,
                                translation: segment.translation,
                                onWordTap: widget.onWordTap,
                                textAlign: TextAlign.left,
                                language: widget.document.meta.language,
                                baseStyle: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 23,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                ),
                                wordStyle: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 23,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: theme.colorScheme.primary,
                                  decorationStyle: TextDecorationStyle.dotted,
                                ),
                                translationStyle: theme.textTheme.bodyMedium
                                    ?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              if (widget.expanded) ...[
                                const SizedBox(height: 8),
                                SegmentNotes(
                                  segment: segment,
                                  onPhraseTap: (phrase) =>
                                      widget.onPhraseTap(phrase, segment),
                                ),
                              ],
                            ],
                          ),
                        );
                      }
                      return InkWell(
                        onTap: () => widget.onSeek(segment.startMs),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 7, 24, 7),
                          child: Text(
                            segment.text.replaceAll('\n', ' '),
                            textAlign: TextAlign.left,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.55),
                              height: 1.4,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (!_following)
                Positioned(
                  right: 16,
                  bottom: 10,
                  child: FilledButton.tonalIcon(
                    onPressed: _resumeFollowing,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('回到当前'),
                  ),
                ),
            ],
          ),
        ),
        ValueListenableBuilder<int>(
          valueListenable: widget.position,
          builder: (context, position, _) {
            final progress = duration > 0
                ? (position / duration).clamp(0.0, 1.0)
                : 0.0;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Row(
                children: [
                  Text(
                    _formatMs(position),
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_formatMs(duration), style: theme.textTheme.labelSmall),
                ],
              ),
            );
          },
        ),
      ],
        ),

      ],
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
  const _NowPlayingCard({
    required this.nowPlaying,
    required this.position,
    required this.duration,
  });

  final NowPlaying? nowPlaying;
  final ValueListenable<int> position;
  final ValueListenable<int> duration;

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
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
            ValueListenableBuilder<int>(
              valueListenable: duration,
              builder: (context, total, _) {
                if (total <= 0) {
                  return const SizedBox.shrink();
                }
                return ValueListenableBuilder<int>(
                  valueListenable: position,
                  builder: (context, current, _) {
                    final progress = (current / total).clamp(0.0, 1.0);
                    return Column(
                      children: [
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              _formatMs(current),
                              style: theme.textTheme.labelSmall,
                            ),
                            const Spacer(),
                            Text(
                              _formatMs(total),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
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
