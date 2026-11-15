import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/appearance/appearance_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LangLearnApp()));
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
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(backgroundPath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
            if (appearance.scrimEnabled)
              ColoredBox(
                color: scrimColor.withValues(
                  alpha: appearance.scrimOpacity.clamp(0.0, 0.85),
                ),
              ),
            content,
          ],
        );
      },
    );
  }
}
