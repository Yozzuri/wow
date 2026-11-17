import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TokenizerMode { local, ai }

class TokenizerSettings {
  const TokenizerSettings({this.mode = TokenizerMode.local});

  final TokenizerMode mode;

  TokenizerSettings copyWith({TokenizerMode? mode}) =>
      TokenizerSettings(mode: mode ?? this.mode);

  Map<String, dynamic> toJson() => {'mode': mode.name};

  factory TokenizerSettings.fromJson(Map<String, dynamic> json) {
    final name = json['mode'] as String? ?? 'local';
    return TokenizerSettings(
      mode: TokenizerMode.values.firstWhere(
        (value) => value.name == name,
        orElse: () => TokenizerMode.local,
      ),
    );
  }
}

class TokenizerSettingsController extends StateNotifier<TokenizerSettings> {
  TokenizerSettingsController() : super(const TokenizerSettings()) {
    _load();
  }

  static const _prefsKey = 'tokenizer_mode_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      state = TokenizerSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      // Keep the local default.
    }
  }

  Future<void> update(TokenizerSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final tokenizerModeProvider =
    StateNotifierProvider<TokenizerSettingsController, TokenizerSettings>(
      (ref) => TokenizerSettingsController(),
    );
