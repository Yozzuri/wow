import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/challenge/challenge_screen.dart';
import '../features/grammar/grammar_screen.dart';
import '../features/learn/learn_screen.dart';
import '../features/music/music_screen.dart';
import '../features/practice/practice_screen.dart';
import '../features/reading/reading_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/video/video_screen.dart';
import '../features/vocab/vocab_screen.dart';

final currentTabIndexProvider = StateProvider<int>((ref) => 0);

final GoRouter appRouter = GoRouter(
  initialLocation: '/practice',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/practice',
              builder: (context, state) => const PracticeScreen(),
              routes: [
                GoRoute(
                  path: 'video',
                  builder: (context, state) => const VideoScreen(),
                ),
                GoRoute(
                  path: 'music',
                  builder: (context, state) => const MusicScreen(),
                ),
                GoRoute(
                  path: 'reading',
                  builder: (context, state) => const ReadingScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/learn',
              builder: (context, state) => const LearnScreen(),
              routes: [
                GoRoute(
                  path: 'vocab',
                  builder: (context, state) => const VocabScreen(),
                ),
                GoRoute(
                  path: 'grammar',
                  builder: (context, state) => const GrammarScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/challenge',
              builder: (context, state) => const ChallengeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          ref.read(currentTabIndexProvider.notifier).state = index;
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '实战',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '学习',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: '挑战',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
