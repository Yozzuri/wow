import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_background.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/appearance/appearance_settings.dart';
import 'core/challenge/challenge_widget_sync.dart';
import 'core/vocab/checkin_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LangLearnApp()));
  unawaited(const CheckinStore().syncWidget());
  unawaited(ChallengeWidgetSync.sync());
}

class LangLearnApp extends ConsumerWidget {
  const LangLearnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    return MaterialApp.router(
      title: 'LangLearn',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        Brightness.light,
        appearance.seedColor,
        translucent: appearance.hasBackground,
      ),
      darkTheme: buildTheme(
        Brightness.dark,
        appearance.seedColor,
        translucent: appearance.hasBackground,
      ),
      themeMode: appearance.themeMode,
      routerConfig: appRouter,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final backgroundPath = appearance.backgroundPath;
        if (backgroundPath == null || backgroundPath.isEmpty) {
          return content;
        }
        final brightness = Theme.of(context).brightness;
        final scrimColor = brightness == Brightness.dark
            ? Colors.black
            : Colors.white;
        return AppBackground(
          path: backgroundPath,
          scrimColor: scrimColor,
          scrimOpacity: appearance.scrimEnabled
              ? appearance.scrimOpacity
              : 0,
          child: content,
        );
      },
    );
  }
}
