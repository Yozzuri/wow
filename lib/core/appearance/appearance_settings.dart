import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppearanceSettings {
  const AppearanceSettings({
    this.seedColorValue = 0xFF3F7CAC,
    this.themeMode = ThemeMode.system,
    this.backgroundPath,
    this.scrimEnabled = true,
    this.scrimOpacity = 0.5,
  });

  final int seedColorValue;
  final ThemeMode themeMode;
  final String? backgroundPath;
  final bool scrimEnabled;
  final double scrimOpacity;

  Color get seedColor => Color(seedColorValue);
  bool get hasBackground => (backgroundPath ?? '').isNotEmpty;

  AppearanceSettings copyWith({
    int? seedColorValue,
    ThemeMode? themeMode,
    String? backgroundPath,
    bool clearBackground = false,
    bool? scrimEnabled,
    double? scrimOpacity,
  }) => AppearanceSettings(
    seedColorValue: seedColorValue ?? this.seedColorValue,
    themeMode: themeMode ?? this.themeMode,
    backgroundPath: clearBackground
        ? null
        : (backgroundPath ?? this.backgroundPath),
    scrimEnabled: scrimEnabled ?? this.scrimEnabled,
    scrimOpacity: scrimOpacity ?? this.scrimOpacity,
  );

  Map<String, dynamic> toJson() => {
    'seedColorValue': seedColorValue,
    'themeMode': themeMode.name,
    'backgroundPath': backgroundPath,
    'scrimEnabled': scrimEnabled,
    'scrimOpacity': scrimOpacity,
  };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    final modeName = json['themeMode'] as String? ?? 'system';
    return AppearanceSettings(
      seedColorValue: json['seedColorValue'] as int? ?? 0xFF3F7CAC,
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => ThemeMode.system,
      ),
      backgroundPath: json['backgroundPath'] as String?,
      scrimEnabled: json['scrimEnabled'] as bool? ?? true,
      scrimOpacity: (json['scrimOpacity'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class AppearanceController extends StateNotifier<AppearanceSettings> {
  AppearanceController() : super(const AppearanceSettings()) {
    _load();
  }

  static const _prefsKey = 'appearance_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      state = AppearanceSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
      if (state.hasBackground &&
          !await File(state.backgroundPath!).exists()) {
        state = state.copyWith(clearBackground: true);
      }
    } catch (_) {
      // Keep defaults when stored preferences are corrupted.
    }
  }

  Future<void> update(AppearanceSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
  }

  Future<void> importBackgroundFromBytes(
    List<int> bytes,
    String extension,
  ) async {
    final base = await getApplicationDocumentsDirectory();
    final previous = state.backgroundPath;
    final safeExtension = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final target = File(
      '${base.path}/background_${DateTime.now().millisecondsSinceEpoch}.${safeExtension.isEmpty ? 'jpg' : safeExtension}',
    );
    await target.writeAsBytes(bytes, flush: true);
    await update(state.copyWith(backgroundPath: target.path));
    if (previous != null && previous != target.path) {
      final oldFile = File(previous);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    }
  }

  Future<void> clearBackground() async {
    final previous = state.backgroundPath;
    await update(state.copyWith(clearBackground: true));
    if (previous != null) {
      final file = File(previous);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, AppearanceSettings>(
      (ref) => AppearanceController(),
    );

const appearanceSeedColors = <int>[
  0xFF3F7CAC,
  0xFF00897B,
  0xFF2E7D32,
  0xFF6A4C93,
  0xFFE67E22,
  0xFFC62828,
  0xFFAD1457,
  0xFF455A64,
];
