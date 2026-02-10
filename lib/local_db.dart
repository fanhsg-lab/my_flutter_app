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
    _database = await _initDB('offline_learning_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 6,  // Version 6 adds lesson_words junction table
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onOpen: _onOpen,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // GLOBAL TABLES (shared across all users on this device)

    // Teachers table
    await db.execute('''
      CREATE TABLE teachers (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');

    // Books table
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        level TEXT,
        teacher_id INTEGER,
        source_language TEXT DEFAULT 'es'
      )
    ''');

    await db.execute('''
      CREATE TABLE lessons (
        id INTEGER PRIMARY KEY,
        title TEXT,
        chapter_number INTEGER,
        book_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY,
        lesson_id INTEGER,
        es TEXT,
        en TEXT
      )
    ''');

    // Junction table for many-to-many words <-> lessons
    await db.execute('''
      CREATE TABLE lesson_words (
        lesson_id INTEGER NOT NULL,
        word_id INTEGER NOT NULL,
        PRIMARY KEY (lesson_id, word_id)
      )
    ''');

    // USER-SPECIFIC TABLES (per user)
    await db.execute('''
      CREATE TABLE user_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        word_id INTEGER NOT NULL,
        status TEXT DEFAULT 'new',
        strength REAL DEFAULT 1.0,
        last_reviewed TEXT,
        next_due_at TEXT,
        consecutive_correct INTEGER DEFAULT 0,
        total_attempts INTEGER DEFAULT 0,
        total_correct INTEGER DEFAULT 0,
        needs_sync INTEGER DEFAULT 0,
        UNIQUE(user_id, word_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE attempt_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        word_id INTEGER NOT NULL,
        correct INTEGER NOT NULL,
        attempted_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        UNIQUE(user_id, word_id, attempted_at)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // ANALYTICS TABLE (aggregated daily stats)
    await db.execute('''
      CREATE TABLE daily_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        date TEXT NOT NULL,
        total_words INTEGER DEFAULT 0,
        learned_count INTEGER DEFAULT 0,
        reviewing_count INTEGER DEFAULT 0,
        attempts_sum INTEGER DEFAULT 0,
        UNIQUE(user_id, date)
      )
    ''');

    // Indexes for performance
    await db.execute('CREATE INDEX idx_user_progress_user ON user_progress(user_id)');
    await db.execute('CREATE INDEX idx_attempt_logs_user ON attempt_logs(user_id)');
    await db.execute('CREATE INDEX idx_daily_stats_user_date ON daily_stats(user_id, date DESC)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migration from v1 to v2: Add user_id columns
      debugPrint("🔧 Migrating database from v$oldVersion to v$newVersion");

      // Get current user
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id ?? 'unknown';

      // Backup old data
      final oldProgress = await db.query('user_progress');
      final oldLogs = await db.query('attempt_logs');

      // Drop old tables
      await db.execute('DROP TABLE IF EXISTS user_progress');
      await db.execute('DROP TABLE IF EXISTS attempt_logs');

      // Create new tables with user_id
      await db.execute('''
        CREATE TABLE user_progress (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          word_id INTEGER NOT NULL,
          status TEXT DEFAULT 'new',
          strength REAL DEFAULT 1.0,
          last_reviewed TEXT,
          next_due_at TEXT,
          consecutive_correct INTEGER DEFAULT 0,
          total_attempts INTEGER DEFAULT 0,
          total_correct INTEGER DEFAULT 0,
          needs_sync INTEGER DEFAULT 1,
          UNIQUE(user_id, word_id)
        )
      ''');

      await db.execute('''
        CREATE TABLE attempt_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          word_id INTEGER NOT NULL,
          correct INTEGER NOT NULL,
          attempted_at TEXT NOT NULL,
          synced INTEGER DEFAULT 0,
          UNIQUE(user_id, word_id, attempted_at)
        )
      ''');

      // Restore data with user_id
      for (var row in oldProgress) {
        await db.insert('user_progress', {
          'user_id': userId,
          'word_id': row['word_id'],
          'status': row['status'],
          'strength': row['strength'],
          'last_reviewed': row['last_reviewed'],
          'next_due_at': row['next_due_at'],
          'consecutive_correct': row['consecutive_correct'],
          'total_attempts': row['total_attempts'],
          'total_correct': row['total_correct'],
          'needs_sync': 1,  // Mark for re-sync
        });
      }

      for (var row in oldLogs) {
        await db.insert('attempt_logs', {
          'user_id': userId,
          'word_id': row['word_id'],
          'correct': row['correct'],
          'attempted_at': row['attempted_at'],
          'synced': 0,  // Mark for re-sync
        });
      }

      await db.execute('CREATE INDEX idx_user_progress_user ON user_progress(user_id)');
      await db.execute('CREATE INDEX idx_attempt_logs_user ON attempt_logs(user_id)');

      // Add daily_stats table for aggregated analytics
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_stats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          date TEXT NOT NULL,
          total_words INTEGER DEFAULT 0,
          learned_count INTEGER DEFAULT 0,
          reviewing_count INTEGER DEFAULT 0,
          attempts_sum INTEGER DEFAULT 0,
          UNIQUE(user_id, date)
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_daily_stats_user_date ON daily_stats(user_id, date DESC)');

      debugPrint("✅ Migration to v2 complete!");
    }

    // Migration from v2 to v3: Add attempts_sum column
    if (oldVersion < 3) {
      debugPrint("🔧 Migrating database from v$oldVersion to v3 (adding attempts_sum)");

      try {
        await db.execute('ALTER TABLE daily_stats ADD COLUMN attempts_sum INTEGER DEFAULT 0');
        debugPrint("   ✅ Added attempts_sum column to daily_stats table");
      } catch (e) {
        debugPrint("   ⚠️ Could not add attempts_sum column (may already exist): $e");
      }

      debugPrint("✅ Migration to v3 complete!");
    }

    // Migration from v3 to v4: Add teachers and books tables
    if (oldVersion < 4) {
      debugPrint("🔧 Migrating database from v$oldVersion to v4 (adding teachers/books)");

      try {
        // Create teachers table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS teachers (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT
          )
        ''');
        debugPrint("   ✅ Created teachers table");

        // Create books table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS books (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            level TEXT,
            teacher_id INTEGER
          )
        ''');
        debugPrint("   ✅ Created books table");

        debugPrint("✅ Migration to v4 complete!");
      } catch (e) {
        debugPrint("   ⚠️ Error during v4 migration: $e");
      }
    }

    // Migration from v4 to v5: Add source_language column to books
    if (oldVersion < 5) {
      debugPrint("🔧 Migrating database from v$oldVersion to v5 (adding source_language to books)");
      try {
        await db.execute("ALTER TABLE books ADD COLUMN source_language TEXT DEFAULT 'es'");
        debugPrint("   ✅ Added source_language column to books table");
      } catch (e) {
        debugPrint("   ⚠️ Could not add source_language column (may already exist): $e");
      }
      debugPrint("✅ Migration to v5 complete!");
    }

    // Migration from v5 to v6: Add lesson_words junction table
    if (oldVersion < 6) {
      debugPrint("🔧 Migrating database from v$oldVersion to v6 (adding lesson_words table)");
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS lesson_words (
            lesson_id INTEGER NOT NULL,
            word_id INTEGER NOT NULL,
            PRIMARY KEY (lesson_id, word_id)
          )
        ''');
        // Populate from existing words.lesson_id
        await db.execute('''
          INSERT OR IGNORE INTO lesson_words (lesson_id, word_id)
          SELECT lesson_id, id FROM words WHERE lesson_id IS NOT NULL
        ''');
        debugPrint("   ✅ Created and populated lesson_words table");
      } catch (e) {
        debugPrint("   ⚠️ Error during v6 migration: $e");
      }
      debugPrint("✅ Migration to v6 complete!");
    }
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  // =========================================================
  // 🔄 IMPROVED SYNC ENGINE (Multi-User Safe)
  // =========================================================
  bool _isSyncing = false;

  Future<void> syncEverything() async {
    if (_isSyncing) {
      debugPrint("⏭️ Sync already in progress, skipping");
      return;
    }

    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      debugPrint("📡 No internet, sync skipped");
      return;
    }

    _isSyncing = true;
    final supabase = Supabase.instance.client;
    final db = await instance.database;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      debugPrint("❌ No user logged in");
      _isSyncing = false;
      return;
    }

    try {
      debugPrint("🔄 Starting sync for user: $userId");

      // 1. CHECK USER & UPDATE METADATA
      final metaRes = await db.query('app_meta', where: 'key = ?', whereArgs: ['current_user_id']);
      String? storedUserId = metaRes.isNotEmpty ? metaRes.first['value'] as String? : null;

      if (storedUserId != null && storedUserId != userId) {
        debugPrint("🚨 NEW USER DETECTED! Switching from $storedUserId to $userId");
        // DON'T delete lessons/words - they're global
        // Just update the current user
      }

      await db.insert('app_meta',
        {'key': 'current_user_id', 'value': userId},
        conflictAlgorithm: ConflictAlgorithm.replace
      );

      // 2. PUSH USER'S PENDING DATA (if same user or new user)
      try {
        await _pushPendingData(db, supabase, userId);
      } catch (e) {
        debugPrint("⚠️ Push failed (will continue with pull): $e");
      }

      // 3. DOWNLOAD GLOBAL CONTENT (only if server version changed)
      //    Reads a single row from 'app_settings' in Supabase. Bump 'content_version'
      //    there whenever you add/change lessons or words.
      int remoteVersion = 0;
      try {
        final versionRes = await supabase
            .from('app_settings')
            .select('value')
            .eq('key', 'content_version')
            .maybeSingle();
        remoteVersion = int.tryParse(versionRes?['value']?.toString() ?? '0') ?? 0;
      } catch (e) {
        debugPrint("⚠️ Could not fetch content_version: $e");
      }

      final localVersionRes = await db.query('app_meta', where: 'key = ?', whereArgs: ['content_version']);
      final localVersion = int.tryParse(
        localVersionRes.isNotEmpty ? localVersionRes.first['value']?.toString() ?? '0' : '0'
      ) ?? 0;
      final hasLocalContent = (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM lesson_words')) ?? 0) > 0;

      if (remoteVersion > localVersion || !hasLocalContent) {
        debugPrint("📥 Content sync needed (local v$localVersion → remote v$remoteVersion, hasContent: $hasLocalContent)");
        await _pullContent(db, supabase);
        await db.insert('app_meta',
          {'key': 'content_version', 'value': remoteVersion.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // 3.5 CLEAN UP orphaned progress (word_ids that no longer exist after dedup)
        final orphaned = await db.rawQuery('''
          SELECT up.word_id FROM user_progress up
          LEFT JOIN words w ON w.id = up.word_id
          WHERE w.id IS NULL AND up.user_id = ?
        ''', [userId]);
        if (orphaned.isNotEmpty) {
          final orphanIds = orphaned.map((r) => r['word_id']).toList();
          debugPrint("🧹 Cleaning ${orphanIds.length} orphaned progress records");
          final placeholders = orphanIds.map((_) => '?').join(',');
          await db.rawDelete(
            'DELETE FROM user_progress WHERE word_id IN ($placeholders) AND user_id = ?',
            [...orphanIds, userId],
          );
        }
      } else {
        debugPrint("⏭️ Content up to date (v$localVersion), skipping content pull");
      }

      // 4. DOWNLOAD USER'S PROGRESS (always sync)
      await _pullProgress(db, supabase, userId);

      // 5. DOWNLOAD USER'S DAILY STATS (always sync)
      await _pullDailyStats(db, supabase, userId);

      notifyDataChanged();
      debugPrint("✅ Sync Complete for $userId!");

    } catch (e, stackTrace) {
      debugPrint("❌ Sync Error: $e");
      debugPrint("Stack trace: $stackTrace");
    } finally {
      _isSyncing = false;
    }
  }

  // --- ⬆️ PUSH (Upload) ---
  Future<void> syncProgress() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await _pushPendingData(await instance.database, Supabase.instance.client, userId);
  }

  Future<void> _pushPendingData(Database db, SupabaseClient supabase, String userId) async {
    try {
      // Upload Progress — only for word_ids that still exist in local words table
      final unsyncedProgress = await db.rawQuery('''
        SELECT up.* FROM user_progress up
        INNER JOIN words w ON w.id = up.word_id
        WHERE up.user_id = ? AND up.needs_sync = 1
      ''', [userId]);

      if (unsyncedProgress.isNotEmpty) {
        debugPrint("☁️ Uploading ${unsyncedProgress.length} progress records...");

        // Batch upserts in groups of 100
        const int batchSize = 100;
        for (var i = 0; i < unsyncedProgress.length; i += batchSize) {
          final end = (i + batchSize < unsyncedProgress.length) ? i + batchSize : unsyncedProgress.length;
          final batch = unsyncedProgress.sublist(i, end);

          final progressPayload = batch.map((row) => {
            'user_id': userId,
            'word_id': row['word_id'],
            'status': row['status'],
            'strength': row['strength'],
            'consecutive_correct': row['consecutive_correct'],
            'next_due_at': row['next_due_at'],
            'last_reviewed': row['last_reviewed'],
            'total_attempts': row['total_attempts'],
            'total_correct': row['total_correct'],
          }).toList();

          await supabase.from('user_word_progress').upsert(
            progressPayload,
            onConflict: 'user_id, word_id'
          );
        }

        // Mark as synced
        await db.update(
          'user_progress',
          {'needs_sync': 0},
          where: 'user_id = ? AND needs_sync = 1',
          whereArgs: [userId]
        );
      }

      // NEW: Aggregate attempt logs into daily_stats instead of syncing individual logs
      await _aggregateAndSyncDailyStats(db, supabase, userId);

    } catch (e) {
      debugPrint("❌ Push error: $e");
      rethrow;
    }
  }

  /// Aggregates local attempt_logs into daily summaries and syncs to daily_stats
  Future<void> _aggregateAndSyncDailyStats(Database db, SupabaseClient supabase, String userId) async {
    try {
      // Get all unsynced logs grouped by date
      final unsyncedLogs = await db.rawQuery('''
        SELECT
          DATE(attempted_at) as date,
          COUNT(*) as total_attempts,
          SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) as correct_attempts
        FROM attempt_logs
        WHERE user_id = ? AND synced = 0
        GROUP BY DATE(attempted_at)
      ''', [userId]);

      if (unsyncedLogs.isEmpty) {
        debugPrint("📊 No new daily stats to sync");
        return;
      }

      debugPrint("📊 Aggregating ${unsyncedLogs.length} days of activity into daily_stats...");

      // For each day, calculate learned vs reviewing counts
      List<Map<String, dynamic>> dailyStatsPayload = [];

      for (var dayLog in unsyncedLogs) {
        final date = dayLog['date'] as String;

        // Get word status breakdown for this day
        final statsForDay = await db.rawQuery('''
          SELECT
            SUM(CASE WHEN up.status IN ('consolidating', 'learned') THEN 1 ELSE 0 END) as learned_count,
            SUM(CASE WHEN up.status = 'learning' THEN 1 ELSE 0 END) as reviewing_count,
            COUNT(DISTINCT al.word_id) as total_words
          FROM attempt_logs al
          LEFT JOIN user_progress up ON al.word_id = up.word_id AND al.user_id = up.user_id
          WHERE al.user_id = ? AND DATE(al.attempted_at) = ?
        ''', [userId, date]);

        final stats = statsForDay.first;

        dailyStatsPayload.add({
          'user_id': userId,
          'date': date,
          'total_words': stats['total_words'] ?? 0,  // Cumulative snapshot
          'learned_count': stats['learned_count'] ?? 0,  // Cumulative snapshot
          'reviewing_count': stats['reviewing_count'] ?? 0,  // Cumulative snapshot
          'attempts_sum': dayLog['total_attempts'] ?? 0,  // Daily activity count
        });
      }

      // Batch upsert daily_stats
      if (dailyStatsPayload.isNotEmpty) {
        await supabase.from('daily_stats').upsert(
          dailyStatsPayload,
          onConflict: 'user_id, date'
        );
        debugPrint("   ✅ Synced ${dailyStatsPayload.length} days to daily_stats");
      }

      // Mark logs as synced
      await db.update(
        'attempt_logs',
        {'synced': 1},
        where: 'user_id = ? AND synced = 0',
        whereArgs: [userId]
      );

      // OPTIONAL: Clean up old synced logs (keep last 30 days for local analytics)
      final thirtyDaysAgo = DateTime.now().subtract(Duration(days: 30)).toIso8601String();
      final deletedCount = await db.delete(
        'attempt_logs',
        where: 'user_id = ? AND synced = 1 AND attempted_at < ?',
        whereArgs: [userId, thirtyDaysAgo]
      );

      if (deletedCount > 0) {
        debugPrint("   🗑️ Cleaned up $deletedCount old synced logs (keeping last 30 days)");
      }

    } catch (e) {
      debugPrint("❌ Daily stats aggregation error: $e");
      rethrow;
    }
  }

  // --- ⬇️ PULL (Download) ---
  Future<void> _pullContent(Database db, SupabaseClient supabase) async {
    try {
      // 1. Download ALL teachers (small, needed for selector UI)
      debugPrint("📥 Downloading teachers...");
      final cloudTeachers = await supabase.from('teachers').select();
      debugPrint("   Found ${cloudTeachers.length} teachers in cloud");

      final teacherBatch = db.batch();
      for (var t in cloudTeachers) {
        teacherBatch.insert('teachers', {
          'id': t['id'],
          'name': t['name'],
          'description': t['description']
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await teacherBatch.commit(noResult: true);
      debugPrint("   ✅ Saved ${cloudTeachers.length} teachers to local DB");

      // 2. Download ALL books (small, needed for selector UI)
      debugPrint("📥 Downloading books...");
      final cloudBooks = await supabase.from('books').select();
      debugPrint("   Found ${cloudBooks.length} books in cloud");
      for (var b in cloudBooks) {
        debugPrint("   📖 Book: id=${b['id']} title=${b['title']} teacher_id=${b['teacher_id']}");
      }

      final bookBatch = db.batch();
      for (var b in cloudBooks) {
        bookBatch.insert('books', {
          'id': b['id'],
          'title': b['title'],
          'level': b['level'],
          'teacher_id': b['teacher_id'],
          'source_language': b['source_language'] ?? 'es',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint("   Committing books batch...");
      await bookBatch.commit(noResult: true);
      debugPrint("   ✅ Saved ${cloudBooks.length} books to local DB");

      // 3. Determine scope: current teacher's books only
      debugPrint("📥 Step 3: Getting current teacher...");
      final currentTeacherId = await getCurrentTeacherId();
      debugPrint("   current_teacher_id = $currentTeacherId");
      List<int> bookIds = [];

      if (currentTeacherId != null) {
        // Get book IDs belonging to this teacher
        final teacherBooks = await supabase
            .from('books')
            .select('id')
            .eq('teacher_id', currentTeacherId);
        bookIds = teacherBooks.map<int>((b) => b['id'] as int).toList();
        debugPrint("📚 Scoping to teacher $currentTeacherId — books: $bookIds");
      }

      // 4. Download lessons (scoped by teacher if selected)
      debugPrint("📥 Step 4: Downloading lessons for books $bookIds...");
      final List<dynamic> cloudLessons;
      if (bookIds.isNotEmpty) {
        cloudLessons = await supabase
            .from('lessons')
            .select()
            .inFilter('book_id', bookIds);
      } else {
        // No teacher selected — download all (first-time setup)
        cloudLessons = await supabase.from('lessons').select();
      }
      debugPrint("   Found ${cloudLessons.length} lessons");
      for (var l in cloudLessons) {
        debugPrint("   📝 Lesson: id=${l['id']} title=${l['title']} book_id=${l['book_id']}");
      }

      // Clean old lessons not in scope before inserting
      if (bookIds.isNotEmpty) {
        final placeholders = bookIds.map((_) => '?').join(',');
        await db.rawDelete(
          'DELETE FROM lessons WHERE book_id NOT IN ($placeholders)',
          bookIds,
        );
      }

      final lessonBatch = db.batch();
      for (var l in cloudLessons) {
        lessonBatch.insert('lessons', {
          'id': l['id'],
          'title': l['title'],
          'chapter_number': l['chapter_number'],
          'book_id': l['book_id']
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await lessonBatch.commit(noResult: true);
      debugPrint("   ✅ Saved ${cloudLessons.length} lessons to local DB");

      // 5. Download lesson_words FIRST (needed to know which word IDs to fetch)
      final localLessonIds = cloudLessons
          .map<int>((l) => l['id'] as int)
          .toList();

      debugPrint("📥 Step 5: Syncing lesson_words for ${localLessonIds.length} lessons: $localLessonIds");
      Set<int> neededWordIds = {};
      if (localLessonIds.isNotEmpty) {
        // Clear old lesson_words for these lessons
        final lwPlaceholders = localLessonIds.map((_) => '?').join(',');
        final deletedLW = await db.rawDelete(
          'DELETE FROM lesson_words WHERE lesson_id IN ($lwPlaceholders)',
          localLessonIds,
        );
        debugPrint("   🗑️ Cleared $deletedLW old lesson_words rows");

        // Download from Supabase with pagination (default limit is 1000!)
        int totalLW = 0;
        int pageStart = 0;
        const int pageLimit = 1000;
        bool moreLW = true;

        while (moreLW) {
          final cloudLW = await supabase
              .from('lesson_words')
              .select('lesson_id, word_id')
              .inFilter('lesson_id', localLessonIds)
              .range(pageStart, pageStart + pageLimit - 1);

          debugPrint("   ⬇️ Got ${cloudLW.length} lesson_words (page starting at $pageStart)");

          if (cloudLW.isNotEmpty) {
            final lwBatch = db.batch();
            for (var lw in cloudLW) {
              lwBatch.insert('lesson_words', {
                'lesson_id': lw['lesson_id'],
                'word_id': lw['word_id'],
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
              neededWordIds.add(lw['word_id'] as int);
            }
            await lwBatch.commit(noResult: true);
            totalLW += cloudLW.length;
          }

          if (cloudLW.length < pageLimit) {
            moreLW = false;
          } else {
            pageStart += pageLimit;
          }
        }
        debugPrint("   ✅ Synced $totalLW lesson_words — ${neededWordIds.length} unique word IDs needed");
      }

      // 6. Download words using word IDs from lesson_words (NOT words.lesson_id)
      //    After dedup, words.lesson_id may point to a different lesson than expected,
      //    so we must use lesson_words to know the correct word IDs.
      debugPrint("📥 Step 6: Downloading words (need ${neededWordIds.length} unique word IDs)");
      if (neededWordIds.isNotEmpty) {
        // Find which word IDs we're missing locally
        final existingWordIds = (await db.rawQuery(
          'SELECT id FROM words WHERE id IN (${neededWordIds.map((_) => '?').join(',')})',
          neededWordIds.toList(),
        )).map((r) => r['id'] as int).toSet();

        final missingWordIds = neededWordIds.difference(existingWordIds);
        debugPrint("   📊 ${existingWordIds.length} already cached, ${missingWordIds.length} missing");

        if (missingWordIds.isNotEmpty) {
          debugPrint("   📥 Downloading ${missingWordIds.length} missing words from Supabase...");

          // Download in batches by word ID
          final missingList = missingWordIds.toList();
          const int wordBatchSize = 50;
          for (var i = 0; i < missingList.length; i += wordBatchSize) {
            final end = (i + wordBatchSize < missingList.length) ? i + wordBatchSize : missingList.length;
            final batchWordIds = missingList.sublist(i, end);

            final cloudWords = await supabase
                .from('words')
                .select('id, lesson_id, es, en')
                .inFilter('id', batchWordIds);

            debugPrint("   ⬇️ Requested ${batchWordIds.length} words, got ${cloudWords.length} back");

            if (cloudWords.isNotEmpty) {
              final wordBatch = db.batch();
              for (var w in cloudWords) {
                wordBatch.insert('words', {
                  'id': w['id'],
                  'lesson_id': w['lesson_id'],
                  'es': w['es'],
                  'en': w['en']
                }, conflictAlgorithm: ConflictAlgorithm.replace);
              }
              await wordBatch.commit(noResult: true);
            }
          }
        } else {
          debugPrint("   ✅ All ${neededWordIds.length} words already cached locally");
        }

        // 7. Clean orphaned local words not referenced by any lesson_words
        final orphanedWords = await db.rawQuery('''
          SELECT w.id FROM words w
          WHERE w.id NOT IN (
            SELECT DISTINCT word_id FROM lesson_words
          )
        ''');
        if (orphanedWords.isNotEmpty) {
          final orphanIds = orphanedWords.map((r) => r['id'] as int).toList();
          debugPrint("🧹 Step 7: Deleting ${orphanIds.length} orphaned words not in lesson_words");
          final placeholders = orphanIds.map((_) => '?').join(',');
          await db.rawDelete('DELETE FROM words WHERE id IN ($placeholders)', orphanIds);
        } else {
          debugPrint("   ✅ Step 7: No orphaned words to clean");
        }

        // FINAL CHECK: count words in local DB
        final finalWordCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM words')) ?? 0;
        final finalLWCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM lesson_words')) ?? 0;
        debugPrint("📊 FINAL: $finalWordCount words, $finalLWCount lesson_words in local DB");
      } else if (localLessonIds.isNotEmpty) {
        debugPrint("   ⚠️ No lesson_words found in Supabase — lessons have no words!");
      }
    } catch (e) {
      debugPrint("❌ Content pull error: $e");
      rethrow;
    }
  }

  Future<void> _pullProgress(Database db, SupabaseClient supabase, String userId) async {
    try {
      final remoteProgress = await supabase
        .from('user_word_progress')
        .select()
        .eq('user_id', userId);

      if (remoteProgress.isNotEmpty) {
        debugPrint("📥 Downloading ${remoteProgress.length} progress records");
        // DEBUG: Log non-new statuses to see what Supabase sends
        for (var p in remoteProgress) {
          if (p['word_id'] == 1008 || (p['status'] != null && p['status'] != 'new')) {
            debugPrint("   🔍 PULL word_id=${p['word_id']} status=${p['status']} attempts=${p['total_attempts']} correct=${p['total_correct']}");
          }
        }
        final batch = db.batch();
        final List<Map<String, dynamic>> needsStatusFix = [];
        for (var p in remoteProgress) {
          String status = p['status'] ?? 'new';
          final int attempts = p['total_attempts'] ?? 0;

          // Auto-correct: status='new' but has attempts means data is inconsistent
          if (status == 'new' && attempts > 0) {
            status = 'learning';
            debugPrint("   🔧 AUTO-FIX word_id=${p['word_id']}: status was 'new' with $attempts attempts → set to 'learning'");
            needsStatusFix.add({
              'user_id': userId,
              'word_id': p['word_id'],
              'status': status,
              'strength': p['strength'] ?? 1.0,
              'consecutive_correct': p['consecutive_correct'] ?? 0,
              'next_due_at': p['next_due_at'],
              'last_reviewed': p['last_reviewed'],
              'total_attempts': attempts,
              'total_correct': p['total_correct'] ?? 0,
            });
          }

          batch.insert('user_progress', {
            'user_id': userId,
            'word_id': p['word_id'],
            'status': status,
            'strength': p['strength'] ?? 1.0,
            'last_reviewed': p['last_reviewed'],
            'next_due_at': p['next_due_at'],
            'consecutive_correct': p['consecutive_correct'] ?? 0,
            'total_attempts': attempts,
            'total_correct': p['total_correct'] ?? 0,
            'needs_sync': needsStatusFix.isNotEmpty && needsStatusFix.last['word_id'] == p['word_id'] ? 1 : 0
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);

        // Push auto-fixed statuses back to Supabase so it stays consistent
        if (needsStatusFix.isNotEmpty) {
          debugPrint("   🔧 Pushing ${needsStatusFix.length} auto-fixed statuses back to Supabase");
          await supabase.from('user_word_progress').upsert(
            needsStatusFix,
            onConflict: 'user_id, word_id'
          );
        }

        // DEBUG: Verify what was actually saved locally for word 1008
        final check1008 = await db.query('user_progress',
          where: 'word_id = ? AND user_id = ?',
          whereArgs: [1008, userId]);
        debugPrint("   🔍 LOCAL user_progress for word 1008: $check1008");
      }
    } catch (e) {
      debugPrint("❌ Progress pull error: $e");
      rethrow;
    }
  }

  /// Downloads daily_stats from cloud (much smaller than individual attempt logs)
  Future<void> _pullDailyStats(Database db, SupabaseClient supabase, String userId) async {
    try {
      // Download daily_stats for analytics (heatmap, charts, etc.)
      final cloudDailyStats = await supabase
        .from('daily_stats')
        .select()
        .eq('user_id', userId)
        .order('date', ascending: false);

      if (cloudDailyStats.isEmpty) {
        debugPrint("📊 No daily stats found in cloud");
        return;
      }

      debugPrint("📥 Downloading ${cloudDailyStats.length} days of stats");

      // Store in a local table for analytics (create if doesn't exist)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_stats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          date TEXT NOT NULL,
          total_words INTEGER DEFAULT 0,
          learned_count INTEGER DEFAULT 0,
          reviewing_count INTEGER DEFAULT 0,
          attempts_sum INTEGER DEFAULT 0,
          UNIQUE(user_id, date)
        )
      ''');

      final batch = db.batch();
      for (var stat in cloudDailyStats) {
        batch.insert('daily_stats', {
          'user_id': userId,
          'date': stat['date'],
          'total_words': stat['total_words'] ?? 0,
          'learned_count': stat['learned_count'] ?? 0,
          'reviewing_count': stat['reviewing_count'] ?? 0,
          'attempts_sum': stat['attempts_sum'] ?? 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);

      debugPrint("   ✅ Saved ${cloudDailyStats.length} daily stats locally");
    } catch (e) {
      debugPrint("❌ Daily stats pull error: $e");
      rethrow;
    }
  }

  // Update Progress (Called from Bubble page)
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
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      debugPrint("❌ Cannot save progress: No user logged in");
      return;
    }

    try {
      // Save progress
      await db.insert('user_progress', {
        'user_id': userId,
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

      // Log attempt
      await db.insert('attempt_logs', {
        'user_id': userId,
        'word_id': wordId,
        'correct': isCorrect ? 1 : 0,
        'attempted_at': DateTime.now().toUtc().toIso8601String(),
        'synced': 0
      }, conflictAlgorithm: ConflictAlgorithm.ignore);  // Ignore duplicates

    } catch (e) {
      debugPrint("❌ Failed to save progress: $e");
      rethrow;
    }
  }

  /// Get daily stats for heatmap calendar (last N days of activity)
  Future<Map<String, int>> getDailyActivityHeatmap({int days = 365}) async {
    final db = await instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) return {};

    try {
      final startDate = DateTime.now().subtract(Duration(days: days)).toIso8601String().split('T')[0];

      final results = await db.rawQuery('''
        SELECT date, attempts_sum
        FROM daily_stats
        WHERE user_id = ? AND date >= ?
        ORDER BY date ASC
      ''', [userId, startDate]);

      // Convert to Map<date, count> for heatmap (daily activity, not cumulative)
      Map<String, int> heatmap = {};
      for (var row in results) {
        heatmap[row['date'] as String] = row['attempts_sum'] as int;
      }

      return heatmap;
    } catch (e) {
      debugPrint("❌ Heatmap query error: $e");
      return {};
    }
  }

  /// Get historical learned vs reviewing counts for charts
  /// Excludes today since it's incomplete
  Future<List<Map<String, dynamic>>> getHistoricalStats({int days = 365}) async {
    final db = await instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) return [];

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startDate = today.subtract(Duration(days: days)).toIso8601String().split('T')[0];
      final todayStr = today.toIso8601String().split('T')[0];

      final results = await db.rawQuery('''
        SELECT date, learned_count, reviewing_count, total_words
        FROM daily_stats
        WHERE user_id = ? AND date >= ? AND date < ?
        ORDER BY date ASC
      ''', [userId, startDate, todayStr]);

      return results.map((row) => {
        'date': row['date'],
        'learned': row['learned_count'],
        'reviewing': row['reviewing_count'],
        'total': row['total_words'],
      }).toList();
    } catch (e) {
      debugPrint("❌ Historical stats query error: $e");
      return [];
    }
  }

  Future<List<LessonData>> getDashboardLessons() async {
    final db = await instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      debugPrint("❌ No user logged in");
      return [];
    }

    try {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);

      // Get current book selection (filter lessons by book)
      final currentBookId = await getCurrentBookId();

      // OPTIMIZED: Single query to get ALL lessons with their words and progress
      // Instead of N+1 queries (one per lesson), we now use 1 query for everything
      final String bookFilter = currentBookId != null ? 'AND l.book_id = ?' : '';
      final List<Object?> queryArgs = currentBookId != null
          ? [userId, currentBookId]
          : [userId];

      final allData = await db.rawQuery('''
        SELECT
          l.id as lesson_id,
          l.title,
          l.chapter_number,
          w.id as word_id,
          up.status,
          up.next_due_at
        FROM lessons l
        LEFT JOIN lesson_words lw ON lw.lesson_id = l.id
        LEFT JOIN words w ON w.id = lw.word_id
        LEFT JOIN user_progress up ON w.id = up.word_id AND up.user_id = ?
        WHERE 1=1 $bookFilter
        ORDER BY l.chapter_number ASC, w.id ASC
      ''', queryArgs);

      debugPrint("📚 Fetched ${allData.length} word records in single query");

      // Group by lesson and calculate stats in Dart using mutable counters
      Map<int, Map<String, dynamic>> lessonStats = {};

      for (var row in allData) {
        final lessonId = row['lesson_id'] as int;
        final title = row['title'] as String;
        final chapterNumber = row['chapter_number'] as int;
        final wordId = row['word_id']; // Can be null if lesson has no words

        // Initialize lesson stats if not seen yet
        if (!lessonStats.containsKey(lessonId)) {
          lessonStats[lessonId] = {
            'title': title,
            'chapter_number': chapterNumber,
            'learned': 0,
            'learning': 0,
            'unseen': 0,
            'forecast': List.filled(7, 0),
          };
        }

        // Skip if this lesson has no words (LEFT JOIN returned null word_id)
        if (wordId == null) continue;

        final stats = lessonStats[lessonId]!;
        String status = row['status'] as String? ?? 'new';
        String? nextDueStr = row['next_due_at'] as String?;

        // DEBUG: Log word 1008 and any non-new words
        if (wordId == 1008 || status != 'new') {
          debugPrint("   🔍 DASHBOARD lesson=$lessonId word=$wordId status=$status nextDue=$nextDueStr");
        }

        // Calculate learned/learning/unseen
        if (status == 'new') {
          stats['unseen']++;
        } else if (status == 'learning') {
          stats['learning']++;
        } else if (status == 'consolidating' || status == 'learned') {
          if (nextDueStr == null) {
            stats['learning']++;
          } else {
            try {
              DateTime dueDate = DateTime.parse(nextDueStr).toLocal();
              if (dueDate.isBefore(now) || dueDate.isAtSameMomentAs(now)) {
                stats['learning']++;
              } else {
                stats['learned']++;
              }
            } catch (e) {
              stats['learning']++;
            }
          }
        }

        // Forecast calculation
        if (nextDueStr != null) {
          try {
            DateTime due = DateTime.parse(nextDueStr).toLocal();
            int diffDays = DateTime(due.year, due.month, due.day).difference(todayMidnight).inDays;
            List<int> forecast = stats['forecast'] as List<int>;
            if (diffDays < 0) {
              forecast[0]++;
            } else if (diffDays < 7) {
              forecast[diffDays]++;
            }
          } catch (e) {
            // Skip invalid dates for forecast
          }
        }
      }

      // Convert mutable map to immutable LessonData list
      final results = lessonStats.entries.map((entry) {
        final id = entry.key;
        final stats = entry.value;
        return LessonData(
          id: id,
          title: stats['title'] as String,
          learned: stats['learned'] as int,
          learning: stats['learning'] as int,
          unseen: stats['unseen'] as int,
          chapter_number: stats['chapter_number'] as int,
          forecast: stats['forecast'] as List<int>,
        );
      }).toList();
      results.sort((a, b) => a.chapter_number.compareTo(b.chapter_number));

      debugPrint("📚 Processed ${results.length} lessons");
      return results;
    } catch (e) {
      debugPrint("❌ Dashboard query error: $e");
      return [];
    }
  }

  // =========================================================
  // 📚 BOOK MANAGEMENT (Multi-Teacher & Multi-Book Support)
  // =========================================================

  /// Get the currently selected teacher ID from local storage
  Future<int?> getCurrentTeacherId() async {
    final db = await database;
    try {
      final result = await db.query('app_meta',
        where: 'key = ?',
        whereArgs: ['current_teacher_id']
      );

      if (result.isEmpty) return null;

      final value = result.first['value'] as String?;
      return value != null ? int.tryParse(value) : null;
    } catch (e) {
      debugPrint("❌ Error getting current_teacher_id: $e");
      return null;
    }
  }

  /// Set the currently selected teacher ID in local storage
  Future<void> setCurrentTeacherId(int teacherId) async {
    final db = await database;
    try {
      await db.insert('app_meta',
        {'key': 'current_teacher_id', 'value': teacherId.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace
      );
      debugPrint("✅ Set current_teacher_id to $teacherId");
      notifyDataChanged(); // Trigger UI refresh
    } catch (e) {
      debugPrint("❌ Error setting current_teacher_id: $e");
    }
  }

  /// Get the currently selected book ID from local storage
  Future<int?> getCurrentBookId() async {
    final db = await database;
    try {
      final result = await db.query('app_meta',
        where: 'key = ?',
        whereArgs: ['current_book_id']
      );

      if (result.isEmpty) return null;

      final value = result.first['value'] as String?;
      return value != null ? int.tryParse(value) : null;
    } catch (e) {
      debugPrint("❌ Error getting current_book_id: $e");
      return null;
    }
  }

  /// Set the currently selected book ID in local storage
  Future<void> setCurrentBookId(int bookId) async {
    final db = await database;
    try {
      await db.insert('app_meta',
        {'key': 'current_book_id', 'value': bookId.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace
      );
      debugPrint("✅ Set current_book_id to $bookId");
      notifyDataChanged(); // Trigger UI refresh
    } catch (e) {
      debugPrint("❌ Error setting current_book_id: $e");
    }
  }

  /// Get the source language of the currently selected book ('es', 'en', etc.)
  Future<String> getBookSourceLanguage() async {
    final db = await database;
    try {
      final bookId = await getCurrentBookId();
      if (bookId == null) return 'es';
      final result = await db.query('books',
        columns: ['source_language'],
        where: 'id = ?',
        whereArgs: [bookId],
      );
      if (result.isEmpty) return 'es';
      return (result.first['source_language'] as String?) ?? 'es';
    } catch (e) {
      debugPrint("❌ Error getting book source language: $e");
      return 'es';
    }
  }

  /// Get the saved app language ('en' or 'el')
  Future<String?> getLanguage() async {
    final db = await database;
    try {
      final result = await db.query('app_meta',
        where: 'key = ?',
        whereArgs: ['app_language']
      );
      if (result.isEmpty) return null;
      return result.first['value'] as String?;
    } catch (e) {
      debugPrint("❌ Error getting app_language: $e");
      return null;
    }
  }

  /// Set the app language ('en' or 'el')
  Future<void> setLanguage(String locale) async {
    final db = await database;
    try {
      await db.insert('app_meta',
        {'key': 'app_language', 'value': locale},
        conflictAlgorithm: ConflictAlgorithm.replace
      );
      debugPrint("✅ Set app_language to $locale");
    } catch (e) {
      debugPrint("❌ Error setting app_language: $e");
    }
  }

  Future<String?> getDisplayName() async {
    final db = await database;
    try {
      final result = await db.query('app_meta',
        where: 'key = ?',
        whereArgs: ['display_name']
      );
      if (result.isEmpty) return null;
      return result.first['value'] as String?;
    } catch (e) {
      debugPrint("❌ Error getting display_name: $e");
      return null;
    }
  }

  Future<void> setDisplayName(String name) async {
    final db = await database;
    try {
      await db.insert('app_meta',
        {'key': 'display_name', 'value': name},
        conflictAlgorithm: ConflictAlgorithm.replace
      );
    } catch (e) {
      debugPrint("❌ Error setting display_name: $e");
    }
  }

  /// Get all available teachers
  Future<List<TeacherData>> getAllTeachers() async {
    final db = await database;
    try {
      final teachersQuery = await db.rawQuery('''
        SELECT
          t.id,
          t.name,
          t.description,
          COUNT(DISTINCT b.id) as book_count
        FROM teachers t
        LEFT JOIN books b ON b.teacher_id = t.id
        GROUP BY t.id, t.name, t.description
        ORDER BY t.id ASC
      ''');

      List<TeacherData> teachers = [];
      for (var row in teachersQuery) {
        teachers.add(TeacherData(
          id: row['id'] as int,
          name: row['name'] as String,
          description: row['description'] as String?,
          bookCount: row['book_count'] as int,
        ));
      }

      debugPrint("👨‍🏫 Found ${teachers.length} teachers");
      return teachers;
    } catch (e) {
      debugPrint("❌ Error fetching teachers: $e");
      return [];
    }
  }

  /// Get all available books (optionally filtered by teacher)
  Future<List<BookData>> getAllBooks({int? teacherId}) async {
    final db = await database;
    try {
      String whereClause = '';
      List<dynamic> whereArgs = [];

      if (teacherId != null) {
        whereClause = 'WHERE b.teacher_id = ?';
        whereArgs.add(teacherId);
      }

      final booksQuery = await db.rawQuery('''
        SELECT
          b.id,
          b.title,
          b.level,
          b.teacher_id,
          b.source_language,
          COUNT(l.id) as lesson_count
        FROM books b
        LEFT JOIN lessons l ON l.book_id = b.id
        $whereClause
        GROUP BY b.id, b.title, b.level, b.teacher_id, b.source_language
        ORDER BY b.id ASC
      ''', whereArgs);

      List<BookData> books = [];
      for (var row in booksQuery) {
        books.add(BookData(
          id: row['id'] as int,
          title: row['title'] as String,
          level: row['level'] as String?,
          teacherId: row['teacher_id'] as int?,
          lessonCount: row['lesson_count'] as int,
          sourceLanguage: (row['source_language'] as String?) ?? 'es',
        ));
      }

      debugPrint("📚 Found ${books.length} books${teacherId != null ? " for teacher $teacherId" : ""}");
      return books;
    } catch (e) {
      debugPrint("❌ Error fetching books: $e");
      return [];
    }
  }
}

class TeacherData {
  final int id;
  final String name;
  final String? description;
  final int bookCount;

  TeacherData({
    required this.id,
    required this.name,
    this.description,
    required this.bookCount,
  });
}

class BookData {
  final int id;
  final String title;
  final String? level;
  final int? teacherId;
  final int lessonCount;
  final String sourceLanguage;

  BookData({
    required this.id,
    required this.title,
    this.level,
    this.teacherId,
    required this.lessonCount,
    this.sourceLanguage = 'es',
  });
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
    required this.forecast
  });
}
