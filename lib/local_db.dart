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
    onDatabaseChanged.value = !onDatabaseChanged.value; // Toggle to trigger listeners
  }
// --- REPAIR TOOL: FORCE LINK WORDS TO CHAPTER 6 ---
  // --- EMERGENCY TOOL: DOWNLOAD WORDS FROM CLOUD ---
// --- FINAL TOOL: DOWNLOAD ALL WORDS FOR CHAPTER 6 ---
  Future<void> forceDownloadChapter6() async {
    final db = await instance.database;
    final supabase = Supabase.instance.client;
    
    debugPrint("☁️ CONNECTING TO CLOUD TO FETCH ALL CHAPTER 6 WORDS...");

    // 1. Get the LOCAL Lesson ID (The "Bucket" on your phone)
    final localLessonRes = await db.query('lessons', where: 'chapter_number = 6');
    if (localLessonRes.isEmpty) {
        debugPrint("❌ No local lesson found for Ch 6. Cannot attach words.");
        return;
    }
    final int localLessonId = localLessonRes.first['id'] as int;
    debugPrint("📂 Local Bucket ID: $localLessonId");

    try {
      // 2. Get the CLOUD Lesson ID (The "Bucket" on the server)
      // We ask Supabase: "Which lesson is Chapter 6?"
      final cloudLessonRes = await supabase
          .from('lessons')
          .select('id')
          .eq('chapter_number', 6)
          .maybeSingle(); // Returns null if not found, instead of crashing

      if (cloudLessonRes == null) {
        debugPrint("❌ Server has no Chapter 6! You need to create it in Supabase first.");
        return;
      }
      
      final int cloudLessonId = cloudLessonRes['id'];
      debugPrint("☁️  Server Source ID: $cloudLessonId");

      // 3. Fetch ALL words from the Cloud Bucket
      final List<dynamic> allCloudWords = await supabase
          .from('words')
          .select()
          .eq('lesson_id', cloudLessonId); // Get everything in that lesson

      if (allCloudWords.isEmpty) {
        debugPrint("⚠️ Server has the Lesson, but it is empty (0 words).");
        return;
      }

      debugPrint("✅ Found ${allCloudWords.length} words on Server. Downloading...");

      // 4. Save them to the Phone
      int count = 0;
      for (var w in allCloudWords) {
        await db.insert('words', {
          'id': w['id'], 
          'lesson_id': localLessonId, // IMPORTANT: Link to the LOCAL bucket ID
          'es': w['es'], 
          'en': w['en']
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
      
      debugPrint("🎉 SUCCESS! Downloaded $count words. Restart App.");

    } catch (e) {
      debugPrint("💥 ERROR DOWNLOADING: $e");
    }
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

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }




// --- DETECTIVE TOOL: FIND WHERE THE WORDS ARE HIDING ---
  Future<void> findHiddenWords() async {
    final db = await instance.database;
    debugPrint("\n🕵️‍♂️ --- STARTING WORD HUNT ---");

    // 1. Group words by Lesson ID to see where they are clustered
    final results = await db.rawQuery('''
      SELECT lesson_id, COUNT(*) as count 
      FROM words 
      GROUP BY lesson_id
    ''');

    if (results.isEmpty) {
      debugPrint("❌ CRITICAL: Local database has 0 words total.");
    } else {
      debugPrint("✅ Found words grouped by Lesson IDs:");
      for (var row in results) {
        int id = row['lesson_id'] as int;
        int count = row['count'] as int;
        
        // Check if this ID actually exists in the Lessons table
        final lessonRow = await db.query('lessons', where: 'id = ?', whereArgs: [id]);
        String lessonName = lessonRow.isNotEmpty ? lessonRow.first['title'] as String : "UNKNOWN/ORPHAN";
        
        debugPrint("   👉 Lesson ID $id has $count words. (Title: '$lessonName')");
      }
    }
    debugPrint("🕵️‍♂️ -----------------------------\n");
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Lessons Table
    await db.execute('''
      CREATE TABLE lessons (
        id INTEGER PRIMARY KEY,
        title TEXT,
        chapter_number INTEGER,
        book_id INTEGER
      )
    ''');

    // 2. Words Table
    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY,
        lesson_id INTEGER,
        es TEXT,
        en TEXT
      )
    ''');

    // 3. User Progress (The offline cache)
    await db.execute('''
      CREATE TABLE user_progress (
        word_id INTEGER PRIMARY KEY,
        status TEXT,
        strength REAL,
        last_reviewed TEXT,
        next_due_at TEXT,
        consecutive_correct INTEGER,
        total_attempts INTEGER,
        total_correct INTEGER,
        needs_sync INTEGER DEFAULT 0 
      )
    ''');
    
    // 4. Offline Attempt Logs
    await db.execute('''
      CREATE TABLE attempt_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER,
        correct INTEGER,
        attempted_at TEXT
      )
    ''');
  }

  // --- SYNC ENGINE ---
 // --- SYNC ENGINE (OFFLINE FIRST) ---
  
 // --- SYNC ENGINE (SMART & SCALABLE) ---
  bool _isSyncing = false; 

  Future<void> syncEverything() async {
    if (_isSyncing) return; // Block duplicate calls

    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) return;

    _isSyncing = true;
    final supabase = Supabase.instance.client;
    final db = await instance.database;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _isSyncing = false; 
      return;
    }

    try {
      debugPrint("🚀 Starting Smart Sync...");

      // --- STEP A: UPLOAD LOCAL PROGRESS (Always keep this) ---
      // This is already efficient. It only uploads what changed.
      final unsyncedProgress = await db.query('user_progress', where: 'needs_sync = ?', whereArgs: [1]);
      if (unsyncedProgress.isNotEmpty) {
        debugPrint("⬆️ Uploading ${unsyncedProgress.length} changes...");
        for (var row in unsyncedProgress) {
            await supabase.from('user_word_progress').upsert({
              'user_id': userId,
              'word_id': row['word_id'],
              'status': row['status'],
              'strength': row['strength'],
              'consecutive_correct': row['consecutive_correct'],
              'next_due_at': row['next_due_at'],
              'last_reviewed': row['last_reviewed'],
              'total_attempts': row['total_attempts'],
              'total_correct': row['total_correct'],
            }, onConflict: 'user_id, word_id');

            await db.update('user_progress', {'needs_sync': 0}, where: 'word_id = ?', whereArgs: [row['word_id']]);
        }
      }

     // --- STEP B: SMART DOWNLOAD (The Optimization) ---
      
      // 1. Check Local Count
      final localCountRes = await db.rawQuery('SELECT COUNT(*) FROM words');
      int localCount = Sqflite.firstIntValue(localCountRes) ?? 0;

      // 2. Check Server Count (Fixed for v2 SDK)
      // ✅ FIX: Use .count() directly. It performs a HEAD request and returns an int.
      final int serverCount = await supabase
          .from('words')
          .count();

      debugPrint("📊 Check: Phone has $localCount words. Server has $serverCount.");

      // 3. DECIDE: Do we need to download?
      if (serverCount == localCount) {
        debugPrint("✅ Sync Optimized: No new words to download. Skipping.");
      } else {
        // Only if numbers don't match, we download the new stuff
        debugPrint("📥 Found new content! Downloading difference...");
        
        List<dynamic> allWords = [];
        int start = 0;
        const int batchSize = 1000;
        bool moreAvailable = true;

        while (moreAvailable) {
          final batch = await supabase
              .from('words')
              .select()
              .range(start, start + batchSize - 1);

          if (batch.isEmpty) {
            moreAvailable = false;
          } else {
            allWords.addAll(batch);
            start += batchSize;
            if (batch.length < batchSize) moreAvailable = false;
          }
        }
        
        // Save to DB
        final batchOps = db.batch();
        for (var w in allWords) {
          batchOps.insert('words', {
            'id': w['id'], 
            'lesson_id': w['lesson_id'], 
            'es': w['es'], 
            'en': w['en']
          }, conflictAlgorithm: ConflictAlgorithm.replace); 
        }
        await batchOps.commit(noResult: true);
        debugPrint("✅ Updated ${allWords.length} words.");
      }

    } catch (e) {
      debugPrint("❌ Sync Error: $e");
    } finally {
      _isSyncing = false; 
    }
  }

  // Get Stats for Dashboard
  Future<List<LessonData>> getDashboardLessons() async {
    final db = await instance.database;
    final nowStr = DateTime.now().toUtc().toIso8601String();

    // Fetch all lessons
    final lessons = await db.query('lessons', orderBy: 'chapter_number ASC');
    List<LessonData> results = [];

    for (var l in lessons) {
      final lessonId = l['id'] as int;
      
      // Count total words in this lesson
      final totalRes = await db.rawQuery('SELECT COUNT(*) as count FROM words WHERE lesson_id = ?', [lessonId]);
      int total = Sqflite.firstIntValue(totalRes) ?? 0;

      // Count Mastered (Green)
      // Status is 'learned' or 'consolidating' AND due date is in the future
      final learnedRes = await db.rawQuery('''
        SELECT COUNT(*) as count FROM user_progress up
        JOIN words w ON up.word_id = w.id
        WHERE w.lesson_id = ? 
        AND (up.status = 'learned' OR up.status = 'consolidating')
        AND up.next_due_at > ?
      ''', [lessonId, nowStr]);
      int learned = Sqflite.firstIntValue(learnedRes) ?? 0;

      // Count Review (Orange)
      // Status 'learning' OR (Status known AND due date is past)
      final reviewRes = await db.rawQuery('''
        SELECT COUNT(*) as count FROM user_progress up
        JOIN words w ON up.word_id = w.id
        WHERE w.lesson_id = ? 
        AND (
          up.status = 'learning' 
          OR 
          ((up.status = 'learned' OR up.status = 'consolidating') AND up.next_due_at <= ?)
        )
      ''', [lessonId, nowStr]);
      int review = Sqflite.firstIntValue(reviewRes) ?? 0;

      int unseen = total - (learned + review);
      if (unseen < 0) unseen = 0;

      results.add(LessonData(
        id: lessonId,
        chapter_number: l['chapter_number'] as int,
        title: l['title'] as String,
        learned: learned,
        learning: review,
        unseen: unseen
      ));
    }
    return results;
  }

  // Save Progress Offline
  Future<void> updateProgressLocal({
    required int wordId,
    required String status,
    required double strength,
    required DateTime nextDue,
    required int streak,
    required int totalAttempts,
    required int totalCorrect,
    required bool isCorrect
  }) async {
    final db = await instance.database;
    
    await db.insert('user_progress', {
      'word_id': wordId,
      'status': status,
      'strength': strength,
      'consecutive_correct': streak,
      'next_due_at': nextDue.toIso8601String(),
      'last_reviewed': DateTime.now().toUtc().toIso8601String(),
      'total_attempts': totalAttempts,
      'total_correct': totalCorrect,
      'needs_sync': 1 
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('attempt_logs', {
      'word_id': wordId,
      'correct': isCorrect ? 1 : 0,
      'attempted_at': DateTime.now().toUtc().toIso8601String()
    });
    
    syncEverything(); // Try to push if online
  }
}

// Data class for UI
class LessonData { 
  final int id; 
  final String title; 
  final int learned; 
  final int learning; 
  final int unseen; 
  final int chapter_number; 
  LessonData({required this.id, required this.title, required this.learned, required this.learning, required this.unseen, required this.chapter_number}); 
}