import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/module_card.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('实战')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '把学到的语言用起来：看视频、听歌、读原文，随时点词查词。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ModuleCard(
            icon: Icons.smart_display_outlined,
            title: '视频',
            subtitle: '本地或在线视频，字幕逐句解析',
            onTap: () => context.go('/practice/video'),
          ),
          ModuleCard(
            icon: Icons.music_note_outlined,
            title: '音乐',
            subtitle: '跟随系统播放，沉浸式滚动歌词',
            onTap: () => context.go('/practice/music'),
          ),
          ModuleCard(
            icon: Icons.auto_stories_outlined,
            title: '阅读',
            subtitle: '导入 txt / epub，分章翻译与点词',
            onTap: () => context.go('/practice/reading'),
          ),
        ],
      ),
    );
  }
}
