import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class LocalDB {
  static final LocalDB instance = LocalDB._init();
  static Database? _database;
  final ValueNotifier<bool> onDatabaseChanged = ValueNotifier(false);
  
  void notifyDataChanged() {
    onDatabaseChanged.value = !onDatabaseChanged.value;
  }

  LocalDB._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('offline_learning.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    // Added onOpen to ensure migration support for existing users
    return await openDatabase(path, version: 1, onCreate: _createDB, onOpen: _onOpen);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('CREATE TABLE lessons (id INTEGER PRIMARY KEY, title TEXT, chapter_number INTEGER, book_id INTEGER)');
    await db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY, lesson_id INTEGER, es TEXT, en TEXT)');
    await db.execute('CREATE TABLE user_progress (word_id INTEGER PRIMARY KEY, status TEXT, strength REAL, last_reviewed TEXT, next_due_at TEXT, consecutive_correct INTEGER, total_attempts INTEGER, total_correct INTEGER, needs_sync INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE attempt_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, word_id INTEGER, correct INTEGER, attempted_at TEXT, synced INTEGER DEFAULT 0)');
    // 🔒 META TABLE: Stores the ID of the user who owns this data
    await db.execute('CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  // Ensure app_meta exists even for users who already have the DB created
  Future<void> _onOpen(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  // --- SYNC ENGINE ---
  bool _isSyncing = false; 

  Future<void> syncEverything() async {
    if (_isSyncing) return;
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) return;

    _isSyncing = true;
    final supabase = Supabase.instance.client;
    final db = await instance.database;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) { _isSyncing = false; return; }

    try {
      // 🔥 STEP 0: CHECK OWNER & WIPE IF NEEDED 🔥
      final metaRes = await db.query('app_meta', where: 'key = ?', whereArgs: ['current_user_id']);
      String? storedUserId = metaRes.isNotEmpty ? metaRes.first['value'] as String? : null;

      if (storedUserId != null && storedUserId != userId) {
        debugPrint("🚨 DIFFERENT USER DETECTED! Wiping local data...");
        // 1. Wipe progress tables
        await db.delete('user_progress');
        await db.delete('attempt_logs');
        // 2. Update owner
        await db.insert('app_meta', {'key': 'current_user_id', 'value': userId}, conflictAlgorithm: ConflictAlgorithm.replace);
        // 3. Skip pushing (old data is irrelevant), jump straight to pulling
      } else {
        // Same user (or first login), save ID just in case
        await db.insert('app_meta', {'key': 'current_user_id', 'value': userId}, conflictAlgorithm: ConflictAlgorithm.replace);

        // --- 1. PUSH LOCAL PROGRESS (Only if same user) ---
        final unsyncedProgress = await db.query('user_progress', where: 'needs_sync = ?', whereArgs: [1]);
        for (var row in unsyncedProgress) {
          await supabase.from('user_word_progress').upsert({
            'user_id': userId, 'word_id': row['word_id'], 'status': row['status'], 
            'strength': row['strength'], 'consecutive_correct': row['consecutive_correct'], 
            'next_due_at': row['next_due_at'], 'last_reviewed': row['last_reviewed'], 
            'total_attempts': row['total_attempts'], 'total_correct': row['total_correct'],
          }, onConflict: 'user_id, word_id');
          await db.update('user_progress', {'needs_sync': 0}, where: 'word_id = ?', whereArgs: [row['word_id']]);
        }
      }

      // --- 2. PULL LESSONS ---
      final cloudLessons = await supabase.from('lessons').select();
      final lessonBatch = db.batch();
      for (var l in cloudLessons) {
        lessonBatch.insert('lessons', {
          'id': l['id'], 'title': l['title'], 'chapter_number': l['chapter_number'], 'book_id': l['book_id']
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await lessonBatch.commit(noResult: true);

      // --- 3. PULL WORDS (If empty) ---
      final localCountRes = await db.rawQuery('SELECT COUNT(*) FROM words');
      int localCount = Sqflite.firstIntValue(localCountRes) ?? 0;
      
      if (localCount == 0) {
        int start = 0;
        bool fetchingWords = true;
        while (fetchingWords) {
          final cloudWords = await supabase.from('words')
              .select('id, lesson_id, es, en')
              .range(start, start + 999);
          
          if (cloudWords.isEmpty) {
            fetchingWords = false;
          } else {
            final wordBatch = db.batch();
            for (var w in cloudWords) {
              wordBatch.insert('words', {
                'id': w['id'], 'lesson_id': w['lesson_id'], 'es': w['es'], 'en': w['en']
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await wordBatch.commit(noResult: true);
            start += 1000;
          }
        }
      }

      // --- 4. PULL REMOTE PROGRESS (Restore correct user data) ---
      final remoteProgress = await supabase.from('user_word_progress').select().eq('user_id', userId);
      if (remoteProgress.isNotEmpty) {
        final progressBatch = db.batch();
        for (var p in remoteProgress) {
          progressBatch.insert('user_progress', {
            'word_id': p['word_id'], 'status': p['status'], 'strength': p['strength'],
            'last_reviewed': p['last_reviewed'], 'next_due_at': p['next_due_at'],
            'consecutive_correct': p['consecutive_correct'], 'total_attempts': p['total_attempts'],
            'total_correct': p['total_correct'], 'needs_sync': 0
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await progressBatch.commit(noResult: true);
      }

      // --- 5. FINISH ---
      notifyDataChanged(); 
      debugPrint("✅ Sync Complete for User: $userId");

    } catch (e) {
      debugPrint("❌ Sync Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // =========================================================
  // 📊 DASHBOARD DATA (With Per-Lesson Forecast)
  // =========================================================
  Future<List<LessonData>> getDashboardLessons() async {
    final db = await instance.database;
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    final lessons = await db.query('lessons', orderBy: 'chapter_number ASC');
    List<LessonData> results = [];

    for (var l in lessons) {
      final lessonId = l['id'] as int;
      
      // Get ALL words + progress for this lesson
      final wordsData = await db.rawQuery('''
        SELECT up.status, up.next_due_at 
        FROM words w
        LEFT JOIN user_progress up ON w.id = up.word_id
        WHERE w.lesson_id = ?
      ''', [lessonId]);

      int learned = 0;
      int learning = 0;
      int unseen = 0;
      
      // [Late, Today, Tmrw, +2, +3, +4, +5+]
      List<int> forecast = List.filled(7, 0); 

      for (var row in wordsData) {
        String status = row['status'] as String? ?? 'new';
        String? nextDueStr = row['next_due_at'] as String?;

        // A. Basic Counts
        if (status == 'new') {
          unseen++;
        } else if (status == 'learning') {
          learning++;
        } else if (status == 'consolidating' || status == 'learned') {
          if (nextDueStr != null) {
             DateTime due = DateTime.parse(nextDueStr).toLocal();
             if (due.isBefore(now)) learning++; else learned++;
          } else {
             learned++;
          }
        }

        // B. Forecast Logic (For the Bar Chart)
        if (nextDueStr != null) {
          DateTime due = DateTime.parse(nextDueStr).toLocal();
          DateTime dueMidnight = DateTime(due.year, due.month, due.day);
          int diffDays = dueMidnight.difference(todayMidnight).inDays;

          if (diffDays < 0) forecast[0]++; // Late
          else if (diffDays < 7) forecast[diffDays]++; 
        }
      }

      results.add(LessonData(
        id: lessonId,
        chapter_number: l['chapter_number'] as int,
        title: l['title'] as String,
        learned: learned,
        learning: learning,
        unseen: unseen,
        forecast: forecast,
      ));
    }
    return results;
  }

  // Update Progress
  Future<void> updateProgressLocal({required int wordId, required String status, required double strength, required DateTime nextDue, required int streak, required int totalAttempts, required int totalCorrect, required bool isCorrect}) async {
    final db = await instance.database;
    await db.insert('user_progress', {'word_id': wordId, 'status': status, 'strength': strength, 'consecutive_correct': streak, 'next_due_at': nextDue.toIso8601String(), 'last_reviewed': DateTime.now().toUtc().toIso8601String(), 'total_attempts': totalAttempts, 'total_correct': totalCorrect, 'needs_sync': 1}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('attempt_logs', {'word_id': wordId, 'correct': isCorrect ? 1 : 0, 'attempted_at': DateTime.now().toUtc().toIso8601String(), 'synced': 0});
    syncEverything(); 
  }
  
  // Helpers
  Future<void> forceDownloadChapter6() async {} 
  Future<void> findHiddenWords() async {}
}

class LessonData { 
  final int id; 
  final String title; 
  final int learned; 
  final int learning; 
  final int unseen; 
  final int chapter_number;
  final List<int> forecast; 

  LessonData({
    required this.id, 
    required this.title, 
    required this.learned, 
    required this.learning, 
    required this.unseen, 
    required this.chapter_number,
    required this.forecast,
  }); 
}