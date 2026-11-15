import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../media/media_session_service.dart';
import '../models/content_document.dart';
import '../text/normalize.dart';

class LyricsEntry {
  const LyricsEntry({required this.filePath, required this.document});

  final String filePath;
  final ContentDocument document;

  String get title => document.meta.title;
  String get artist => document.meta.source ?? '';
}

class LyricsStore {
  const LyricsStore();

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/lyrics');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _keyFor(String title, String artist) => sha1
      .convert(utf8.encode('${normalizeForMatch(title)}|${normalizeForMatch(artist)}'))
      .toString();

  Future<LyricsEntry> save(ContentDocument document) async {
    final dir = await _directory();
    final key = _keyFor(document.meta.title, document.meta.source ?? '');
    final file = File('${dir.path}/$key.json');
    await file.writeAsString(jsonEncode(document.toJson()));
    return LyricsEntry(filePath: file.path, document: document);
  }

  Future<List<LyricsEntry>> list() async {
    final dir = await _directory();
    final entries = <LyricsEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        final document = ContentDocument.fromJson(
          (json as Map).cast<String, dynamic>(),
        );
        entries.add(LyricsEntry(filePath: entity.path, document: document));
      } catch (_) {
        // Skip corrupted files rather than failing the whole list.
      }
    }
    entries.sort((a, b) => a.title.compareTo(b.title));
    return entries;
  }

  Future<void> delete(LyricsEntry entry) async {
    final file = File(entry.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  LyricsEntry? match(NowPlaying nowPlaying, List<LyricsEntry> entries) {
    if (!nowPlaying.hasSong || entries.isEmpty) {
      return null;
    }
    final title = normalizeForMatch(nowPlaying.title!);
    final artist = normalizeForMatch(nowPlaying.artist ?? '');
    LyricsEntry? best;
    var bestScore = 0;
    for (final entry in entries) {
      final entryTitle = normalizeForMatch(entry.title);
      final entryArtist = normalizeForMatch(entry.artist);
      var score = 0;
      final artistMatches =
          artist.isNotEmpty &&
          entryArtist.isNotEmpty &&
          (artist == entryArtist ||
              artist.contains(entryArtist) ||
              entryArtist.contains(artist));
      if (title.isNotEmpty && title == entryTitle) {
        score = artistMatches ? 100 : 70;
      } else if (title.isNotEmpty &&
          entryTitle.isNotEmpty &&
          (title.contains(entryTitle) || entryTitle.contains(title))) {
        score = artistMatches ? 80 : 40;
      } else if (artistMatches && entryTitle.isEmpty) {
        score = 20;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    return bestScore >= 40 ? best : null;
  }
}
