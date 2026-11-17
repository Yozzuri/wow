import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/video/online_video.dart';

void main() {
  test('recognizes direct media links', () {
    expect(
      isDirectMediaUri(Uri.parse('https://cdn.example.com/a/b.mp4?token=1')),
      isTrue,
    );
    expect(
      isDirectMediaUri(Uri.parse('https://cdn.example.com/live/index.m3u8')),
      isTrue,
    );
    expect(
      isDirectMediaUri(
        Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
      ),
      isFalse,
    );
  });

  test('extracts Bilibili ids from page links', () {
    final bvid = parseBilibiliIds(
      'https://www.bilibili.com/video/BV1xx411c7mD?p=1',
    );
    expect(bvid?.bvid, 'BV1xx411c7mD');

    final aid = parseBilibiliIds('https://www.bilibili.com/video/av12345');
    expect(aid?.aid, '12345');

    expect(parseBilibiliIds('https://example.com/video'), isNull);
  });

  test('converts Bilibili subtitle json to SRT', () {
    final srt = bilibiliSubtitleToSrt([
      {'from': 1.25, 'to': 3.5, 'content': 'こんにちは'},
      {'from': 4, 'to': 5.25, 'content': '世界'},
    ]);
    expect(srt, contains('00:00:01,250 --> 00:00:03,500'));
    expect(srt, contains('こんにちは'));
    expect(srt, contains('00:00:04,000 --> 00:00:05,250'));
  });

  test('rewrites only bilivideo hosts to the selected CDN', () {
    final source = Uri.parse(
      'https://upos-sz-estgoss.bilivideo.com/a/b.mp4?token=1',
    );
    final ali = applyBilibiliCdn(
      source,
      'upos-sz-mirrorali.bilivideo.com',
    );
    expect(ali.host, 'upos-sz-mirrorali.bilivideo.com');
    expect(ali.query, source.query);

    final other = Uri.parse('https://example.com/a.mp4?token=1');
    expect(
      applyBilibiliCdn(other, 'upos-sz-mirrorali.bilivideo.com').host,
      'example.com',
    );
    expect(applyBilibiliCdn(source, null), source);
  });

  test('maps app languages to subtitle api codes', () {
    expect(subtitleLanguageCode('en'), 'eng');
    expect(subtitleLanguageCode('ja'), 'jpn');
    expect(subtitleLanguageCode('zh'), 'chi');
    expect(subtitleLanguageCode('xx'), isNull);
  });
}
