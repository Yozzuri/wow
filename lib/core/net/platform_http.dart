import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class PlatformHttpException implements Exception {
  PlatformHttpException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PlatformHttpResponse {
  const PlatformHttpResponse({
    required this.status,
    required this.body,
    required this.finalUrl,
    required this.contentType,
  });

  final int status;
  final Uint8List body;
  final Uri finalUrl;
  final String contentType;
}

/// On Android requests are executed with the system network stack, which
/// honors the device proxy and CA store. This avoids Dart TLS handshake
/// failures on some mobile networks. Other platforms fall back to package:http.
class PlatformHttp {
  const PlatformHttp._();

  static const _channel = MethodChannel('com.toastp.langlearn/http');

  static Future<PlatformHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('get', {
        'url': uri.toString(),
        'headers': headers,
      });
      if (result != null) {
        final rawBody = result['body'];
        final body = rawBody is Uint8List
            ? rawBody
            : Uint8List.fromList(
                (rawBody as List?)?.whereType<int>().toList() ?? const [],
              );
        return PlatformHttpResponse(
          status: (result['status'] as num?)?.toInt() ?? 0,
          body: body,
          finalUrl:
              Uri.tryParse(result['url'] as String? ?? '') ?? uri,
          contentType: result['contentType'] as String? ?? '',
        );
      }
    } on MissingPluginException {
      // Fall back to the Dart client on non-Android platforms.
    } on PlatformException catch (error) {
      throw PlatformHttpException(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : '系统网络请求失败',
      );
    }
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
    return PlatformHttpResponse(
      status: response.statusCode,
      body: response.bodyBytes,
      finalUrl: response.request?.url ?? uri,
      contentType: response.headers['content-type'] ?? '',
    );
  }

  static Future<void> download(
    Uri uri,
    String filePath, {
    Map<String, String> headers = const {},
  }) async {
    try {
      await _channel.invokeMethod<void>('download', {
        'url': uri.toString(),
        'filePath': filePath,
        'headers': headers,
      });
      return;
    } on MissingPluginException {
      // Fall back to the Dart client on non-Android platforms.
    } on PlatformException catch (error) {
      throw PlatformHttpException(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : '系统下载失败',
      );
    }
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(minutes: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlatformHttpException('下载失败：HTTP \${response.statusCode}');
    }
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes, flush: true);
  }
}
