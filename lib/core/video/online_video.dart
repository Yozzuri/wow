import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_document.dart';
import '../net/platform_http.dart';
import '../subtitle/subtitle_parser.dart';

class OnlineVideoException implements Exception {
  OnlineVideoException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BilibiliIds {
  const BilibiliIds({this.bvid, this.aid});
  final String? bvid;
  final String? aid;
}

class OnlineVideoResult {
  const OnlineVideoResult({
    required this.pageUrl,
    required this.mediaUrl,
    required this.title,
    required this.headers,
    this.document,
    this.subtitleLabel,
  });

  final Uri pageUrl;
  final Uri mediaUrl;
  final String title;
  final Map<String, String> headers;
  final ContentDocument? document;
  final String? subtitleLabel;
}

class OnlineVideoHistoryEntry {
  const OnlineVideoHistoryEntry({
    required this.url,
    required this.title,
    required this.savedAt,
  });

  final String url;
  final String title;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'savedAt': savedAt.toIso8601String(),
  };

  factory OnlineVideoHistoryEntry.fromJson(Map<String, dynamic> json) =>
      OnlineVideoHistoryEntry(
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '',
        savedAt:
            DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class OnlineVideoHistoryStore {
  const OnlineVideoHistoryStore();

  static const _key = 'online_video_history_v1';

  Future<List<OnlineVideoHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <OnlineVideoHistoryEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <OnlineVideoHistoryEntry>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                OnlineVideoHistoryEntry.fromJson(item.cast<String, dynamic>()),
          )
          .where((entry) => entry.url.isNotEmpty)
          .toList();
    } catch (_) {
      return <OnlineVideoHistoryEntry>[];
    }
  }

  Future<List<OnlineVideoHistoryEntry>> add(
    OnlineVideoHistoryEntry entry,
  ) async {
    final entries = [...await load()];
    entries.removeWhere((item) => item.url == entry.url);
    entries.insert(0, entry);
    final trimmed = entries.take(20).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((item) => item.toJson()).toList()),
    );
    return trimmed;
  }

  Future<List<OnlineVideoHistoryEntry>> remove(String url) async {
    final entries = [...await load()]..removeWhere((item) => item.url == url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((item) => item.toJson()).toList()),
    );
    return entries;
  }
}

const String _browserUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

const Set<String> _mediaExtensions = {
  'mp4',
  'm4v',
  'webm',
  'mkv',
  'mov',
  'm3u8',
  'mpd',
  'flv',
  'ts',
  'm4s',
};

bool isDirectMediaUri(Uri uri) {
  final path = uri.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) {
    return false;
  }
  return _mediaExtensions.contains(path.substring(dot + 1));
}

BilibiliIds? parseBilibiliIds(String url) {
  final bvid =
      RegExp(r'(BV[0-9A-Za-z]{10})').firstMatch(url)?.group(1) ??
      Uri.tryParse(url)?.queryParameters['bvid'];
  final aid =
      RegExp(
        r'/video/av(\d+)',
        caseSensitive: false,
      ).firstMatch(url)?.group(1) ??
      Uri.tryParse(url)?.queryParameters['aid'];
  if ((bvid == null || bvid.isEmpty) && (aid == null || aid.isEmpty)) {
    return null;
  }
  return BilibiliIds(bvid: bvid, aid: aid);
}

String? subtitleLanguageCode(String language) {
  return switch (language) {
    'en' => 'eng',
    'ja' => 'jpn',
    'zh' => 'chi',
    'ko' => 'kor',
    'es' => 'spa',
    'fr' => 'fre',
    'de' => 'ger',
    'ru' => 'rus',
    'th' => 'tha',
    'ar' => 'ara',
    _ => null,
  };
}

String bilibiliSubtitleToSrt(List<dynamic> body) {
  final buffer = StringBuffer();
  var index = 1;
  for (final item in body) {
    if (item is! Map) {
      continue;
    }
    final from = (item['from'] as num?)?.toDouble();
    final to = (item['to'] as num?)?.toDouble();
    final content = (item['content'] as String? ?? '').trim();
    if (from == null || to == null || content.isEmpty) {
      continue;
    }
    buffer.writeln(index++);
    buffer.writeln(
      '${_srtTime((from * 1000).round())} --> ${_srtTime((to * 1000).round())}',
    );
    buffer.writeln(content.replaceAll(RegExp(r'\s*\n\s*'), ' '));
    buffer.writeln();
  }
  return buffer.toString();
}

