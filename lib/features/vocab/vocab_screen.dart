import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class VocabScreen extends StatelessWidget {
  const VocabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: '词汇',
      icon: Icons.style_outlined,
      description: '从字幕中提取的生词会进入这里，按间隔重复算法安排复习。\n（下一步开发）',
    );
  }
}
