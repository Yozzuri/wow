import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/library/lyrics_store.dart';
import 'package:langlearn/core/media/media_session_service.dart';
import 'package:langlearn/core/models/content_document.dart';
import 'package:langlearn/core/text/normalize.dart';

LyricsEntry _entry(String title, String artist) {
  return LyricsEntry(
    filePath: '$title-$artist.json',
    document: ContentDocument(
      kind: ContentKind.music,
      meta: ContentMeta(title: title, source: artist),
      segments: const [
        ContentSegment(index: 0, startMs: 0, endMs: 3000, text: 'line'),
      ],
    ),
  );
}

void main() {
  test('normalizeForMatch removes brackets and punctuation', () {
    expect(normalizeForMatch('怪物 (TV动画《BEASTARS》第二季片头曲)'), '怪物');
    expect(normalizeForMatch('Hello, World!'), 'helloworld');
  });

  test('matches title with bracketed suffix and artist', () {
    const store = LyricsStore();
    final entries = [_entry('怪物', 'YOASOBI')];
    const nowPlaying = NowPlaying(title: '怪物 (TV动画)', artist: 'YOASOBI');
    final match = store.match(nowPlaying, entries);
    expect(match, isNotNull);
    expect(match!.title, '怪物');
  });

  test('returns null for a different song', () {
    const store = LyricsStore();
    final entries = [_entry('夜に駆ける', 'YOASOBI')];
    const nowPlaying = NowPlaying(title: '怪物', artist: 'YOASOBI');
    expect(store.match(nowPlaying, entries), isNull);
  });
}
