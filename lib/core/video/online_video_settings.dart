import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnlineCdnLine {
  const OnlineCdnLine({required this.id, required this.label, this.host});

  final String id;
  final String label;
  final String? host;
}

const onlineCdnLines = <OnlineCdnLine>[
  OnlineCdnLine(id: 'auto', label: '自动（B 站分配）'),
  OnlineCdnLine(
    id: 'aliyun',
    label: '阿里云',
    host: 'upos-sz-mirrorali.bilivideo.com',
  ),
  OnlineCdnLine(
    id: 'tencent',
    label: '腾讯云',
    host: 'upos-sz-mirrorcos.bilivideo.com',
  ),
  OnlineCdnLine(
    id: 'huawei',
    label: '华为云',
    host: 'upos-sz-mirrorhw.bilivideo.com',
  ),
  OnlineCdnLine(
    id: 'telecom',
    label: '电信',
    host: 'upos-sz-mirror08c.bilivideo.com',
  ),
  OnlineCdnLine(
    id: 'overseas_aliyun',
    label: '海外阿里云',
    host: 'upos-sz-mirroraliov.bilivideo.com',
  ),
  OnlineCdnLine(
    id: 'overseas_tencent',
    label: '海外腾讯云',
    host: 'upos-sz-mirrorcosov.bilivideo.com',
  ),
];

OnlineCdnLine onlineCdnLineFor(String id) => onlineCdnLines.firstWhere(
  (line) => line.id == id,
  orElse: () => onlineCdnLines.first,
);

class OnlineVideoSettings {
  const OnlineVideoSettings({
    this.cdnLineId = 'auto',
    this.cacheBeforePlay = false,
    this.transcriptionModel = 'whisper-1',
  });

  final String cdnLineId;
  final bool cacheBeforePlay;
  final String transcriptionModel;

  OnlineCdnLine get cdnLine => onlineCdnLineFor(cdnLineId);
  String? get cdnHost => cdnLine.host;

  OnlineVideoSettings copyWith({
    String? cdnLineId,
    bool? cacheBeforePlay,
    String? transcriptionModel,
  }) => OnlineVideoSettings(
    cdnLineId: cdnLineId ?? this.cdnLineId,
    cacheBeforePlay: cacheBeforePlay ?? this.cacheBeforePlay,
    transcriptionModel: transcriptionModel ?? this.transcriptionModel,
  );

  Map<String, dynamic> toJson() => {
    'cdnLineId': cdnLineId,
    'cacheBeforePlay': cacheBeforePlay,
    'transcriptionModel': transcriptionModel,
  };

  factory OnlineVideoSettings.fromJson(Map<String, dynamic> json) =>
      OnlineVideoSettings(
        cdnLineId: json['cdnLineId'] as String? ?? 'auto',
        cacheBeforePlay: json['cacheBeforePlay'] as bool? ?? false,
        transcriptionModel:
            json['transcriptionModel'] as String? ?? 'whisper-1',
      );
}

class OnlineVideoSettingsController extends StateNotifier<OnlineVideoSettings> {
  OnlineVideoSettingsController() : super(const OnlineVideoSettings()) {
    _load();
  }

  static const _prefsKey = 'online_video_settings_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      state = OnlineVideoSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      // Keep defaults when stored preferences are corrupted.
    }
  }

  Future<void> update(OnlineVideoSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final onlineVideoSettingsProvider =
    StateNotifierProvider<OnlineVideoSettingsController, OnlineVideoSettings>(
      (ref) => OnlineVideoSettingsController(),
    );
