import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/vocab/checkin_store.dart';
import 'package:langlearn/core/vocab/daily_tasks.dart';
import 'package:langlearn/core/vocab/learning_plan.dart';
import 'package:langlearn/core/vocab/vocab_store.dart';

VocabEntry _entry({
  required String key,
  bool learned = false,
  DateTime? dueAt,
  DateTime? learnedAt,
  DateTime? lastReviewedAt,
  int reps = 0,
}) {
  final now = DateTime(2026, 11, 16, 12);
  return VocabEntry(
    key: key,
    word: key,
    lemma: key,
    meaning: '$key 的释义',
    sentence: 'example $key',
    sourceTitle: 'test',
    createdAt: now,
    dueAt: dueAt ?? now,
    learned: learned,
    learnedAt: learnedAt,
    lastReviewedAt: lastReviewedAt,
    reps: reps,
  );
}

void main() {
  group('Ebbinghaus schedule', () {
    test('good advances along the ladder starting at one day', () {
      expect(ebbinghausSchedule(0, ReviewGrade.good), (
        stage: 1,
        intervalDays: 1,
      ));
      expect(ebbinghausSchedule(1, ReviewGrade.good), (
        stage: 2,
        intervalDays: 2,
      ));
      expect(ebbinghausSchedule(2, ReviewGrade.good), (
        stage: 3,
        intervalDays: 4,
      ));
      expect(ebbinghausSchedule(3, ReviewGrade.good), (
        stage: 4,
        intervalDays: 7,
      ));
    });

    test('forgot resets and hard steps back', () {
      expect(ebbinghausSchedule(4, ReviewGrade.forgot), (
        stage: 0,
        intervalDays: 1,
      ));
      expect(ebbinghausSchedule(3, ReviewGrade.hard), (
        stage: 2,
        intervalDays: 4,
      ));
    });

    test('easy skips ahead without exceeding the ladder', () {
      expect(ebbinghausSchedule(0, ReviewGrade.easy), (
        stage: 2,
        intervalDays: 4,
      ));
      expect(ebbinghausSchedule(9, ReviewGrade.easy), (
        stage: 9,
        intervalDays: 365,
      ));
    });
  });

  group('check-in streak', () {
    final today = DateTime(2026, 11, 16);

    test('counts consecutive days ending today', () {
      expect(
        computeCheckinStreak([
          '2026-11-16',
          '2026-11-15',
          '2026-11-14',
        ], now: today),
        3,
      );
    });

    test('keeps the streak visible before checking in today', () {
      expect(computeCheckinStreak(['2026-11-15', '2026-11-14'], now: today), 2);
    });

    test('breaks on a gap and handles missing data', () {
      expect(computeCheckinStreak(['2026-11-15', '2026-11-13'], now: today), 1);
      expect(computeCheckinStreak(const [], now: today), 0);
    });
  });

  group('daily tasks', () {
    test('caps new and review words by the plan', () {
      final now = DateTime(2026, 11, 16, 12);
      final entries = [
        _entry(key: 'new1'),
        _entry(key: 'new2'),
        _entry(key: 'new3'),
        _entry(
          key: 'due1',
          learned: true,
          dueAt: DateTime(2026, 11, 15),
          reps: 1,
        ),
        _entry(
          key: 'due2',
          learned: true,
          dueAt: DateTime(2026, 11, 15),
          reps: 1,
        ),
        _entry(
          key: 'future',
          learned: true,
          dueAt: DateTime(2026, 11, 20),
          reps: 2,
        ),
      ];
      final tasks = buildDailyTasks(
        entries,
        const LearningPlan(newPerDay: 2, reviewPerDay: 1),
        now: now,
      );
      expect(tasks.newWords.map((e) => e.key), ['new1', 'new2']);
      expect(tasks.reviewWords.map((e) => e.key), ['due1']);
      expect(tasks.extraReviewWords.map((e) => e.key), ['due2']);
      expect(tasks.isDone, isFalse);
    });

    test('counts what is already done today', () {
      final now = DateTime(2026, 11, 16, 12);
      final entries = [
        _entry(key: 'new1'),
        _entry(
          key: 'learnedToday',
          learned: true,
          learnedAt: DateTime(2026, 11, 16, 9),
          dueAt: DateTime(2026, 11, 17),
          lastReviewedAt: DateTime(2026, 11, 16, 10),
        ),
        _entry(
          key: 'reviewedToday',
          learned: true,
          dueAt: DateTime(2026, 11, 30),
          lastReviewedAt: DateTime(2026, 11, 16, 11),
          reps: 2,
        ),
      ];
      final tasks = buildDailyTasks(
        entries,
        const LearningPlan(newPerDay: 5, reviewPerDay: 5),
        now: now,
      );
      expect(tasks.newDoneToday, 1);
      expect(tasks.reviewDoneToday, 2);
      expect(tasks.newWords.map((e) => e.key), ['new1']);
      expect(tasks.reviewWords, isEmpty);
    });
  });
}
