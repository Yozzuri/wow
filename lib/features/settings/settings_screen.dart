import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('LangLearn'),
                  subtitle: const Text('版本 0.1.0 · 视频字幕 / 词汇 / 语法 / 音乐歌词'),
                ),
              ],
            ),
    );
  }
}
