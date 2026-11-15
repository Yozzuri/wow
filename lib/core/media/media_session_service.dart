import 'package:flutter/services.dart';

class NowPlaying {
  const NowPlaying({
    this.title,
    this.artist,
    this.album,
    this.packageName,
    this.durationMs = 0,
    this.positionMs = 0,
    this.isPlaying = false,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? packageName;
  final int durationMs;
  final int positionMs;
  final bool isPlaying;

  bool get hasSong => (title ?? '').trim().isNotEmpty;

  factory NowPlaying.fromMap(Map<Object?, Object?> map) => NowPlaying(
    title: map['title'] as String?,
    artist: map['artist'] as String?,
    album: map['album'] as String?,
    packageName: map['packageName'] as String?,
    durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
    isPlaying: map['isPlaying'] as bool? ?? false,
  );
}

class MediaSessionService {
  const MediaSessionService();

  static const MethodChannel _channel = MethodChannel(
    'langlearn/media_session',
  );

  Future<bool> hasAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Ignore: the settings screen may be unavailable on some ROMs.
    }
  }

  Future<NowPlaying?> getNowPlaying() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getNowPlaying',
      );
      if (map == null) {
        return null;
      }
      final nowPlaying = NowPlaying.fromMap(map);
      return nowPlaying.hasSong ? nowPlaying : null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> seek(int positionMs) async {
    try {
      await _channel.invokeMethod<void>('seekTo', {
        'positionMs': positionMs,
      });
    } on PlatformException {
      // Ignore: the current session may not support seeking.
    }
  }
}
