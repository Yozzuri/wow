import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class MusicScreen extends StatelessWidget {
  const MusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: '音乐',
      icon: Icons.music_note_outlined,
      description: '读取系统当前播放的歌曲，与已导入的 LRC 歌词匹配后同步展示。\n需要通知使用权，下一步接入原生 MediaSession。',
    );
  }
}
