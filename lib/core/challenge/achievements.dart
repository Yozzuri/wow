import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'challenge_store.dart';

class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.emoji,
    required this.name,
    required this.description,
    required this.condition,
    required this.target,
    required this.unit,
  });

  final String id;
  final String emoji;
  final String name;
  final String description;
  final String condition;
  final double target;
  final String unit;
}

const achievementDefs = <AchievementDef>[
  AchievementDef(
    id: 'genius',
    emoji: '🧠',
    name: '天才少年',
    description: '如果这是你真正的实力 那么他人的质疑便是对你最大的认可！',
    condition: '在任意一场极限挑战中达成 9.5 以上的综合评分',
    target: 9.5,
    unit: '分',
  ),
  AchievementDef(
    id: 'veteran',
    emoji: '🔥',
    name: '百炼成钢',
    description: '十场挑战只是开始，手感会一直留在肌肉记忆里。',
    condition: '累计完成 10 场挑战',
    target: 10,
    unit: '场',
  ),
  AchievementDef(
    id: 'ranked_star',
    emoji: '🏅',
    name: '排位初征',
    description: '第一次把成绩交给段位系统，从此每一分都算数。',
    condition: '完成一次排位结算',
    target: 1,
    unit: '次',
  ),
];

AchievementDef achievementById(String id) => achievementDefs.firstWhere(
  (item) => item.id == id,
  orElse: () => achievementDefs.first,
);

class AchievementStats {
  const AchievementStats({
    this.bestExtremeScore = 0,
    this.totalChallenges = 0,
    this.rankedSettlements = 0,
  });

  final double bestExtremeScore;
  final int totalChallenges;
  final int rankedSettlements;

  double valueFor(AchievementDef def) => switch (def.id) {
    'genius' => bestExtremeScore,
    'veteran' => totalChallenges.toDouble(),
    'ranked_star' => rankedSettlements.toDouble(),
    _ => 0,
  };

  Map<String, dynamic> toJson() => {
    'bestExtremeScore': bestExtremeScore,
    'totalChallenges': totalChallenges,
    'rankedSettlements': rankedSettlements,
  };

  factory AchievementStats.fromJson(Map<String, dynamic> json) =>
      AchievementStats(
        bestExtremeScore:
            (json['bestExtremeScore'] as num?)?.toDouble() ?? 0,
        totalChallenges: (json['totalChallenges'] as num?)?.toInt() ?? 0,
        rankedSettlements: (json['rankedSettlements'] as num?)?.toInt() ?? 0,
      );
}

class AchievementProgress {
  const AchievementProgress({required this.def, required this.current});

  final AchievementDef def;
  final double current;

  bool get unlocked => current >= def.target;

  double get ratio => def.target <= 0
      ? 1
      : (current / def.target).clamp(0.0, 1.0);

  String get progressLabel =>
      '${current.toStringAsFixed(def.target % 1 == 0 ? 0 : 1)}'
      ' / ${def.target.toStringAsFixed(def.target % 1 == 0 ? 0 : 1)} ${def.unit}';
}

class AchievementStore {
  const AchievementStore();

  static const _statsKey = 'achievement_stats_v1';
  static const _pinnedKey = 'achievement_pinned_v1';

  Future<AchievementStats> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statsKey);
    if (raw == null || raw.isEmpty) {
      return const AchievementStats();
    }
    try {
      return AchievementStats.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const AchievementStats();
    }
  }

  Future<List<AchievementProgress>> progress() async {
    final stats = await _loadStats();
    return [
      for (final def in achievementDefs)
        AchievementProgress(def: def, current: stats.valueFor(def)),
    ];
  }

  Future<void> recordChallenge({
    required ChallengeDifficulty difficulty,
    required double score,
    required bool ranked,
  }) async {
    final stats = await _loadStats();
    final bestExtreme = difficulty == ChallengeDifficulty.extreme
        ? (score > stats.bestExtremeScore ? score : stats.bestExtremeScore)
        : stats.bestExtremeScore;
    final next = AchievementStats(
      bestExtremeScore: bestExtreme,
      totalChallenges: stats.totalChallenges + 1,
      rankedSettlements:
          stats.rankedSettlements + (ranked ? 1 : 0),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statsKey, jsonEncode(next.toJson()));
  }

  Future<List<String>> loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pinnedKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .where((id) => achievementDefs.any((def) => def.id == id))
            .take(3)
            .toList();
      }
    } catch (_) {
      // Ignore corrupted selection.
    }
    return const [];
  }

  Future<List<String>> togglePinned(String id) async {
    final current = [...await loadPinned()];
    if (current.contains(id)) {
      current.remove(id);
    } else {
      if (current.length >= 3) {
        return current;
      }
      current.add(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinnedKey, jsonEncode(current));
    return current;
  }

  /// Emoji line for the home-screen widgets. Locked ones show a lock.
  Future<String> widgetLine() async {
    final pinned = await loadPinned();
    if (pinned.isEmpty) {
      return '';
    }
    final progress = await this.progress();
    final byId = {for (final item in progress) item.def.id: item};
    return pinned
        .map((id) {
          final item = byId[id];
          if (item == null) {
            return '';
          }
          return item.unlocked ? item.def.emoji : '🔒';
        })
        .where((value) => value.isNotEmpty)
        .join(' ');
  }
}

final achievementProgressProvider =
    FutureProvider<List<AchievementProgress>>(
      (ref) => const AchievementStore().progress(),
    );

final pinnedAchievementsProvider = FutureProvider<List<String>>(
  (ref) => const AchievementStore().loadPinned(),
);
