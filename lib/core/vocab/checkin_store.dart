import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../challenge/achievements.dart';

class CheckinStatus {
  const CheckinStatus({this.streak = 0, this.checkedInToday = false});

  final int streak;
  final bool checkedInToday;

  CheckinStatus copyWith({int? streak, bool? checkedInToday}) => CheckinStatus(
    streak: streak ?? this.streak,
    checkedInToday: checkedInToday ?? this.checkedInToday,
  );
}

String checkinDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _shiftDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

int computeCheckinStreak(Iterable<String> dates, {DateTime? now}) {
  final set = dates.toSet();
  final today = now ?? DateTime.now();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!set.contains(checkinDayKey(cursor))) {
    cursor = _shiftDays(cursor, -1);
  }
  var streak = 0;
  while (set.contains(checkinDayKey(cursor))) {
    streak++;
    cursor = _shiftDays(cursor, -1);
  }
  return streak;
}

class CheckinStore {
  const CheckinStore();

  static const _prefsKey = 'vocab_checkin_v1';
  static const _channel = MethodChannel('com.toastp.langlearn/widget');

  Future<Set<String>> _loadDates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // Ignore corrupted check-in data.
    }
    return <String>{};
  }

  Future<CheckinStatus> loadStatus() async {
    final dates = await _loadDates();
    final status = CheckinStatus(
      streak: computeCheckinStreak(dates),
      checkedInToday: dates.contains(checkinDayKey(DateTime.now())),
    );
    await _syncWidget(dates, status.streak);
    return status;
  }

  Future<CheckinStatus> checkInToday() async {
    final dates = await _loadDates();
    dates.add(checkinDayKey(DateTime.now()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(dates.toList()..sort()));
    final status = CheckinStatus(
      streak: computeCheckinStreak(dates),
      checkedInToday: true,
    );
    await _syncWidget(dates, status.streak);
    return status;
  }

  Future<void> syncWidget() async {
    final dates = await _loadDates();
    await _syncWidget(dates, computeCheckinStreak(dates));
  }

  Future<void> _syncWidget(Set<String> dates, int streak) async {
    try {
      final achievements = await const AchievementStore().widgetLine();
      await _channel.invokeMethod<void>('updateCheckin', {
        'dates': dates.toList()..sort(),
        'streak': streak,
        'achievements': achievements,
      });
    } on MissingPluginException {
      // Not running on Android or the widget bridge is unavailable.
    } catch (_) {
      // Widget updates are best effort and must never break check-in.
    }
  }
}

class CheckinController extends StateNotifier<CheckinStatus> {
  CheckinController() : super(const CheckinStatus()) {
    _load();
  }

  static const _store = CheckinStore();

  Future<void> _load() async {
    final status = await _store.loadStatus();
    if (mounted) {
      state = status;
    }
  }

  Future<CheckinStatus> checkIn() async {
    final status = await _store.checkInToday();
    if (mounted) {
      state = status;
    }
    return status;
  }

  Future<void> refresh() async {
    final status = await _store.loadStatus();
    if (mounted) {
      state = status;
    }
  }
}

final checkinProvider = StateNotifierProvider<CheckinController, CheckinStatus>(
  (ref) => CheckinController(),
);
