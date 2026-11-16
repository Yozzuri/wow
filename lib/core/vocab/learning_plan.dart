import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LearningPlan {
  const LearningPlan({this.newPerDay = 10, this.reviewPerDay = 50});

  final int newPerDay;
  final int reviewPerDay;

  LearningPlan copyWith({int? newPerDay, int? reviewPerDay}) => LearningPlan(
    newPerDay: newPerDay ?? this.newPerDay,
    reviewPerDay: reviewPerDay ?? this.reviewPerDay,
  );

  Map<String, dynamic> toJson() => {
    'newPerDay': newPerDay,
    'reviewPerDay': reviewPerDay,
  };

  factory LearningPlan.fromJson(Map<String, dynamic> json) => LearningPlan(
    newPerDay: (json['newPerDay'] as num?)?.round().clamp(0, 200) ?? 10,
    reviewPerDay: (json['reviewPerDay'] as num?)?.round().clamp(0, 500) ?? 50,
  );
}

class LearningPlanController extends StateNotifier<LearningPlan> {
  LearningPlanController() : super(const LearningPlan()) {
    _load();
  }

  static const _prefsKey = 'learning_plan_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      state = LearningPlan.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      // Keep defaults when stored preferences are corrupted.
    }
  }

  Future<void> update(LearningPlan next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final learningPlanProvider =
    StateNotifierProvider<LearningPlanController, LearningPlan>(
      (ref) => LearningPlanController(),
    );
