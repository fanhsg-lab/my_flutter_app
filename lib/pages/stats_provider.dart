import 'dart:math'; // Import for 'max'
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../local_db.dart';

// 1. DATA MODEL
class UserStats {
  final int totalWords;
  final int learning;
  final int mastered;
  final int newWords;
  final int fresh;
  final int fading;
  final int dormant;
  final List<int> forecast;
  final List<FlSpot> learnedSpots;
  final List<FlSpot> learningSpots;
  final List<String> dateLabels;
  final double historyMaxY;
  final Map<DateTime, int> heatmapData;

  UserStats({
    required this.totalWords,
    required this.learning,
    required this.mastered,
    required this.newWords,
    required this.fresh,
    required this.fading,
    required this.dormant,
    required this.forecast,
    required this.learnedSpots,
    required this.learningSpots,
    required this.dateLabels,
    required this.historyMaxY,
    required this.heatmapData,
  });
}

// 2. THE TRIGGER
final dbUpdateTrigger = StreamProvider<bool>((ref) async* {
  yield LocalDB.instance.onDatabaseChanged.value;
  await for (final _ in _notifierToStream(LocalDB.instance.onDatabaseChanged)) {
    yield LocalDB.instance.onDatabaseChanged.value;
  }
});

Stream<void> _notifierToStream(ValueNotifier notifier) async* {
  var previousValue = notifier.value;
  while (true) {
    await Future.delayed(const Duration(milliseconds: 300));
    if (notifier.value != previousValue) {
      previousValue = notifier.value;
      yield null;
    }
  }
}

// 3. FILTER STATE (book, teacher, or all)
enum StatsFilter { book, teacher, all }
final statsFilterProvider = StateProvider<StatsFilter>((ref) => StatsFilter.book);

