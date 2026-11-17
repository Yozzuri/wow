import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/content_document.dart';
import 'ai_settings.dart';

class TranscriptionException implements Exception {
  TranscriptionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TranscriptionService {
  const TranscriptionService();

  static const int maxBytes = 24 * 1024 * 1024;

  Future<ContentDocument> transcribe({
    required AiConfig config,
    required String filePath,
    required String language,
    required String title,
    String model = 'whisper-1',
  }) async {
    if (!config.isConfigured) {
      throw TranscriptionException('请先在设置中配置 AI 接口地址和 API Key');
    }
    final file = File(filePath);
    if (!await file.exists()) {
      throw TranscriptionException('音频文件不存在');
    }
    if (await file.length() > maxBytes) {
      throw TranscriptionException('音频超过 25MB，Transcription 接口无法一次处理');
    }
    final uri = Uri.parse('${config.normalizedBaseUrl}/audio/transcriptions');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${config.apiKey}'
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json'
      ..fields['timestamp_granularities[]'] = 'segment';
    if (language.trim().length == 2) {
      request.fields['language'] = language.trim();
    }
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: 'audio.${_extension(file.path)}',
      ),
    );
    final streamed = await request
        .send()
        .timeout(const Duration(minutes: 6));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = utf8.decode(response.bodyBytes, allowMalformed: true);
      throw TranscriptionException(
        '转写接口错误 ${response.statusCode}: '
        '${detail.length > 300 ? detail.substring(0, 300) : detail}',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw TranscriptionException('转写接口返回格式异常');
    }
    final segments = <ContentSegment>[];
    final rawSegments = decoded['segments'];
    if (rawSegments is List) {
      for (final item in rawSegments) {
        if (item is! Map) {
          continue;
        }
        final start = (item['start'] as num?)?.toDouble();
        final end = (item['end'] as num?)?.toDouble();
        final text = (item['text'] as String? ?? '').trim();
        if (start == null || end == null || text.isEmpty) {
          continue;
        }
        segments.add(
          ContentSegment(
            index: segments.length,
            startMs: (start * 1000).round(),
            endMs: (end * 1000).round(),
            text: text,
          ),
        );
      }
    }
    if (segments.isEmpty) {
      final text = (decoded['text'] as String? ?? '').trim();
      if (text.isEmpty) {
        throw TranscriptionException('没有识别到语音内容');
      }
      segments.add(
        ContentSegment(index: 0, startMs: 0, endMs: 0, text: text),
      );
    }
    final rawLanguage = (decoded['language'] as String? ?? language).toLowerCase();
    final code = rawLanguage.startsWith('ja')
        ? 'ja'
        : rawLanguage.startsWith('en')
        ? 'en'
        : rawLanguage.startsWith('zh')
        ? 'zh'
        : rawLanguage.startsWith('ko')
        ? 'ko'
        : language;
    return ContentDocument(
      meta: ContentMeta(
        title: title,
        source: 'AI 听写',
        language: code,
        durationMs: segments.last.endMs,
      ),
      segments: segments,
    );
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) {
      return 'm4a';
    }
    return path.substring(dot + 1);
  }
}
