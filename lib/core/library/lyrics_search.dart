import 'dart:convert';

import 'package:http/http.dart' as http;

class LyricsSearchResult {
  const LyricsSearchResult({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.lyrics,
    required this.source,
    required this.synced,
  });

  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String lyrics;
  final String source;
  final bool synced;
}

class LyricsSearchService {
  const LyricsSearchService();

  static const _headers = {
    'User-Agent': 'LangLearn/0.2.0 (personal language learning app)',
    'Accept': 'application/json',
  };

  Future<List<LyricsSearchResult>> search({
    required String title,
    required String artist,
    int? durationMs,
  }) async {
    final results = <LyricsSearchResult>[];
    try {
      results.addAll(await _searchLrclib(title, artist, durationMs));
    } catch (_) {
      // Fall through to the fallback provider.
    }
    if (results.isEmpty && title.trim().isNotEmpty) {
      try {
        results.addAll(await _searchNetease(title, artist));
      } catch (_) {
        // Return whatever has been collected.
      }
    }
    return results;
  }

  Future<List<LyricsSearchResult>> _searchLrclib(
    String title,
    String artist,
    int? durationMs,
  ) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': title.trim(),
      if (artist.trim().isNotEmpty) 'artist_name': artist.trim(),
    });
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      return const [];
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      return const [];
    }
    final results = <LyricsSearchResult>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final synced = (item['syncedLyrics'] as String? ?? '').trim();
      final plain = (item['plainLyrics'] as String? ?? '').trim();
      final lyrics = synced.isNotEmpty ? synced : plain;
      if (lyrics.isEmpty) {
        continue;
      }
      final duration = (item['duration'] as num?)?.toInt() ?? 0;
      results.add(
        LyricsSearchResult(
          title: item['trackName'] as String? ?? title,
          artist: item['artistName'] as String? ?? artist,
          album: item['albumName'] as String? ?? '',
          durationMs: duration * 1000,
          lyrics: lyrics,
          source: 'LRCLIB',
          synced: synced.isNotEmpty,
        ),
      );
    }
    if (durationMs != null && durationMs > 0) {
      results.sort((a, b) {
        final da = (a.durationMs - durationMs).abs();
        final db = (b.durationMs - durationMs).abs();
        return da.compareTo(db);
      });
    }
    return results.take(20).toList();
  }

  Future<List<LyricsSearchResult>> _searchNetease(
    String title,
    String artist,
  ) async {
    final query = [title, artist].where((value) => value.trim().isNotEmpty).join(' ');
    final searchUri = Uri.https('music.163.com', '/api/search/get', {
      's': query,
      'type': '1',
      'limit': '10',
    });
    final headers = {
      ..._headers,
      'Referer': 'https://music.163.com/',
    };
    final response = await http
        .get(searchUri, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      return const [];
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      return const [];
    }
    final result = decoded['result'];
    final songs = result is Map ? result['songs'] : null;
    if (songs is! List) {
      return const [];
    }
    final results = <LyricsSearchResult>[];
    for (final song in songs.whereType<Map>().take(3)) {
      final id = song['id'];
      if (id is! num) {
        continue;
      }
      try {
        final lyricUri = Uri.https('music.163.com', '/api/song/lyric', {
          'id': id.toInt().toString(),
          'lv': '-1',
          'kv': '-1',
          'tv': '-1',
        });
        final lyricResponse = await http
            .get(lyricUri, headers: headers)
            .timeout(const Duration(seconds: 15));
        if (lyricResponse.statusCode != 200) {
          continue;
        }
        final lyricJson = jsonDecode(utf8.decode(lyricResponse.bodyBytes));
        if (lyricJson is! Map) {
          continue;
        }
        final lrc = lyricJson['lrc'];
        final lyric = lrc is Map ? (lrc['lyric'] as String? ?? '').trim() : '';
        if (lyric.isEmpty) {
          continue;
        }
        final artists = song['artists'];
        final artistName = artists is List
            ? artists
                  .whereType<Map>()
                  .map((item) => item['name']?.toString() ?? '')
                  .where((name) => name.isNotEmpty)
                  .join('/')
            : '';
        final album = song['album'];
        results.add(
          LyricsSearchResult(
            title: song['name']?.toString() ?? title,
            artist: artistName.isNotEmpty ? artistName : artist,
            album: album is Map ? (album['name']?.toString() ?? '') : '',
            durationMs: (song['duration'] as num?)?.toInt() ?? 0,
            lyrics: lyric,
            source: '网易云',
            synced: RegExp(r'\[\d{1,3}:\d{1,2}').hasMatch(lyric),
          ),
        );
      } catch (_) {
        // Skip this candidate.
      }
    }
    return results;
  }
}
