import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/challenge/challenge_store.dart';
import 'package:langlearn/core/challenge/rank_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('averages are empty before any challenge', () async {
    final averages = await const ChallengeStore().averages();
    expect(averages.isEmpty, isTrue);
    expect(averages.averageFor(ChallengeDifficulty.regular), isNull);
  });

  test('records scores per difficulty and averages them', () async {
    const store = ChallengeStore();
    await store.record(ChallengeDifficulty.regular, 8.0);
    await store.record(ChallengeDifficulty.regular, 7.0);
    await store.record(ChallengeDifficulty.extreme, 5.0);

    final averages = await store.averages();
    expect(averages.regular, 7.5);
    expect(averages.regularCount, 2);
    expect(averages.extreme, 5.0);
    expect(averages.extremeCount, 1);
    expect(averages.training, isNull);
    expect(formatAverages(averages), '--|7.5|5.0');
  });

  test('difficulty time shrinks per word and never goes below the floor', () {
    const difficulty = ChallengeDifficulty.extreme;
    expect(difficulty.secondsFor(0), 7);
    expect(difficulty.secondsFor(1), closeTo(6.6, 0.001));
    expect(difficulty.secondsFor(100), difficulty.minSeconds);
  });

  test('thresholds grow linearly from 5.0 to 9.0', () {
    expect(rankPromotionThreshold(0), 5.0);
    expect(rankPromotionThreshold(4), 7.0);
    expect(rankPromotionThreshold(8), 9.0);
  });

  test('word multipliers are non-linear', () {
    expect(rankWordMultiplier(10), 1.0);
    expect(rankWordMultiplier(20), 2.5);
    expect(rankWordMultiplier(30), 4.5);
    expect(rankWordMultiplier(50), 8.5);
  });

  test('rank points compare score with tier threshold', () {
    final training = rankPointsFor(
      difficulty: ChallengeDifficulty.training,
      score: 10,
      wordCount: 10,
      specificLanguage: false,
      tier: 0,
    );
    expect(training.finalPoints, 0);

    final bronze = rankPointsFor(
      difficulty: ChallengeDifficulty.regular,
      score: 10,
      wordCount: 10,
      specificLanguage: false,
      tier: 0,
    );
    expect(bronze.base, 100);
    expect(bronze.finalPoints, 100);

    final peak = rankPointsFor(
      difficulty: ChallengeDifficulty.regular,
      score: 10,
      wordCount: 10,
      specificLanguage: false,
      tier: 8,
    );
    expect(peak.base, 20);
    expect(peak.finalPoints, 20);

    final longRun = rankPointsFor(
      difficulty: ChallengeDifficulty.extreme,
      score: 10,
      wordCount: 20,
      specificLanguage: true,
      tier: 0,
    );
    expect(longRun.afterWords, 250);
    expect(longRun.afterLanguage, 225);
    expect(longRun.finalPoints, 300);
  });

  test('small losses are protected, larger losses are not', () {
    final protected = rankPointsFor(
      difficulty: ChallengeDifficulty.regular,
      score: 8.9,
      wordCount: 10,
      specificLanguage: false,
      tier: 8,
    );
    expect(protected.base, -2);
    expect(protected.protectedLoss, isTrue);
    expect(protected.finalPoints, 0);

    final loss = rankPointsFor(
      difficulty: ChallengeDifficulty.regular,
      score: 6.0,
      wordCount: 10,
      specificLanguage: false,
      tier: 5,
    );
    expect(loss.base, -30);
    expect(loss.protectedLoss, isFalse);
    expect(loss.finalPoints, -30);
  });

  test('advanceRank promotes through divisions and tiers', () {
    final start = RankState(
      tier: 0,
      division: 0,
      stars: 0,
      points: 0,
      season: 1,
      seasonStart: DateTime(2026, 1, 1),
    );
    final oneStar = advanceRank(start, 100);
    expect(oneStar.stars, 1);
    expect(oneStar.points, 0);

    final promoted = advanceRank(oneStar, 300);
    expect(promoted.stars, 0);
    expect(promoted.division, 1);

    final tierUp = advanceRank(
      start.copyWith(division: 2, stars: 3, points: 0),
      100,
    );
    expect(tierUp.tier, 1);
    expect(tierUp.division, 0);
    expect(tierUp.stars, 0);
  });

  test('losing points demotes stars', () {
    final start = RankState(
      tier: 2,
      division: 1,
      stars: 0,
      points: 0,
      season: 1,
      seasonStart: DateTime(2026, 1, 1),
    );
    final demoted = advanceRank(start, -100);
    expect(demoted.division, 0);
    expect(demoted.stars, 3);
  });

  test('season inheritance is non-linear', () {
    RankState at(int tier) => RankState(
      tier: tier,
      division: 2,
      stars: 3,
      points: 50,
      season: 1,
      seasonStart: DateTime(2026, 1, 1),
    );
    expect(inheritRank(at(8)).tier, 6);
    expect(inheritRank(at(6)).tier, 4);
    expect(inheritRank(at(5)).tier, 3);
    expect(inheritRank(at(0)).tier, 0);
    final next = inheritRank(at(8));
    expect(next.division, 0);
    expect(next.stars, 0);
    expect(next.season, 2);
  });

  test('elapsed seasons roll over multiple times', () {
    final state = RankState(
      tier: 8,
      division: 0,
      stars: 1,
      points: 20,
      season: 1,
      seasonStart: DateTime(2026, 1, 1),
    );
    final now = DateTime(2026, 5, 10);
    final rolled = applySeasonRollover(state, now);
    // 129 days covers two 60-day seasons.
    expect(rolled.season, 3);
    expect(rolled.tier, 4);
  });
}
