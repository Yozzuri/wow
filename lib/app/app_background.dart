import 'dart:io';

import 'package:flutter/material.dart';

/// Draws the wallpaper behind the whole navigator.
///
/// Two things matter for smooth page transitions:
/// 1. The decoded image is kept alive and wrapped in a [RepaintBoundary], so
///    route animations do not repaint or re-upload the wallpaper every frame.
/// 2. It is decoded at screen resolution instead of the original size, which
///    keeps it inside Flutter's image cache and avoids re-decoding between
///    route builds.
class AppBackground extends StatefulWidget {
  const AppBackground({
    super.key,
    required this.path,
    required this.scrimColor,
    required this.scrimOpacity,
    required this.child,
  });

  final String path;
  final Color scrimColor;
  final double scrimOpacity;
  final Widget child;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  ImageProvider? _provider;
  String? _providerPath;
  int? _providerWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final logicalWidth = MediaQuery.sizeOf(context).width;
    final targetWidth = (logicalWidth * ratio).round().clamp(320, 2048);
    if (_providerPath == widget.path && _providerWidth == targetWidth) {
      return;
    }
    _providerPath = widget.path;
    _providerWidth = targetWidth;
    final provider = ResizeImage(
      FileImage(File(widget.path)),
      width: targetWidth,
      allowUpscaling: false,
    );
    _provider = provider;
    // Warm the cache so the first route transition already has the pixels.
    precacheImage(provider, context).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opacity = widget.scrimOpacity.clamp(0.0, 0.85);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.colorScheme.surface),
        if (_provider != null)
          RepaintBoundary(
            child: Image(
              image: _provider!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        if (opacity > 0)
          IgnorePointer(
            child: ColoredBox(
              color: widget.scrimColor.withValues(alpha: opacity),
            ),
          ),
        widget.child,
      ],
    );
  }
}
