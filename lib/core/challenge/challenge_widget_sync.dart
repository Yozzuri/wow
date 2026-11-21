import 'package:flutter/services.dart';

import 'achievements.dart';
import 'challenge_store.dart';
import 'rank_store.dart';

/// Pushes averages and rank to the dedicated challenge widget.
class ChallengeWidgetSync {
  const ChallengeWidgetSync._();

  static const _channel = MethodChannel('com.toastp.langlearn/widget');

  static Future<void> sync() async {
    try {
      final averages = await const ChallengeStore().averages();
      final rank = await const RankStore().load();
      final achievements = await const AchievementStore().widgetLine();
      await _channel.invokeMethod<void>('updateChallenge', {
        'achievements': achievements,
        'averages': formatAverages(averages),
        'rank': rank.displayText,
        'season': '第${rank.season}赛季 · 剩${rank.seasonDaysLeft.clamp(0, rankSeasonDays)}天',
      });
    } on MissingPluginException {
      // Not running on Android.
    } catch (_) {
      // Widget updates are best effort.
    }
  }
}
