import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'challenge_store.dart';

const List<String> rankTierNames = [
  '青铜',
  '白银',
  '黄金',
  '铂金',
  '钻石',
  '大师',
  '宗师',
  '王者',
  '巅峰',
];

const List<String> rankDivisionLabels = ['III', 'II', 'I'];

/// Points needed to gain one star.
const int rankPointsPerStar = 100;

/// A season lasts two months.
const int rankSeasonDays = 60;

/// Tier inheritance at season end, as 0-based tier indexes.
/// 巅峰(9) -> 宗师(7), 宗师(7) -> 钻石(5), 王者(8) -> 大师(6), ...
const List<int> rankTierInheritance = [0, 0, 0, 1, 2, 3, 4, 5, 6];

class RankState {
  const RankState({
    required this.tier,
    required this.division,
    required this.stars,
    required this.points,
    required this.season,
    required this.seasonStart,
  });

  final int tier;
  final int division;
  final int stars;
  final int points;
  final int season;
  final DateTime seasonStart;

  factory RankState.initial(DateTime now) => RankState(
    tier: 0,
    division: 0,
    stars: 0,
    points: 0,
    season: 1,
    seasonStart: DateTime(now.year, now.month, now.day),
  );

  bool get isTopTier => tier >= rankTierNames.length - 1;

  String get tierName => rankTierNames[tier.clamp(0, rankTierNames.length - 1)];

  String get divisionLabel => rankDivisionLabels[division.clamp(0, 2)];

  String get label => '$tierName $divisionLabel';

  /// Filled/empty stars for the widget, e.g. "★★☆☆".
  String get starBar {
    if (isTopTier) {
      return '★×$stars';
    }
    final filled = stars.clamp(0, 4);
    return List.filled(filled, '★').join() +
        List.filled(4 - filled, '☆').join();
  }

  String get displayText => '$label $starBar';

  int get pointsToNextStar => rankPointsPerStar - points;

  int get seasonDaysLeft =>
      rankSeasonDays - DateTime.now().difference(seasonStart).inDays;

  RankState copyWith({
    int? tier,
    int? division,
    int? stars,
    int? points,
    int? season,
    DateTime? seasonStart,
  }) => RankState(
    tier: tier ?? this.tier,
    division: division ?? this.division,
    stars: stars ?? this.stars,
    points: points ?? this.points,
    season: season ?? this.season,
    seasonStart: seasonStart ?? this.seasonStart,
  );

  Map<String, dynamic> toJson() => {
    'tier': tier,
    'division': division,
    'stars': stars,
    'points': points,
    'season': season,
    'seasonStart': seasonStart.toIso8601String(),
  };

  factory RankState.fromJson(Map<String, dynamic> json, DateTime fallback) =>
      RankState(
        tier: ((json['tier'] as num?)?.toInt() ?? 0).clamp(
          0,
          rankTierNames.length - 1,
        ),
        division: ((json['division'] as num?)?.toInt() ?? 0).clamp(0, 2),
        stars: ((json['stars'] as num?)?.toInt() ?? 0).clamp(0, 999),
        points: ((json['points'] as num?)?.toInt() ?? 0).clamp(
          0,
          rankPointsPerStar - 1,
        ),
        season: (json['season'] as num?)?.toInt() ?? 1,
        seasonStart:
            DateTime.tryParse(json['seasonStart'] as String? ?? '') ?? fallback,
      );
}

class RankPointsBreakdown {
  const RankPointsBreakdown({
    required this.threshold,
    required this.base,
    required this.wordMultiplier,
    required this.afterWords,
    required this.languageMultiplier,
    required this.afterLanguage,
    required this.difficultyMultiplier,
    required this.finalPoints,
    this.protectedLoss = false,
  });

  static const zero = RankPointsBreakdown(
    threshold: 5,
    base: 0,
    wordMultiplier: 1,
    afterWords: 0,
    languageMultiplier: 1,
    afterLanguage: 0,
    difficultyMultiplier: 1,
    finalPoints: 0,
  );

  /// Composite score required to gain points at this tier.
  final double threshold;
  final int base;
  final double wordMultiplier;
  final int afterWords;
  final double languageMultiplier;
  final int afterLanguage;
  final double difficultyMultiplier;
  final int finalPoints;

  /// Set when a small loss was cancelled by the rank protection.
  final bool protectedLoss;
}

/// Required composite score grows linearly from 5.0 (青铜) to 9.0 (巅峰).
double rankPromotionThreshold(int tier) {
  final index = tier.clamp(0, rankTierNames.length - 1);
  return 5.0 + 0.5 * index;
}

