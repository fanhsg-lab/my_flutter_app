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
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onOpen: _onOpen,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('CREATE TABLE lessons (id INTEGER PRIMARY KEY, title TEXT, chapter_number INTEGER, book_id INTEGER)');
    await db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY, lesson_id INTEGER, es TEXT, en TEXT)');
    await db.execute('CREATE TABLE user_progress (word_id INTEGER PRIMARY KEY, status TEXT, strength REAL, last_reviewed TEXT, next_due_at TEXT, consecutive_correct INTEGER, total_attempts INTEGER, total_correct INTEGER, needs_sync INTEGER DEFAULT 0)');
    // Note: 'unique(word_id, attempted_at)' helps us ignore duplicates during aggressive sync
    await db.execute('CREATE TABLE attempt_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, word_id INTEGER, correct INTEGER, attempted_at TEXT, synced INTEGER DEFAULT 0, CONSTRAINT unique_log UNIQUE(word_id, attempted_at))');
    await db.execute('CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  // =========================================================
  // 🔄 AUTOMATIC SYNC ENGINE
  // =========================================================
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
      // 1. CHECK USER & RESET IF NEEDED
      final metaRes = await db.query('app_meta', where: 'key = ?', whereArgs: ['current_user_id']);
      String? storedUserId = metaRes.isNotEmpty ? metaRes.first['value'] as String? : null;

      if (storedUserId != null && storedUserId != userId) {
        debugPrint("🚨 NEW USER DETECTED! Wiping old data...");
        await db.delete('user_progress');
        await db.delete('attempt_logs');
        await db.insert('app_meta', {'key': 'current_user_id', 'value': userId}, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await db.insert('app_meta', {'key': 'current_user_id', 'value': userId}, conflictAlgorithm: ConflictAlgorithm.replace);
        // If same user, upload any pending data first
        await _pushPendingData(db, supabase, userId);
      }

      // 2. DOWNLOAD CONTENT
      await _pullContent(db, supabase);

      // 3. DOWNLOAD STATS
      await _pullProgress(db, supabase, userId);

      // 4. 🔥 SMART HISTORY DOWNLOAD (The Fix) 🔥
      // We check if Cloud has more logs than we do. If so, we download.
      final localCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM attempt_logs')) ?? 0;
      final cloudCountRes = await supabase.from('attempt_logs').count(CountOption.exact);
      final cloudCount = await supabase.from('attempt_logs').count(CountOption.exact);

      debugPrint("📊 Sync Check: Local Logs ($localCount) vs Cloud Logs ($cloudCount)");

      if (cloudCount > localCount) {
        debugPrint("📥 Cloud has more history. Downloading difference...");
        await _downloadAllLogs(db, supabase, userId);
      } else {
        debugPrint("✅ History is up to date.");
      }

      notifyDataChanged(); 
      debugPrint("✅ Sync Complete!");

    } catch (e) {
      debugPrint("❌ Sync Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // --- ⬆️ PUSH (Upload) ---
  Future<void> syncProgress() async {
     // This is the lightweight function called after a game
     // It just calls the internal pusher
     await _pushPendingData(await instance.database, Supabase.instance.client, Supabase.instance.client.auth.currentUser?.id ?? '');
  }

  Future<void> _pushPendingData(Database db, SupabaseClient supabase, String userId) async {
      if (userId.isEmpty) return;

      // Upload Stats
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

      // Upload Logs (Batched)
      final unsyncedLogs = await db.query('attempt_logs', where: 'synced = ?', whereArgs: [0]);
      if (unsyncedLogs.isNotEmpty) {
        debugPrint("☁️ Uploading ${unsyncedLogs.length} logs...");
        const int batchSize = 500;
        for (var i = 0; i < unsyncedLogs.length; i += batchSize) {
          final end = (i + batchSize < unsyncedLogs.length) ? i + batchSize : unsyncedLogs.length;
          final batch = unsyncedLogs.sublist(i, end);
          final logPayload = batch.map((l) => {
            'user_id': userId, 'word_id': l['word_id'], 'correct': l['correct'] == 1, 'attempted_at': l['attempted_at']
          }).toList();
          await supabase.from('attempt_logs').upsert(logPayload);
        }
        await db.update('attempt_logs', {'synced': 1}, where: 'synced = 0');
      }
  }

  // --- ⬇️ PULL (Download) ---
  Future<void> _downloadAllLogs(Database db, SupabaseClient supabase, String userId) async {
    int start = 0;
    bool fetching = true;
    const int limit = 1000;

    while (fetching) {
      final cloudLogs = await supabase
          .from('attempt_logs')
          .select()
          .eq('user_id', userId)
          .range(start, start + limit - 1);
      
      if (cloudLogs.isEmpty) {
        fetching = false;
      } else {
          final batch = db.batch();
          for (var log in cloudLogs) {
            // INSERT OR IGNORE: This ensures we don't crash if we already have the log
            batch.rawInsert(
              'INSERT OR IGNORE INTO attempt_logs (word_id, correct, attempted_at, synced) VALUES (?, ?, ?, ?)',
              [log['word_id'], log['correct'] == true ? 1 : 0, log['attempted_at'], 1]
            );
          }
          await batch.commit(noResult: true);
          debugPrint("   ⬇️ Downloaded logs $start - ${start + cloudLogs.length}");
          
          if (cloudLogs.length < limit) fetching = false; 
          else start += limit; 
      }
    }
  }

  Future<void> _pullContent(Database db, SupabaseClient supabase) async {
      final cloudLessons = await supabase.from('lessons').select();
      final lessonBatch = db.batch();
      for (var l in cloudLessons) {
        lessonBatch.insert('lessons', {'id': l['id'], 'title': l['title'], 'chapter_number': l['chapter_number'], 'book_id': l['book_id']}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await lessonBatch.commit(noResult: true);

      final localCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM words')) ?? 0;
      if (localCount == 0) {
        int start = 0;
        bool fetching = true;
        while (fetching) {
          final cloudWords = await supabase.from('words').select('id, lesson_id, es, en').range(start, start + 999);
          if (cloudWords.isEmpty) { fetching = false; } 
          else {
            final wordBatch = db.batch();
            for (var w in cloudWords) {
              wordBatch.insert('words', {'id': w['id'], 'lesson_id': w['lesson_id'], 'es': w['es'], 'en': w['en']}, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await wordBatch.commit(noResult: true);
            start += 1000;
          }
        }
      }
  }

  Future<void> _pullProgress(Database db, SupabaseClient supabase, String userId) async {
      final remoteProgress = await supabase.from('user_word_progress').select().eq('user_id', userId);
      if (remoteProgress.isNotEmpty) {
        final batch = db.batch();
        for (var p in remoteProgress) {
          batch.insert('user_progress', {
            'word_id': p['word_id'], 'status': p['status'], 'strength': p['strength'], 'last_reviewed': p['last_reviewed'], 'next_due_at': p['next_due_at'], 'consecutive_correct': p['consecutive_correct'], 'total_attempts': p['total_attempts'], 'total_correct': p['total_correct'], 'needs_sync': 0
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
  }

  // Update Progress (Called from Game)
  Future<void> updateProgressLocal({required int wordId, required String status, required double strength, required DateTime nextDue, required int streak, required int totalAttempts, required int totalCorrect, required bool isCorrect}) async {
    final db = await instance.database;
    await db.insert('user_progress', {
      'word_id': wordId, 'status': status, 'strength': strength, 'consecutive_correct': streak, 'next_due_at': nextDue.toIso8601String(), 'last_reviewed': DateTime.now().toUtc().toIso8601String(), 'total_attempts': totalAttempts, 'total_correct': totalCorrect, 'needs_sync': 1
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    
    // Use INSERT OR IGNORE logic via try/catch or helper if uniqueness is strict, 
    // but standard insert is fine here as we handle upstream logic
    await db.insert('attempt_logs', {
      'word_id': wordId, 'correct': isCorrect ? 1 : 0, 'attempted_at': DateTime.now().toUtc().toIso8601String(), 'synced': 0
    });
  }

  Future<List<LessonData>> getDashboardLessons() async {
    final db = await instance.database;
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final lessons = await db.query('lessons', orderBy: 'chapter_number ASC');
    List<LessonData> results = [];
    for (var l in lessons) {
      final lessonId = l['id'] as int;
      final wordsData = await db.rawQuery('SELECT up.status, up.next_due_at FROM words w LEFT JOIN user_progress up ON w.id = up.word_id WHERE w.lesson_id = ?', [lessonId]);
      int learned = 0, learning = 0, unseen = 0;
      List<int> forecast = List.filled(7, 0); 
      for (var row in wordsData) {
        String status = row['status'] as String? ?? 'new';
        String? nextDueStr = row['next_due_at'] as String?;
        if (status == 'new') unseen++; else if (status == 'learning') learning++; else if (status == 'consolidating' || status == 'learned') { if (nextDueStr != null && DateTime.parse(nextDueStr).toLocal().isBefore(now)) learning++; else learned++; }
        if (nextDueStr != null) { DateTime due = DateTime.parse(nextDueStr).toLocal(); int diffDays = DateTime(due.year, due.month, due.day).difference(todayMidnight).inDays; if (diffDays < 0) forecast[0]++; else if (diffDays < 7) forecast[diffDays]++; }
      }
      results.add(LessonData(id: lessonId, title: l['title'] as String, learned: learned, learning: learning, unseen: unseen, chapter_number: l['chapter_number'] as int, forecast: forecast));
    }
    return results;
  }
}

class LessonData { 
  final int id; final String title; final int learned; final int learning; final int unseen; final int chapter_number; final List<int> forecast; 
  LessonData({required this.id, required this.title, required this.learned, required this.learning, required this.unseen, required this.chapter_number, required this.forecast}); 
}