// 4. THE MAIN PROVIDER (with filtering support)
final statsProvider = FutureProvider<UserStats>((ref) async {
  ref.watch(dbUpdateTrigger);
  final filter = ref.watch(statsFilterProvider);

  final db = await LocalDB.instance.database;
  final now = DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final userId = Supabase.instance.client.auth.currentUser?.id;

  // Get current book and teacher IDs
  final currentBookId = await LocalDB.instance.getCurrentBookId();
  final currentTeacherId = await LocalDB.instance.getCurrentTeacherId();

  // Build word filter based on selected filter mode
  String wordFilter = '';
  List<dynamic> wordFilterArgs = [];

  if (filter == StatsFilter.book && currentBookId != null) {
    // Filter by current book only
    wordFilter = '''
      AND word_id IN (
        SELECT w.id FROM words w
        JOIN lesson_words lw ON lw.word_id = w.id
        JOIN lessons l ON lw.lesson_id = l.id
        WHERE l.book_id = ?
      )
    ''';
    wordFilterArgs.add(currentBookId);
  } else if (filter == StatsFilter.teacher && currentTeacherId != null) {
    // Filter by all books from current teacher
    wordFilter = '''
      AND word_id IN (
        SELECT w.id FROM words w
        JOIN lesson_words lw ON lw.word_id = w.id
        JOIN lessons l ON lw.lesson_id = l.id
        JOIN books b ON l.book_id = b.id
        WHERE b.teacher_id = ?
      )
    ''';
    wordFilterArgs.add(currentTeacherId);
  }
  // If filter == all, no word filter (show everything)

  // --- A. COUNTS & FORECAST ---
  final allWords = await db.rawQuery('''
    SELECT * FROM user_progress
    WHERE user_id = ? $wordFilter
  ''', [userId, ...wordFilterArgs]);

  // Count total words in scope
  int totalWords;
  if (filter == StatsFilter.book && currentBookId != null) {
    final res = await db.rawQuery('''
      SELECT COUNT(DISTINCT w.id) as count FROM words w
      JOIN lesson_words lw ON lw.word_id = w.id
      JOIN lessons l ON lw.lesson_id = l.id
      WHERE l.book_id = ?
    ''', [currentBookId]);
    totalWords = Sqflite.firstIntValue(res) ?? 0;
  } else if (filter == StatsFilter.teacher && currentTeacherId != null) {
    final res = await db.rawQuery('''
      SELECT COUNT(DISTINCT w.id) as count FROM words w
      JOIN lesson_words lw ON lw.word_id = w.id
      JOIN lessons l ON lw.lesson_id = l.id
      JOIN books b ON l.book_id = b.id
      WHERE b.teacher_id = ?
    ''', [currentTeacherId]);
    totalWords = Sqflite.firstIntValue(res) ?? 0;
  } else {
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM words');
    totalWords = Sqflite.firstIntValue(res) ?? 0;
  }

  int lrn = 0, lrd = 0;
  int fresh = 0, fading = 0, dormant = 0;
  List<int> forecast = List.filled(7, 0);

  for (var row in allWords) {
    String status = row['status'] as String;

    if (status == 'learning') lrn++;
    else if (status == 'consolidating' || status == 'learned') {
      lrd++;
      if (row['last_reviewed'] != null) {
        final lastReview = DateTime.parse(row['last_reviewed'] as String).toLocal();
        final diff = now.difference(lastReview).inDays;
        if (diff <= 7) fresh++;
        else if (diff <= 30) fading++;
        else dormant++;
      }
    }

    if (row['next_due_at'] != null) {
      DateTime due = DateTime.parse(row['next_due_at'] as String).toLocal();
      DateTime dueMidnight = DateTime(due.year, due.month, due.day);
      int diffDays = dueMidnight.difference(todayMidnight).inDays;

      if (diffDays < 0) forecast[0]++;
      else if (diffDays < 7) forecast[diffDays]++;
    }
  }

  int n = totalWords - (lrn + lrd);
  if (n < 0) n = 0;

  // 🔥 NEW: Use aggregated daily_stats for heatmap (much faster!)
  final heatmapData = await LocalDB.instance.getDailyActivityHeatmap(days: 365);

  // Convert String dates to DateTime keys for the heatmap widget
  Map<DateTime, int> heat = {};
  for (var entry in heatmapData.entries) {
    try {
      final date = DateTime.parse(entry.key);
      final cleanDate = DateTime(date.year, date.month, date.day);
      heat[cleanDate] = entry.value;
    } catch (e) {
      debugPrint("⚠️ Invalid date in heatmap: ${entry.key}");
    }
  }

  // --- C. HISTORICAL STATS (Using new helper function) ---
  List<FlSpot> tempLearned = [];
  List<FlSpot> tempLearning = [];
  List<String> tempDates = [];
  double calcMax = 10;

  if (userId != null) {
    try {
      // 🔥 NEW: Use optimized helper function
      final historicalStats = await LocalDB.instance.getHistoricalStats(days: 90);

      int index = 0;
      for (var stat in historicalStats) {
        double valLearned = (stat['learned'] as num?)?.toDouble() ?? 0;
        double valLearning = (stat['reviewing'] as num?)?.toDouble() ?? 0;

        tempLearned.add(FlSpot(index.toDouble(), valLearned));
        tempLearning.add(FlSpot(index.toDouble(), valLearning));

        DateTime dateObj = DateTime.parse(stat['date'] as String).toLocal();
        tempDates.add(DateFormat('MMM d').format(dateObj));

        if (valLearned > calcMax) calcMax = valLearned;
        if (valLearning > calcMax) calcMax = valLearning;

        // Fill gaps in heatmap from daily_stats
        DateTime cleanDate = DateTime(dateObj.year, dateObj.month, dateObj.day);
        if (!heat.containsKey(cleanDate) && (stat['total'] as num) > 0) {
          // If not already in heatmap but we have activity, add it
          heat[cleanDate] = (stat['total'] as num).toInt();
        }

        index++;
      }
    } catch (e) {
      debugPrint("⚠️ Could not load history: $e");
    }
  }

  if (tempLearned.isEmpty) {
    tempLearned.add(const FlSpot(0, 0));
    tempLearning.add(const FlSpot(0, 0));
    tempDates.add("Today");
  }

  return UserStats(
    totalWords: totalWords,
    learning: lrn,
    mastered: lrd,
    newWords: n,
    fresh: fresh,
    fading: fading,
    dormant: dormant,
    forecast: forecast,
    learnedSpots: tempLearned,
    learningSpots: tempLearning,
    dateLabels: tempDates,
    historyMaxY: calcMax * 1.2,
    heatmapData: heat,
  );
});