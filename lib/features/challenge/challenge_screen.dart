import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class ChallengeScreen extends StatelessWidget {
  const ChallengeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: '挑战',
      icon: Icons.emoji_events_outlined,
      description: '挑战模式还在准备中。\n（下一步开发）',
    );
  }
}