/// Word count multiplier. 10 words = 1.0x, 20 = 2.5x, then steeper.
double rankWordMultiplier(int wordCount) {
  if (wordCount >= 50) {
    return 8.5;
  }
  if (wordCount >= 30) {
    return 4.5;
  }
  if (wordCount >= 20) {
    return 2.5;
  }
  return 1.0;
}

/// Base points compare the composite score with the tier threshold, then get
/// scaled by word count, selected language and difficulty. A loss smaller than
/// 20 points is cancelled by the rank protection.
RankPointsBreakdown rankPointsFor({
  required ChallengeDifficulty difficulty,
  required double score,
  required int wordCount,
  required bool specificLanguage,
  required int tier,
}) {
  if (!difficulty.affectsRank) {
    return RankPointsBreakdown.zero;
  }
  final threshold = rankPromotionThreshold(tier);
  final base = ((score - threshold) * 20).round().clamp(-150, 150);
  final wordMultiplier = rankWordMultiplier(wordCount);
  final afterWords = (base * wordMultiplier).round();
  final languageMultiplier = specificLanguage ? 0.9 : 1.0;
  final afterLanguage = (afterWords * languageMultiplier).round();
  final difficultyMultiplier = difficulty == ChallengeDifficulty.extreme
      ? 1.5
      : 1.0;
  var finalPoints = (afterLanguage * difficultyMultiplier)
      .round()
      .clamp(-300, 300);
  var protectedLoss = false;
  if (finalPoints < 0 && finalPoints > -20) {
    finalPoints = 0;
    protectedLoss = true;
  }
  return RankPointsBreakdown(
    threshold: threshold,
    base: base,
    wordMultiplier: wordMultiplier,
    afterWords: afterWords,
    languageMultiplier: languageMultiplier,
    afterLanguage: afterLanguage,
    difficultyMultiplier: difficultyMultiplier,
    finalPoints: finalPoints,
    protectedLoss: protectedLoss,
  );
}

RankState advanceRank(RankState state, int delta) {
  if (delta == 0) {
    return state;
  }
  var tier = state.tier;
  var division = state.division;
  var stars = state.stars;
  var points = state.points + delta;
  if (delta > 0) {
    while (points >= rankPointsPerStar) {
      points -= rankPointsPerStar;
      stars += 1;
      if (!_isTop(tier) && stars >= 4) {
        stars -= 4;
        division += 1;
        if (division > 2) {
          division = 0;
          tier += 1;
        }
      }
    }
  } else {
    while (points < 0) {
      if (stars > 0) {
        stars -= 1;
        points += rankPointsPerStar;
      } else if (division > 0) {
        division -= 1;
        stars = 3;
        points += rankPointsPerStar;
      } else if (tier > 0) {
        tier -= 1;
        division = 2;
        stars = 3;
        points += rankPointsPerStar;
      } else {
        points = 0;
        break;
      }
    }
  }
  return state.copyWith(
    tier: tier,
    division: division,
    stars: stars,
    points: points,
  );
}

RankState inheritRank(RankState state) {
  final nextTier = rankTierInheritance[state.tier.clamp(
    0,
    rankTierInheritance.length - 1,
  )];
  return RankState(
    tier: nextTier,
    division: 0,
    stars: 0,
    points: 0,
    season: state.season + 1,
    seasonStart: state.seasonStart.add(const Duration(days: rankSeasonDays)),
  );
}

bool _isTop(int tier) => tier >= rankTierNames.length - 1;

class RankStore {
  const RankStore();

  static const _prefsKey = 'rank_state_v1';

  Future<RankState> load({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    RankState state;
    if (raw == null || raw.isEmpty) {
      state = RankState.initial(current);
    } else {
      try {
        state = RankState.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
          current,
        );
      } catch (_) {
        state = RankState.initial(current);
      }
    }
    final rolled = applySeasonRollover(state, current);
    if (rolled != state || raw == null || raw.isEmpty) {
      await _save(rolled);
    }
    return rolled;
  }

  Future<RankState> applyPoints(int points) async {
    final state = await load();
    if (points == 0) {
      return state;
    }
    final next = advanceRank(state, points);
    await _save(next);
    return next;
  }

  Future<void> _save(RankState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }
}

/// Handles any number of elapsed two-month seasons at once.
RankState applySeasonRollover(RankState state, DateTime now) {
  var current = state;
  while (!now.isBefore(
    current.seasonStart.add(const Duration(days: rankSeasonDays)),
  )) {
    current = inheritRank(current);
  }
  return current;
}

final rankProvider = FutureProvider<RankState>((ref) => const RankStore().load());
