import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/module_card.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实战')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ModuleCard(
            icon: Icons.smart_display_outlined,
            title: '视频',
            onTap: () => context.go('/practice/video'),
          ),
          ModuleCard(
            icon: Icons.music_note_outlined,
            title: '音乐',
            onTap: () => context.go('/practice/music'),
          ),
          ModuleCard(
            icon: Icons.auto_stories_outlined,
            title: '阅读',
            onTap: () => context.go('/practice/reading'),
          ),
        ],
      ),
    );
  }
}
