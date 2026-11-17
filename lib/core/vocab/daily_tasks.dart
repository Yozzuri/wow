import 'learning_plan.dart';
import 'vocab_store.dart';

class DailyTasks {
  const DailyTasks({
    required this.newWords,
    required this.reviewWords,
    required this.extraReviewWords,
    required this.newDoneToday,
    required this.reviewDoneToday,
    required this.plan,
  });

  final List<VocabEntry> newWords;
  final List<VocabEntry> reviewWords;

  /// Due words beyond today's review plan. They are never blocked: the
  /// learning screen offers a "continue reviewing" entry for them.
  final List<VocabEntry> extraReviewWords;
  final int newDoneToday;
  final int reviewDoneToday;
  final LearningPlan plan;

  int get total => newWords.length + reviewWords.length;
  bool get isDone => total == 0;
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Builds today's queue: at most [plan.newPerDay] new words and
/// [plan.reviewPerDay] due reviews, minus what has already been done today.
DailyTasks buildDailyTasks(
  List<VocabEntry> entries,
  LearningPlan plan, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final newDone = entries
      .where(
        (entry) =>
            entry.learnedAt != null && isSameDay(entry.learnedAt!, today),
      )
      .length;
  final reviewDone = entries
      .where(
        (entry) =>
            entry.lastReviewedAt != null &&
            isSameDay(entry.lastReviewedAt!, today),
      )
      .length;

  final newBudget = (plan.newPerDay - newDone).clamp(0, plan.newPerDay);
  final reviewBudget = (plan.reviewPerDay - reviewDone).clamp(
    0,
    plan.reviewPerDay,
  );

  final newWords = entries.where((entry) => !entry.learned).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final reviewWords =
      entries
          .where(
            (entry) => entry.learned && !entry.dueAt.isAfter(today),
          )
          .toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  return DailyTasks(
    newWords: newWords.take(newBudget).toList(),
    reviewWords: reviewWords.take(reviewBudget).toList(),
    extraReviewWords: reviewWords.skip(reviewBudget).toList(),
    newDoneToday: newDone,
    reviewDoneToday: reviewDone,
    plan: plan,
  );
}
