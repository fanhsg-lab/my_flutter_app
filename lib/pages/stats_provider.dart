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

// 3. THE MAIN PROVIDER
final statsProvider = FutureProvider<UserStats>((ref) async {
  ref.watch(dbUpdateTrigger);

  final db = await LocalDB.instance.database;
  final now = DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final userId = Supabase.instance.client.auth.currentUser?.id;

  // --- A. COUNTS & FORECAST ---
  final allWords = await db.query('user_progress');
  final totalWordsRes = await db.rawQuery('SELECT COUNT(*) FROM words');
  int totalWords = Sqflite.firstIntValue(totalWordsRes) ?? 0;

  int lrn = 0, lrd = 0;
  int fresh = 0, fading = 0, dormant = 0;
  List<int> forecast = List.filled(7, 0);
  
  // 🔥 HEATMAP PREP: Start with an empty map
  Map<DateTime, int> heat = {};

  for (var row in allWords) {
    String status = row['status'] as String;
    
    // 1. POPULATE HEATMAP FROM SAVED PROGRESS
    // This captures the LAST time you touched a word.
    if (row['last_reviewed'] != null) {
      DateTime lr = DateTime.parse(row['last_reviewed'] as String).toLocal();
      DateTime cleanLr = DateTime(lr.year, lr.month, lr.day);
      heat[cleanLr] = (heat[cleanLr] ?? 0) + 1;
    }

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

  // 2. ADD LOCAL LOGS (For today's high-detail activity)
  final logs = await db.query('attempt_logs');
  for (var log in logs) {
    DateTime dt = DateTime.parse(log['attempted_at'] as String).toLocal();
    DateTime cleanDate = DateTime(dt.year, dt.month, dt.day);
    heat[cleanDate] = (heat[cleanDate] ?? 0) + 1;
  }

  // --- C. CLOUD HISTORY BACKFILL ---
  List<FlSpot> tempLearned = [];
  List<FlSpot> tempLearning = [];
  List<String> tempDates = [];
  double calcMax = 10;

  if (userId != null) {
    try {
      final response = await Supabase.instance.client
          .from('daily_stats')
          .select('date, learned_count, reviewing_count') 
          .eq('user_id', userId)
          .order('date', ascending: true)
          .limit(365); // 🔥 UPDATE: Fetch full year (was 60)

      int index = 0;
      for (var row in response) {
        double valLearned = (row['learned_count'] as num).toDouble();
        double valLearning = (row['reviewing_count'] as num).toDouble();
        
        tempLearned.add(FlSpot(index.toDouble(), valLearned));
        tempLearning.add(FlSpot(index.toDouble(), valLearning));
        
        DateTime dateObj = DateTime.parse(row['date']).toLocal();
        tempDates.add(DateFormat('MMM d').format(dateObj));

        if (valLearned > calcMax) calcMax = valLearned;
        if (valLearning > calcMax) calcMax = valLearning;
        
        // --- 🔥 FILL GAPS IN HEATMAP (THE FIX) 🔥 ---
        DateTime cleanDate = DateTime(dateObj.year, dateObj.month, dateObj.day);
        
        // Check if we have ANY local data for this date.
        int currentScore = heat[cleanDate] ?? 0;

        // If local score is 0, but Cloud says we existed that day -> Force a score.
        // We give it '5' so it shows up as a medium-colored block.
        if (currentScore == 0) {
           heat[cleanDate] = 5; 
        } 
        // If we already have local data (e.g. score 50), we keep the local data 
        // because it's more accurate.
        
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