String _srtTime(int ms) {
  final hours = ms ~/ 3600000;
  final minutes = (ms % 3600000) ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  final millis = ms % 1000;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(hours)}:${two(minutes)}:${two(seconds)},${millis.toString().padLeft(3, '0')}';
}

class OnlineVideoService {
  const OnlineVideoService();

  Future<OnlineVideoResult> resolve(
    String rawUrl, {
    required String language,
    bool fetchSubtitles = true,
  }) async {
    var uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      uri = Uri.tryParse('https://${rawUrl.trim()}');
    }
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw OnlineVideoException('请输入 http 或 https 开头的视频地址');
    }
    if (isDirectMediaUri(uri)) {
      final title = _titleFromUri(uri);
      final document = fetchSubtitles
          ? await _openSubtitles(title, language)
          : null;
      return OnlineVideoResult(
        pageUrl: uri,
        mediaUrl: uri,
        title: title,
        headers: const {'User-Agent': _browserUserAgent},
        document: document,
        subtitleLabel: document == null ? null : '在线字幕 · OpenSubtitles',
      );
    }

    final PlatformHttpResponse response;
    try {
      response = await PlatformHttp.get(
        uri,
        headers: const {'User-Agent': _browserUserAgent},
      );
    } on PlatformHttpException catch (error) {
      throw OnlineVideoException(
        '无法访问 ${uri.host}：$error。可能是网络或代理拦截，可换网络后重试。',
      );
    }
    if (response.status < 200 || response.status >= 400) {
      throw OnlineVideoException('页面请求失败：HTTP ${response.status}');
    }
    final finalUri = response.finalUrl;
    final html = utf8.decode(response.body, allowMalformed: true);
    if (finalUri.host.contains('bilibili.com') ||
        finalUri.host.contains('b23.tv')) {
      return _resolveBilibili(
        finalUri,
        html,
        language: language,
        fetchSubtitles: fetchSubtitles,
      );
    }
    final mediaUrl = _extractMediaUrl(html, finalUri);
    if (mediaUrl == null) {
      throw OnlineVideoException('没有在这个页面找到可播放的视频地址。目前实验性支持直链和部分网页。');
    }
    final title = _extractTitle(html) ?? _titleFromUri(finalUri);
    final document = fetchSubtitles
        ? await _openSubtitles(title, language)
        : null;
    return OnlineVideoResult(
      pageUrl: finalUri,
      mediaUrl: mediaUrl,
      title: title,
      headers: {
        'User-Agent': _browserUserAgent,
        'Referer': finalUri.toString(),
      },
      document: document,
      subtitleLabel: document == null ? null : '在线字幕 · OpenSubtitles',
    );
  }

  Future<OnlineVideoResult> _resolveBilibili(
    Uri pageUri,
    String html, {
    required String language,
    required bool fetchSubtitles,
  }) async {
    final ids = parseBilibiliIds(pageUri.toString());
    if (ids == null) {
      throw OnlineVideoException('无法从链接中识别 B 站视频 ID');
    }
    final headers = {
      'User-Agent': _browserUserAgent,
      'Referer': pageUri.toString(),
      'Origin': 'https://www.bilibili.com',
    };
    final view = await _getJson(
      'https://api.bilibili.com/x/web-interface/view',
      {
        if (ids.bvid != null) 'bvid': ids.bvid!,
        if (ids.aid != null) 'aid': ids.aid!,
      },
      headers,
    );
    final data = view['data'];
    if (data is! Map) {
      throw OnlineVideoException('B 站视频信息获取失败');
    }
    final title = (data['title'] as String? ?? '').trim().isEmpty
        ? _extractTitle(html) ?? 'Bilibili 视频'
        : (data['title'] as String).trim();
    final bvid = ids.bvid ?? data['bvid'] as String?;
    final aid = ids.aid ?? (data['aid'] as num?)?.toString();
    final pages = data['pages'];
    final cid =
        (data['cid'] as num?)?.toString() ??
        (pages is List && pages.isNotEmpty && pages.first is Map
            ? (pages.first['cid'] as num?)?.toString()
            : null);
    if (cid == null) {
      throw OnlineVideoException('B 站视频缺少 cid');
    }
    final play = await _getJson('https://api.bilibili.com/x/player/playurl', {
      if (bvid != null) 'bvid': bvid,
      if (bvid == null && aid != null) 'avid': aid,
      'cid': cid,
      'qn': '64',
      'fnval': '0',
      'fourk': '0',
      'fnver': '0',
      'platform': 'html5',
      'high_quality': '1',
    }, headers);
    final playData = play['data'];
    String? media;
    if (playData is Map) {
      final durl = playData['durl'];
      if (durl is List && durl.isNotEmpty && durl.first is Map) {
        media = durl.first['url'] as String?;
      }
      if (media == null) {
        final dash = playData['dash'];
        if (dash is Map) {
          final videos = dash['video'];
          if (videos is List && videos.isNotEmpty && videos.first is Map) {
            media = videos.first['baseUrl'] as String?;
          }
        }
      }
    }
    if (media == null || media.isEmpty) {
      throw OnlineVideoException('没有取到 B 站视频流，可能需要登录或该视频受限');
    }
    ContentDocument? document;
    String? label;
    if (fetchSubtitles) {
      final subtitle = await _bilibiliSubtitle(
        bvid: bvid,
        aid: aid,
        cid: cid,
        headers: headers,
        language: language,
        title: title,
        source: pageUri.toString(),
      );
      document = subtitle?.key;
      label = subtitle?.value;
    }
    var mediaUri = Uri.parse(media);
    if (mediaUri.scheme == 'http' &&
        (mediaUri.host.contains('bilivideo.com') ||
            mediaUri.host.contains('hdslb.com') ||
            mediaUri.host.contains('bilibili.com'))) {
      mediaUri = mediaUri.replace(scheme: 'https');
    }
    return OnlineVideoResult(
      pageUrl: pageUri,
      mediaUrl: mediaUri,
      title: title,
      headers: headers,
      document: document,
      subtitleLabel: label,
    );
  }

  Future<MapEntry<ContentDocument, String>?> _bilibiliSubtitle({
    required String? bvid,
    required String? aid,
    required String cid,
    required Map<String, String> headers,
    required String language,
    required String title,
    required String source,
  }) async {
    try {
      final json = await _getJson('https://api.bilibili.com/x/player/v2', {
        if (bvid != null) 'bvid': bvid,
        if (bvid == null && aid != null) 'aid': aid,
        'cid': cid,
      }, headers);
      final data = json['data'];
      final subtitle = data is Map ? data['subtitle'] : null;
      final list = subtitle is Map ? subtitle['subtitles'] : null;
      if (list is! List || list.isEmpty) {
        return null;
      }
      Map? chosen;
      for (final item in list.whereType<Map>()) {
        final lan = (item['lan'] as String? ?? '').toLowerCase();
        if (lan.startsWith(language) ||
            (language == 'zh' && lan.startsWith('zh'))) {
          chosen = item;
          break;
        }
      }
      chosen ??= list.whereType<Map>().first;
      final url = chosen['subtitle_url'] as String?;
      if (url == null || url.isEmpty) {
        return null;
      }
      final subtitleUri = url.startsWith('//')
          ? Uri.parse('https:$url')
          : Uri.parse(url);
      final response = await PlatformHttp.get(
        subtitleUri,
        headers: {'User-Agent': _browserUserAgent},
      );
      if (response.status < 200 || response.status >= 300) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.body));
      final body = decoded is Map ? decoded['body'] : null;
      if (body is! List || body.isEmpty) {
        return null;
      }
      final srt = bilibiliSubtitleToSrt(body);
      final parsed = SubtitleParser.parse(srt, fileName: 'bilibili.srt');
      if (parsed.segments.isEmpty) {
        return null;
      }
      final lan = (chosen['lan'] as String? ?? language).toLowerCase();
      final code = lan.startsWith('zh')
          ? 'zh'
          : lan.startsWith('ja')
          ? 'ja'
          : lan.startsWith('en')
          ? 'en'
          : lan.startsWith('ko')
          ? 'ko'
          : language;
      return MapEntry(
        ContentDocument(
          meta: ContentMeta(title: title, source: source, language: code),
          segments: parsed.segments,
        ),
        'B 站字幕 · $lan',
      );
    } catch (_) {
      return null;
    }
  }

  Future<ContentDocument?> _openSubtitles(String title, String language) async {
    final code = subtitleLanguageCode(language);
    if (code == null || title.trim().isEmpty) {
      return null;
    }
    try {
      final uri = Uri.https(
        'rest.opensubtitles.org',
        '/search/query-${Uri.encodeComponent(title.trim())}/sublanguageid-$code',
      );
      final response = await PlatformHttp.get(
        uri,
        headers: const {
          'User-Agent': 'TemporaryUserAgent',
          'X-User-Agent': 'TemporaryUserAgent',
          'Accept': 'application/json',
        },
      );
      if (response.status != 200) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! List) {
        return null;
      }
      for (final item in decoded.whereType<Map>()) {
        final link = item['SubDownloadLink'] as String?;
        if (link == null || !link.startsWith('http')) {
          continue;
        }
        final download = await PlatformHttp.get(
          Uri.parse(link),
          headers: const {
            'User-Agent': 'TemporaryUserAgent',
            'X-User-Agent': 'TemporaryUserAgent',
          },
        );
        if (download.status != 200) {
          continue;
        }
        final bytes = download.body;
        List<int> textBytes = bytes;
        if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
          textBytes = gzip.decode(bytes);
        }
        var text = utf8.decode(textBytes, allowMalformed: true);
        if (text.contains('\uFFFD')) {
          text = latin1.decode(textBytes, allowInvalid: true);
        }
        final parsed = SubtitleParser.parse(
          text,
          fileName: (item['SubFileName'] as String? ?? 'subtitle.srt'),
        );
        if (parsed.segments.isEmpty) {
          continue;
        }
        return ContentDocument(
          meta: ContentMeta(
            title: (item['MovieName'] as String? ?? title).trim(),
            source: 'OpenSubtitles',
            language: language,
          ),
          segments: parsed.segments,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>> _getJson(
    String url,
    Map<String, String> query,
    Map<String, String> headers,
  ) async {
    final uri = Uri.https(Uri.parse(url).host, Uri.parse(url).path, query);
    final response = await PlatformHttp.get(uri, headers: headers);
    if (response.status != 200) {
      throw OnlineVideoException('接口请求失败：HTTP ${response.status}');
    }
    final decoded = jsonDecode(utf8.decode(response.body));
    if (decoded is! Map) {
      throw OnlineVideoException('接口返回格式异常');
    }
    return decoded.cast<String, dynamic>();
  }
}

String _titleFromUri(Uri uri) {
  final segments = uri.pathSegments;
  final last = segments.isEmpty ? '' : segments.last;
  final dot = last.lastIndexOf('.');
  final name = dot > 0 ? last.substring(0, dot) : last;
  return Uri.decodeComponent(name).trim().isEmpty
      ? '在线视频'
      : Uri.decodeComponent(name).trim();
}

String? _extractTitle(String html) {
  final meta = _metaContent(html, const ['og:title', 'twitter:title']);
  if (meta != null && meta.trim().isNotEmpty) {
    return meta.trim();
  }
  final match = RegExp(
    r'<title[^>]*>([^<]*)</title>',
    caseSensitive: false,
  ).firstMatch(html);
  final title = match?.group(1)?.trim();
  if (title == null || title.isEmpty) {
    return null;
  }
  return title
      .replaceAll(
        RegExp(r'\s*[-_|]\s*(bilibili|哔哩哔哩).*$', caseSensitive: false),
        '',
      )
      .trim();
}

Uri? _extractMediaUrl(String html, Uri base) {
  final candidates = <String>[];
  final meta = _metaContent(html, const [
    'og:video',
    'og:video:url',
    'og:video:secure_url',
    'twitter:player:stream',
  ]);
  if (meta != null) {
    candidates.add(meta);
  }
  for (final pattern in [
    RegExp("<video[^>]+src=[\\x22\\x27]([^\\x22\\x27]+)", caseSensitive: false),
    RegExp(
      "<source[^>]+src=[\\x22\\x27]([^\\x22\\x27]+)",
      caseSensitive: false,
    ),
    RegExp(r'"contentUrl"\s*:\s*"([^"]+)"'),
  ]) {
    for (final match in pattern.allMatches(html)) {
      final value = match.group(1);
      if (value != null) {
        candidates.add(value);
      }
    }
  }
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('blob:') ||
        trimmed.startsWith('data:')) {
      continue;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      continue;
    }
    final resolved = uri.hasScheme ? uri : base.resolveUri(uri);
    if (resolved.scheme == 'http' || resolved.scheme == 'https') {
      return resolved;
    }
  }
  return null;
}

String? _metaContent(String html, List<String> names) {
  final pattern = RegExp(r'<meta\s+([^>]+)>', caseSensitive: false);
  for (final match in pattern.allMatches(html)) {
    final attrs = match.group(1) ?? '';
    final property = RegExp(
      "(?:property|name)\\s*=\\s*[\\x22\\x27]([^\\x22\\x27]+)",
      caseSensitive: false,
    ).firstMatch(attrs)?.group(1)?.toLowerCase();
    if (property == null || !names.contains(property)) {
      continue;
    }
    final content = RegExp(
      "content\\s*=\\s*[\\x22\\x27]([^\\x22\\x27]*)",
      caseSensitive: false,
    ).firstMatch(attrs)?.group(1);
    if (content != null && content.trim().isNotEmpty) {
      return content.trim();
    }
  }
  return null;
}
