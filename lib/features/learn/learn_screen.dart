import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/module_card.dart';

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('学习')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '按每日计划学习词汇，语法知识会逐步补上。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ModuleCard(
            icon: Icons.style_outlined,
            title: '词汇',
            subtitle: '每日新学与复习、艾宾浩斯排程、打卡',
            onTap: () => context.go('/learn/vocab'),
          ),
          ModuleCard(
            icon: Icons.menu_book_outlined,
            title: '语法',
            subtitle: '语法课程与 AI 讲解',
            onTap: () => context.go('/learn/grammar'),
          ),
        ],
      ),
    );
  }
}
