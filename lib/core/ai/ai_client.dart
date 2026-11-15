import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_settings.dart';

class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiClient {
  AiClient(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final AiConfig config;
  final http.Client _client;

  Uri get _chatCompletionsUri =>
      Uri.parse('${config.normalizedBaseUrl}/chat/completions');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${config.apiKey}',
  };

  Future<String> testConnection() async {
    final content = await _complete(
      messages: [
        {
          'role': 'user',
          'content': 'Reply with the single word: ok',
        },
      ],
      maxTokens: 8,
    );
    return content.isEmpty ? 'ok' : content;
  }

  Future<String> explainWord({
    required String word,
    required String sentence,
    String language = 'en',
  }) {
    return _complete(
      messages: [
        {
          'role': 'system',
          'content':
              'You are a concise language tutor. Answer in Chinese. '
              'Explain the target word in context: phonetic, part of speech, '
              'meaning in this sentence, and one short example.',
        },
        {
          'role': 'user',
          'content':
              'Language: $language\nTarget word: $word\nSentence: $sentence',
        },
      ],
      maxTokens: 400,
    );
  }

  Future<String> translateSegments({
    required List<String> texts,
    required String language,
  }) async {
    final joined = texts.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
    return _complete(
      messages: [
        {
          'role': 'system',
          'content':
              'Translate each numbered line into Chinese. Preserve the numbering. '
              'Output only the numbered translations, one per line.',
        },
        {
          'role': 'user',
          'content': 'Source language: $language\n$joined',
        },
      ],
      maxTokens: 1500,
    );
  }

  Future<String> explainSentence({
    required String sentence,
    String language = 'en',
  }) {
    return _complete(
      messages: [
        {
          'role': 'system',
          'content':
              'You are a concise language tutor. Answer in Chinese. '
              'Translate the sentence, explain its structure briefly, and list '
              'the most useful phrases with short meanings.',
        },
        {
          'role': 'user',
          'content': 'Language: $language\nSentence: $sentence',
        },
      ],
      maxTokens: 600,
    );
  }

  Future<String> segmentText({
    required String text,
    required String language,
  }) {
    return _complete(
      messages: [
        {
          'role': 'system',
          'content':
              'Insert spaces between words in the given $language text so that '
              'each word can be looked up separately. Keep punctuation and line '
              'breaks unchanged. Output only the processed text.',
        },
        {'role': 'user', 'content': text},
      ],
      maxTokens: 3000,
    );
  }

  Future<String> chat({
    required List<Map<String, String>> messages,
    int maxTokens = 1200,
  }) => _complete(messages: messages, maxTokens: maxTokens);

  Future<String> _complete({
    required List<Map<String, String>> messages,
    int maxTokens = 400,
  }) async {    if (!config.isConfigured) {
      throw AiException('请先在设置中配置 AI 接口地址和 API Key');
    }
    final response = await _client
        .post(
          _chatCompletionsUri,
          headers: _headers,
          body: jsonEncode({
            'model': config.model,
            'messages': messages,
            'temperature': 0.2,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = utf8.decode(response.bodyBytes, allowMalformed: true);
      throw AiException(
        'AI 接口错误 ${response.statusCode}: ${detail.length > 300 ? detail.substring(0, 300) : detail}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = (decoded as Map<String, dynamic>)['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw AiException('AI 返回内容为空');
    }
    final message = (choices.first as Map)['message'] as Map?;
    final content = message?['content'];
    if (content is String) {
      return content.trim();
    }
    if (content is List) {
      return content
          .map((part) => part is Map ? (part['text'] ?? '') : '')
          .join()
          .trim();
    }
    return '';
  }
}
