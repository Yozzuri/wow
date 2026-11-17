import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/video/online_video.dart';
import '../../core/video/online_video_settings.dart';

Future<OnlineVideoResult?> showOnlineVideoSheet(
  BuildContext context, {
  required String language,
}) {
  return showModalBottomSheet<OnlineVideoResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => OnlineVideoSheet(language: language),
  );
}

class OnlineVideoSheet extends ConsumerStatefulWidget {
  const OnlineVideoSheet({super.key, required this.language});

  final String language;

  @override
  ConsumerState<OnlineVideoSheet> createState() => _OnlineVideoSheetState();
}

class _OnlineVideoSheetState extends ConsumerState<OnlineVideoSheet> {
  static const _service = OnlineVideoService();
  static const _historyStore = OnlineVideoHistoryStore();

  final _urlController = TextEditingController();
  List<OnlineVideoHistoryEntry> _history = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await _historyStore.load();
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _urlController.text = text;
      setState(() => _error = null);
    }
  }

  Future<void> _play(String raw) async {
    final url = raw.trim();
    if (url.isEmpty || _loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cdnHost = ref.read(onlineVideoSettingsProvider).cdnHost;
      final result = await _service.resolve(
        url,
        language: widget.language,
        cdnHost: cdnHost,
      );
      final history = await _historyStore.add(
        OnlineVideoHistoryEntry(
          url: result.pageUrl.toString(),
          title: result.title,
          savedAt: DateTime.now(),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() => _history = history);
      Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _removeHistory(OnlineVideoHistoryEntry entry) async {
    final history = await _historyStore.remove(entry.url);
    if (mounted) {
      setState(() => _history = history);
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('在线视频', style: theme.textTheme.titleLarge),
                  ),
                  Chip(
                    label: const Text('实验性'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '支持 mp4 / m3u8 直链和部分视频网页。会自动尝试获取 B 站字幕或搜索公开字幕，失败时仍可手动导入字幕文件。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: '视频地址',
                  hintText: 'https://... 或 B 站视频页链接',
                  suffixIcon: IconButton(
                    tooltip: '粘贴',
                    onPressed: _loading ? null : _paste,
                    icon: const Icon(Icons.content_paste),
                  ),
                ),
                onSubmitted: _play,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : () => _play(_urlController.text),
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_loading ? '正在解析并搜索字幕…' : '播放并搜索字幕'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('最近播放', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final entry in _history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.public),
                    title: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      entry.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '播放',
                          onPressed: _loading ? null : () => _play(entry.url),
                          icon: const Icon(Icons.play_circle_outline),
                        ),
                        IconButton(
                          tooltip: '删除记录',
                          onPressed: _loading
                              ? null
                              : () => _removeHistory(entry),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
