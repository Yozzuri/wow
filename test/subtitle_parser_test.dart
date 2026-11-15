import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/subtitle/subtitle_parser.dart';

void main() {
  group('SubtitleParser', () {
    test('parses SRT with tags and multiline text', () {
      const raw = '''
1
00:00:01,000 --> 00:00:03,500
Hello <i>world</i>

2
00:00:04,000 --> 00:00:06,000
Second line
with a break
''';
      final result = SubtitleParser.parse(raw, fileName: 'movie.srt');
      expect(result.format, 'srt');
      expect(result.segments, hasLength(2));
      expect(result.segments.first.startMs, 1000);
      expect(result.segments.first.endMs, 3500);
      expect(result.segments.first.text, 'Hello world');
      expect(result.segments.last.text, 'Second line\nwith a break');
    });

    test('parses VTT with settings and NOTE blocks', () {
      const raw = '''
WEBVTT

NOTE this is a comment

00:00:01.000 --> 00:00:02.500 align:start position:0%
Hi there

00:00:03.000 --> 00:00:04.000
Bye
''';
      final result = SubtitleParser.parse(raw, fileName: 'movie.vtt');
      expect(result.format, 'vtt');
      expect(result.segments, hasLength(2));
      expect(result.segments.first.endMs, 2500);
      expect(result.segments.first.text, 'Hi there');
    });

    test('parses ASS dialogue lines', () {
      const raw = '''
[Script Info]
Title: demo

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\\i1}Hello{\\i0}\\Nworld
''';
      final result = SubtitleParser.parse(raw, fileName: 'movie.ass');
      expect(result.format, 'ass');
      expect(result.segments, hasLength(1));
      expect(result.segments.first.startMs, 1000);
      expect(result.segments.first.endMs, 3500);
      expect(result.segments.first.text, 'Hello\nworld');
    });

    test('parses LRC lines with offset', () {
      const raw = '''
[ti:Song]
[ar:Artist]
[offset:500]
[00:01.00]First line
[00:03.50][00:05.00]Chorus
''';
      final result = SubtitleParser.parse(raw, fileName: 'song.lrc');
      expect(result.format, 'lrc');
      expect(result.metadata['ti'], 'Song');
      expect(result.metadata['ar'], 'Artist');
      expect(result.segments, hasLength(3));
      expect(result.segments.first.startMs, 500);
      expect(result.segments[1].startMs, 3000);
      expect(result.segments[2].startMs, 4500);
    });
  });
}
