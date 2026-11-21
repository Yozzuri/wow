import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChallengeDifficulty { training, regular, extreme }

extension ChallengeDifficultyInfo on ChallengeDifficulty {
  String get label => switch (this) {
    ChallengeDifficulty.training => '训练',
    ChallengeDifficulty.regular => '常规',
    ChallengeDifficulty.extreme => '极限',
  };

  String get description => switch (this) {
    ChallengeDifficulty.training => '每题 20 秒起，节奏宽松',
    ChallengeDifficulty.regular => '每题 12 秒起，逐步收紧',
    ChallengeDifficulty.extreme => '每题 7 秒起，几乎没有余量',
  };

  /// Seconds allowed for the first word.
  double get startSeconds => switch (this) {
    ChallengeDifficulty.training => 20,
    ChallengeDifficulty.regular => 12,
    ChallengeDifficulty.extreme => 7,
  };

  /// Seconds removed from the allowance after each word.
  double get stepSeconds => switch (this) {
    ChallengeDifficulty.training => 0.3,
    ChallengeDifficulty.regular => 0.5,
    ChallengeDifficulty.extreme => 0.4,
  };

  /// Never go below this many seconds per word.
  double get minSeconds => switch (this) {
    ChallengeDifficulty.training => 8,
    ChallengeDifficulty.regular => 5,
    ChallengeDifficulty.extreme => 3,
  };

  /// Training never changes ranked points.
  bool get affectsRank => this != ChallengeDifficulty.training;

  double secondsFor(int index) {
    final value = startSeconds - index * stepSeconds;
    return value < minSeconds ? minSeconds : value;
  }

  String get storageKey => switch (this) {
    ChallengeDifficulty.training => 'training',
    ChallengeDifficulty.regular => 'regular',
    ChallengeDifficulty.extreme => 'extreme',
  };
}

class ChallengeAverages {
  const ChallengeAverages({
    this.training,
    this.regular,
    this.extreme,
    this.trainingCount = 0,
    this.regularCount = 0,
    this.extremeCount = 0,
  });

  final double? training;
  final double? regular;
  final double? extreme;
  final int trainingCount;
  final int regularCount;
  final int extremeCount;

  double? averageFor(ChallengeDifficulty difficulty) => switch (difficulty) {
    ChallengeDifficulty.training => training,
    ChallengeDifficulty.regular => regular,
    ChallengeDifficulty.extreme => extreme,
  };

  int countFor(ChallengeDifficulty difficulty) => switch (difficulty) {
    ChallengeDifficulty.training => trainingCount,
    ChallengeDifficulty.regular => regularCount,
    ChallengeDifficulty.extreme => extremeCount,
  };

  bool get isEmpty =>
      trainingCount == 0 && regularCount == 0 && extremeCount == 0;
}

class ChallengeStore {
  const ChallengeStore();

  static const _prefsKey = 'challenge_scores_v2';

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

    final training = read(ChallengeDifficulty.training.storageKey);
    final regular = read(ChallengeDifficulty.regular.storageKey);
    final extreme = read(ChallengeDifficulty.extreme.storageKey);
    return ChallengeAverages(
      training: training.$1,
      trainingCount: training.$2,
      regular: regular.$1,
      regularCount: regular.$2,
      extreme: extreme.$1,
      extremeCount: extreme.$2,
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

/// Text used by the home-screen widget: e.g. "9.1|7.8|1.3".
String formatAverages(ChallengeAverages averages) {
  return [
    for (final difficulty in ChallengeDifficulty.values)
      averages.averageFor(difficulty)?.toStringAsFixed(1) ?? '--',
  ].join('|');
}

final challengeAveragesProvider = FutureProvider<ChallengeAverages>(
  (ref) => const ChallengeStore().averages(),
);
