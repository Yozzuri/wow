import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/challenge/challenge_store.dart';
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
    await store.record(ChallengeDifficulty.topSecret, 5.0);

    final averages = await store.averages();
    expect(averages.regular, 7.5);
    expect(averages.regularCount, 2);
    expect(averages.topSecret, 5.0);
    expect(averages.topSecretCount, 1);
    expect(averages.confidential, isNull);
    expect(averages.countFor(ChallengeDifficulty.confidential), 0);
  });

  test('difficulty time shrinks per word and never goes below the floor', () {
    const difficulty = ChallengeDifficulty.topSecret;
    expect(difficulty.secondsFor(0), 7);
    expect(difficulty.secondsFor(1), closeTo(6.6, 0.001));
    expect(difficulty.secondsFor(100), difficulty.minSeconds);
  });
}
