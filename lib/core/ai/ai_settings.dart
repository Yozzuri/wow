import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiConfig {
  const AiConfig({
    this.baseUrl = 'https://api.openai.com/v1',
    this.model = 'gpt-4o-mini',
    this.apiKey = '',
  });

  final String baseUrl;
  final String model;
  final String apiKey;

  bool get isConfigured => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  String get normalizedBaseUrl => baseUrl.trim().replaceFirst(
    RegExp(r'/+$'),
    '',
  );

  AiConfig copyWith({String? baseUrl, String? model, String? apiKey}) =>
      AiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
      );

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
    baseUrl: json['baseUrl'] as String? ?? '',
    model: json['model'] as String? ?? '',
    apiKey: json['apiKey'] as String? ?? '',
  );
}

class AiSettingsStore {
  const AiSettingsStore();

  static const _storageKey = 'ai_config_v1';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<AiConfig> load() async {
    final raw = await _secureStorage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      return const AiConfig();
    }
    try {
      return AiConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const AiConfig();
    }
  }

  Future<void> save(AiConfig config) => _secureStorage.write(
    key: _storageKey,
    value: jsonEncode(config.toJson()),
  );
}

final aiSettingsStoreProvider = Provider<AiSettingsStore>(
  (ref) => const AiSettingsStore(),
);

final aiConfigProvider = FutureProvider<AiConfig>(
  (ref) => ref.watch(aiSettingsStoreProvider).load(),
);
