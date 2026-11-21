import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/challenge/achievements.dart';
import 'package:langlearn/core/challenge/challenge_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('extreme scores are compressed only at the top end', () {
    expect(settleScore(ChallengeDifficulty.regular, 9.6), 9.6);
    expect(settleScore(ChallengeDifficulty.extreme, 8.0), 8.0);
    expect(settleScore(ChallengeDifficulty.extreme, 9.0), lessThan(9.0));
    expect(settleScore(ChallengeDifficulty.extreme, 9.5), lessThan(9.5));
    expect(settleScore(ChallengeDifficulty.extreme, 9.5), greaterThan(9.0));
    expect(settleScore(ChallengeDifficulty.extreme, 10.0), 10.0);
  });

  test('challenge runs update achievement progress', () async {
    const store = AchievementStore();
    await store.recordChallenge(
      difficulty: ChallengeDifficulty.extreme,
      score: 9.6,
      ranked: true,
    );
    await store.recordChallenge(
      difficulty: ChallengeDifficulty.regular,
      score: 7.0,
      ranked: false,
    );

    final progress = await store.progress();
    final genius = progress.firstWhere((item) => item.def.id == 'genius');
    final veteran = progress.firstWhere((item) => item.def.id == 'veteran');
    final ranked = progress.firstWhere((item) => item.def.id == 'ranked_star');

    expect(genius.current, 9.6);
    expect(genius.unlocked, isTrue);
    expect(veteran.current, 2);
    expect(veteran.unlocked, isFalse);
    expect(ranked.current, 1);
    expect(ranked.unlocked, isTrue);
  });

  test('pinned achievements are limited to three and drive the widget', () async {
    const store = AchievementStore();
    await store.recordChallenge(
      difficulty: ChallengeDifficulty.extreme,
      score: 9.6,
      ranked: false,
    );
    await store.togglePinned('genius');
    await store.togglePinned('veteran');
    await store.togglePinned('ranked_star');

    final pinned = await store.loadPinned();
    expect(pinned.length, 3);
    final line = await store.widgetLine();
    expect(line.split(' ').first, '🧠');
    expect(line.contains('🔒'), isTrue);
  });
}
