import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';
import '../../core/appearance/appearance_settings.dart';
import '../../core/text/tokenizer_settings.dart';
import '../../core/video/online_video_settings.dart';
import '../../core/vocab/learning_plan.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _obscureKey = true;
  bool _testing = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(aiConfigProvider.future).then((config) {
      if (!mounted) {
        return;
      }
      setState(() {
        _baseUrlController.text = config.baseUrl;
        _modelController.text = config.model;
        _apiKeyController.text = config.apiKey;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  AiConfig get _currentConfig => AiConfig(
    baseUrl: _baseUrlController.text.trim(),
    model: _modelController.text.trim(),
    apiKey: _apiKeyController.text.trim(),
  );

  Future<void> _save({bool showSnackBar = true}) async {
    await ref.read(aiSettingsStoreProvider).save(_currentConfig);
    ref.invalidate(aiConfigProvider);
    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI 设置已保存')));
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await _save(showSnackBar: false);
      final result = await AiClient(_currentConfig).testConnection();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接成功：$result')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('连接失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _editTranscriptionModel() async {
    final settings = ref.read(onlineVideoSettingsProvider);
    final controller = TextEditingController(
      text: settings.transcriptionModel,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('语音转写模型'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '模型名',
            hintText: 'whisper-1',
            helperText: '需要接口支持 /audio/transcriptions',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) {
      return;
    }
    await ref
        .read(onlineVideoSettingsProvider.notifier)
        .update(settings.copyWith(transcriptionModel: result));
  }

  Future<void> _pickBackground() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = (result != null && result.files.isNotEmpty)
        ? result.files.first
        : null;
    if (file == null) {
      return;
    }
    try {
      final bytes = file.bytes;
      if (bytes == null) {
        return;
      }
      final dot = file.name.lastIndexOf('.');
      final extension = dot >= 0 ? file.name.substring(dot + 1) : 'jpg';
      await ref
          .read(appearanceProvider.notifier)
          .importBackgroundFromBytes(bytes, extension);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('背景已更新')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置背景失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = ref.watch(appearanceProvider);
    final plan = ref.watch(learningPlanProvider);
    final onlineVideo = ref.watch(onlineVideoSettingsProvider);
    final tokenizer = ref.watch(tokenizerModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('AI 接口', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '兼容 OpenAI Chat Completions 的接口，支持自定义服务商。密钥保存在系统安全存储中。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _baseUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com/v1',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    hintText: 'gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.network_check),
                        label: Text(_testing ? '测试中…' : '测试连接'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _save(),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('保存'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 12),
                Text('学习计划', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '每日新学与复习数量会用于生成今天的词汇任务，超出部分留到以后。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _PlanSlider(
                  label: '每日新学',
                  unit: '个',
                  value: plan.newPerDay,
                  max: 50,
                  step: 5,
                  onChanged: (value) => ref
                      .read(learningPlanProvider.notifier)
                      .update(plan.copyWith(newPerDay: value)),
                ),
                _PlanSlider(
                  label: '每日复习',
                  unit: '个',
                  value: plan.reviewPerDay,
                  max: 300,
                  step: 10,
                  onChanged: (value) => ref
                      .read(learningPlanProvider.notifier)
                      .update(plan.copyWith(reviewPerDay: value)),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text('分词', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '本地分词速度快。AI 预分词适合人名、复合词较多的日语文本，会增加接口请求。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<TokenizerMode>(
                  segments: const [
                    ButtonSegment(
                      value: TokenizerMode.local,
                      label: Text('本地快速'),
                    ),
                    ButtonSegment(
                      value: TokenizerMode.ai,
                      label: Text('AI 预分词'),
                    ),
                  ],
                  selected: {tokenizer.mode},
                  onSelectionChanged: (selection) => ref
                      .read(tokenizerModeProvider.notifier)
                      .update(tokenizer.copyWith(mode: selection.first)),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text('在线视频', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'B 站视频默认使用平台分配的媒体线路。直连慢或播放失败时可以换一条线路。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: onlineVideo.cdnLineId,
                  decoration: const InputDecoration(labelText: 'B 站 CDN 线路'),
                  items: [
                    for (final line in onlineCdnLines)
                      DropdownMenuItem(value: line.id, child: Text(line.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    ref
                        .read(onlineVideoSettingsProvider.notifier)
                        .update(onlineVideo.copyWith(cdnLineId: value));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.graphic_eq),
                  title: const Text('语音转写模型'),
                  subtitle: Text(onlineVideo.transcriptionModel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editTranscriptionModel,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('先缓存再播放'),
                  subtitle: const Text('避免播放器直连失败；首次播放需要等待下载'),
                  value: onlineVideo.cacheBeforePlay,
                  onChanged: (value) => ref
                      .read(onlineVideoSettingsProvider.notifier)
                      .update(
                        onlineVideo.copyWith(cacheBeforePlay: value),
                      ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text('外观与背景', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Text('主题色', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final value in appearanceSeedColors)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => ref
                            .read(appearanceProvider.notifier)
                            .update(
                              appearance.copyWith(seedColorValue: value),
                            ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: appearance.seedColorValue == value
                                ? Border.all(
                                    color: theme.colorScheme.onSurface,
                                    width: 2.5,
                                  )
                                : null,
                          ),
                          child: appearance.seedColorValue == value
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('显示模式', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                    ),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {appearance.themeMode},
                  onSelectionChanged: (selection) => ref
                      .read(appearanceProvider.notifier)
                      .update(
                        appearance.copyWith(themeMode: selection.first),
                      ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: const Text('自定义背景'),
                  subtitle: Text(
                    appearance.hasBackground ? '已设置背景图片' : '未设置',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (appearance.hasBackground)
                        IconButton(
                          tooltip: '移除背景',
                          onPressed: () => ref
                              .read(appearanceProvider.notifier)
                              .clearBackground(),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      TextButton(
                        onPressed: _pickBackground,
                        child: const Text('选择图片'),
                      ),
                    ],
                  ),
                ),
                if (appearance.hasBackground) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('半透明遮罩'),
                    subtitle: const Text('提升文字在背景图上的可读性'),
                    value: appearance.scrimEnabled,
                    onChanged: (value) => ref
                        .read(appearanceProvider.notifier)
                        .update(appearance.copyWith(scrimEnabled: value)),
                  ),
                  if (appearance.scrimEnabled)
                    Row(
                      children: [
                        const Text('遮罩浓度'),
                        Expanded(
                          child: Slider(
                            value: appearance.scrimOpacity.clamp(0.1, 0.85),
                            min: 0.1,
                            max: 0.85,
                            divisions: 15,
                            label:
                                '${(appearance.scrimOpacity * 100).round()}%',
                            onChanged: (value) => ref
                                .read(appearanceProvider.notifier)
                                .update(
                                  appearance.copyWith(scrimOpacity: value),
                                ),
                          ),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('LangLearn'),
                  subtitle: const Text('版本 0.8.3 · 视频字幕 / 词汇 / 语法 / 音乐歌词'),
                ),
              ],
            ),
    );
  }
}

class _PlanSlider extends StatelessWidget {
  const _PlanSlider({
    required this.label,
    required this.unit,
    required this.value,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final String unit;
  final int value;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.labelLarge),
            ),
            Text(
              '$value $unit',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0, max).toDouble(),
          min: 0,
          max: max.toDouble(),
          divisions: max ~/ step,
          label: '$value$unit',
          onChanged: (raw) => onChanged((raw / step).round() * step),
        ),
      ],
    );
  }
}
