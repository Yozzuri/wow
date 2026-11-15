import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class GrammarScreen extends StatelessWidget {
  const GrammarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: '语法',
      icon: Icons.menu_book_outlined,
      description: '语法课程与 AI 讲解会在这里展开。\n（下一步开发）',
    );
  }
}
