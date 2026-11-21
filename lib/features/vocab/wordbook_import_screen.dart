import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_settings.dart';
import '../../core/reading/reading_book.dart';
import '../../core/vocab/wordbook.dart';

String wordbookPrompt(String languageLabel, bool includePitch) {
  final pitchNote = includePitch
      ? '日语请给出音调，例如 0 / 1 / [2]。'
      : '不需要音调。';
  return '''
你是一个词书格式转换助手。请把我提供的词书文本转换成严格的 JSON，只输出 JSON，不要解释。

目标语言：$languageLabel
JSON 结构：
{
  "name": "词书名称",
  "language": "语言代码",
  "entries": [
    {
      "word": "词条原文或短语",
      "lemma": "原型",
      "surfaceReading": "当前词读音；英语用 IPA，日语用假名和音调",
      "lemmaReading": "原型读音",
      "relation": "变形或派生关系；本身是原型时留空",
      "senses": [{"pos": "n.", "meaning": "中文释义"}, {"pos": "v.", "meaning": "中文释义"}],
      "usage": "用法说明",
      "examples": ["例句"],
      "forms": [{"label": "过去式", "value": "built"}],
      "detail": "补充说明，Markdown"
    }
  ]
}

要求：
1. 每行词条输出一个 entry，不要遗漏。
2. 词性和意思必须绑定，一个词性一条 sense；按常用程度从高到低排列，最常用的意思放第一条。
3. forms 尽量补全：过去式、过去分词、三单、复数、现在分词、比较级、形容词和名词派生等。
4. 短语也作为 word 处理；固定搭配尽量写成带 ... 的模式，例如 take ... to do ...。
5. $pitchNote
6. 没有的字段用空字符串或空数组，不要输出 markdown 代码块。
''';
}

class WordbookImportScreen extends ConsumerStatefulWidget {
  const WordbookImportScreen({super.key});

  @override
  ConsumerState<WordbookImportScreen> createState() =>
      _WordbookImportScreenState();
}

class _WordbookImportScreenState extends ConsumerState<WordbookImportScreen> {
  static const _store = WordbookStore();

  final _nameController = TextEditingController(text: '导入词书');
  final _sourceController = TextEditingController();
  String _language = 'en';
  bool _importing = false;
  String? _progress;

  @override
  void dispose() {
    _nameController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  String get _languageLabel =>
      readingLanguageFor(_language).label;

  String get _prompt => wordbookPrompt(_languageLabel, _language == 'ja');

  Future<void> _loadTxt() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'csv', 'md'],
      withData: true,
    );
    final file = (result != null && result.files.isNotEmpty)
        ? result.files.first
        : null;
    if (file == null) {
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      return;
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    _sourceController.text = text;
    final detected = detectLanguage(text);
    if (mounted) {
      setState(() => _language = detected);
    }
    if (_nameController.text == '导入词书' && file.name.contains('.')) {
      _nameController.text = file.name.substring(0, file.name.lastIndexOf('.'));
    }
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(text: _prompt));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提示词已复制')));
    }
  }

  Future<void> _saveEntries(List<WordbookEntry> entries) async {
    if (entries.isEmpty) {
      throw const FormatException('没有解析到词条');
    }
    final book = Wordbook(
      id: '',
      name: _nameController.text.trim().isEmpty
          ? '导入词书'
          : _nameController.text.trim(),
      language: _language,
      createdAt: DateTime.now(),
      entries: entries,
    );
    await _store.save(book);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _importJsonText() async {
    try {
      final book = _store.parseJson(
        _sourceController.text,
        fallbackLanguage: _language,
      );
      await _saveEntries(book.entries);
    } catch (error) {
      _message('JSON 解析失败：$error');
    }
  }

  Future<void> _convertWithAi() async {
    final source = _sourceController.text.trim();
    if (source.isEmpty) {
      _message('请先粘贴或载入词书文本');
      return;
    }
    final config = await ref.read(aiConfigProvider.future);
    if (!config.isConfigured) {
      _message('请先在「设置」页配置 AI 接口');
      return;
    }
    setState(() {
      _importing = true;
      _progress = '准备中…';
    });
    try {
      final lines = source
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final chunks = <String>[];
      const chunkSize = 30;
      for (var start = 0; start < lines.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, lines.length);
        chunks.add(lines.sublist(start, end).join('\n'));
      }
      final client = AiClient(config);
      final entries = <WordbookEntry>[];
      final seen = <String>{};
      for (var index = 0; index < chunks.length; index++) {
        if (mounted) {
          setState(() => _progress = 'AI 转换中 ${index + 1}/${chunks.length}…');
        }
        final raw = await client.chat(
          messages: [
            {'role': 'system', 'content': _prompt},
            {'role': 'user', 'content': chunks[index]},
          ],
          maxTokens: 3000,
        );
        final book = _store.parseJson(raw, fallbackLanguage: _language);
        for (final entry in book.entries) {
          final key = entry.word.toLowerCase();
          if (seen.add(key)) {
            entries.add(entry);
          }
        }
      }
      await _saveEntries(entries);
    } catch (error) {
      _message('AI 转换失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _progress = null;
        });
      }
    }
  }

  void _message(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('导入词书')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'AI 转换提示词',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '复制提示词',
                        onPressed: _copyPrompt,
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '把不认识的 TXT 词书交给 AI，按下面的结构转换后再导入。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _prompt,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '词书名称'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: const InputDecoration(labelText: '词书语言'),
            items: [
              for (final language in readingLanguages)
                DropdownMenuItem(
                  value: language.code,
                  child: Text(
                    '${language.label}（${language.usesSpaces ? '空格分词' : '无空格语言'}）',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _language = value);
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importing ? null : _loadTxt,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('载入 TXT'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importing ? null : _importJsonText,
                  icon: const Icon(Icons.data_object),
                  label: const Text('按 JSON 导入'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sourceController,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: '词书文本 / JSON',
              alignLabelWithHint: true,
              hintText: '粘贴词书内容，或从文件载入',
            ),
          ),
          const SizedBox(height: 16),
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(_progress!),
                ],
              ),
            ),
          FilledButton.icon(
            onPressed: _importing ? null : _convertWithAi,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('用 AI 转换并导入'),
          ),
        ],
      ),
    );
  }
}
