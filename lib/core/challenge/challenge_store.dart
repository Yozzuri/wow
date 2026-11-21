import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChallengeDifficulty { regular, confidential, topSecret }

extension ChallengeDifficultyInfo on ChallengeDifficulty {
  String get label => switch (this) {
    ChallengeDifficulty.regular => '常规',
    ChallengeDifficulty.confidential => '机密',
    ChallengeDifficulty.topSecret => '绝密',
  };

  String get description => switch (this) {
    ChallengeDifficulty.regular => '每题 15 秒起，逐题收紧',
    ChallengeDifficulty.confidential => '每题 10 秒起，节奏更快',
    ChallengeDifficulty.topSecret => '每题 7 秒起，几乎没有余量',
  };

  /// Seconds allowed for the first word.
  double get startSeconds => switch (this) {
    ChallengeDifficulty.regular => 15,
    ChallengeDifficulty.confidential => 10,
    ChallengeDifficulty.topSecret => 7,
  };

  /// Seconds removed from the allowance after each word.
  double get stepSeconds => switch (this) {
    ChallengeDifficulty.regular => 0.4,
    ChallengeDifficulty.confidential => 0.5,
    ChallengeDifficulty.topSecret => 0.4,
  };

  /// Never go below this many seconds per word.
  double get minSeconds => switch (this) {
    ChallengeDifficulty.regular => 6,
    ChallengeDifficulty.confidential => 4,
    ChallengeDifficulty.topSecret => 3,
  };

  double secondsFor(int index) {
    final value = startSeconds - index * stepSeconds;
    return value < minSeconds ? minSeconds : value;
  }

  String get storageKey => name;
}

class ChallengeAverages {
  const ChallengeAverages({
    this.regular,
    this.confidential,
    this.topSecret,
    this.regularCount = 0,
    this.confidentialCount = 0,
    this.topSecretCount = 0,
  });

  final double? regular;
  final double? confidential;
  final double? topSecret;
  final int regularCount;
  final int confidentialCount;
  final int topSecretCount;

  double? averageFor(ChallengeDifficulty difficulty) => switch (difficulty) {
    ChallengeDifficulty.regular => regular,
    ChallengeDifficulty.confidential => confidential,
    ChallengeDifficulty.topSecret => topSecret,
  };

  int countFor(ChallengeDifficulty difficulty) => switch (difficulty) {
    ChallengeDifficulty.regular => regularCount,
    ChallengeDifficulty.confidential => confidentialCount,
    ChallengeDifficulty.topSecret => topSecretCount,
  };

  bool get isEmpty =>
      regularCount == 0 && confidentialCount == 0 && topSecretCount == 0;
}

class ChallengeStore {
  const ChallengeStore();

  static const _prefsKey = 'challenge_scores_v1';

  Future<Map<String, dynamic>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {
      // Ignore corrupted score data.
    }
    return <String, dynamic>{};
  }

  Future<ChallengeAverages> averages() async {
    final raw = await _loadRaw();
    (double?, int) read(String key) {
      final entry = raw[key];
      if (entry is! Map) {
        return (null, 0);
      }
      final sum = (entry['sum'] as num?)?.toDouble() ?? 0;
      final count = (entry['count'] as num?)?.toInt() ?? 0;
      if (count <= 0) {
        return (null, 0);
      }
      return (sum / count, count);
    }

    final regular = read(ChallengeDifficulty.regular.storageKey);
    final confidential = read(ChallengeDifficulty.confidential.storageKey);
    final topSecret = read(ChallengeDifficulty.topSecret.storageKey);
    return ChallengeAverages(
      regular: regular.$1,
      regularCount: regular.$2,
      confidential: confidential.$1,
      confidentialCount: confidential.$2,
      topSecret: topSecret.$1,
      topSecretCount: topSecret.$2,
    );
  }

  Future<ChallengeAverages> record(
    ChallengeDifficulty difficulty,
    double score,
  ) async {
    final raw = await _loadRaw();
    final key = difficulty.storageKey;
    final existing = raw[key];
    var sum = 0.0;
    var count = 0;
    if (existing is Map) {
      sum = (existing['sum'] as num?)?.toDouble() ?? 0;
      count = (existing['count'] as num?)?.toInt() ?? 0;
    }
    raw[key] = {'sum': sum + score, 'count': count + 1};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(raw));
    return averages();
  }
}

final challengeAveragesProvider = FutureProvider<ChallengeAverages>(
  (ref) => const ChallengeStore().averages(),
);
