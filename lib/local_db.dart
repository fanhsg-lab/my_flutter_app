import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class LocalDB {
  static final LocalDB instance = LocalDB._init();
  static Database? _database;
  final ValueNotifier<int> onDatabaseChanged = ValueNotifier(0);

  void notifyDataChanged() {
    onDatabaseChanged.value++;
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
      version: 8,  // Version 8 adds user_progress_reverse for bidirectional tracking
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
        source_language TEXT DEFAULT 'es',
        total_lessons INTEGER DEFAULT 0
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

    await db.execute('''
      CREATE TABLE user_progress_reverse (
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

    // Indexes for performance
    await db.execute('CREATE INDEX idx_user_progress_user ON user_progress(user_id)');
    await db.execute('CREATE INDEX idx_user_progress_reverse_user ON user_progress_reverse(user_id)');
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

    if (oldVersion < 7) {
      debugPrint("🔧 Migrating database to v7 (adding total_lessons to books)");
      try {
        await db.execute('ALTER TABLE books ADD COLUMN total_lessons INTEGER DEFAULT 0');
        debugPrint("   ✅ Added total_lessons column to books");
      } catch (e) {
        debugPrint("   ⚠️ Error during v7 migration: $e");
      }
    }

    if (oldVersion < 8) {
      debugPrint("🔧 Migrating database to v8 (adding user_progress_reverse for bidirectional tracking)");
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_progress_reverse (
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
        await db.execute('CREATE INDEX IF NOT EXISTS idx_user_progress_reverse_user ON user_progress_reverse(user_id)');
        await db.insert('app_meta', {'key': 'word_direction', 'value': 'normal'},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        debugPrint("   ✅ Created user_progress_reverse table");
      } catch (e) {
        debugPrint("   ⚠️ Error during v8 migration: $e");
      }
    }
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  // =========================================================
  // 🔀 DIRECTION HELPERS
  // =========================================================

  /// existing table (user_progress) = GR→ES (isReversed=true)
  /// new table (user_progress_reverse) = ES→GR (isReversed=false)
  String _progressTable(bool isReversed) =>
      isReversed ? 'user_progress' : 'user_progress_reverse';

  String _supabaseProgressTable(bool isReversed) =>
      isReversed ? 'user_word_progress' : 'user_word_progress_reverse';

  Future<String> getWordDirection() async {
    final db = await database;
    final res = await db.query('app_meta', where: 'key = ?', whereArgs: ['word_direction']);
    return res.isNotEmpty ? res.first['value'] as String : 'reverse';
  }

  Future<void> setWordDirection(String direction) async {
    final db = await database;
    await db.insert('app_meta', {'key': 'word_direction', 'value': direction},
        conflictAlgorithm: ConflictAlgorithm.replace);
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

      // 3. DOWNLOAD GLOBAL CONTENT (only when content_version changes in Supabase)
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

      // Also re-pull if the selected teacher changed (lessons are teacher-scoped)
      final lastSyncedTeacher = (await db.query('app_meta', where: 'key = ?', whereArgs: ['last_synced_teacher']));
      final lastTeacherId = lastSyncedTeacher.isNotEmpty ? lastSyncedTeacher.first['value']?.toString() : null;
      final currentTeacherId = (await getCurrentTeacherId())?.toString();
      final teacherChanged = currentTeacherId != null && currentTeacherId != lastTeacherId;

      if (remoteVersion > localVersion || !hasLocalContent || teacherChanged) {
        debugPrint("📥 Content sync needed (local v$localVersion → remote v$remoteVersion, hasContent: $hasLocalContent, teacherChanged: $teacherChanged)");
        await _pullContent(db, supabase);
        await db.insert('app_meta',
          {'key': 'content_version', 'value': remoteVersion.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (currentTeacherId != null) {
          await db.insert('app_meta',
            {'key': 'last_synced_teacher', 'value': currentTeacherId},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 3.5 CLEAN UP orphaned progress (word_ids that no longer exist after dedup)
        // Only run on version change, NOT on teacher switch
        if (!teacherChanged) {
          for (final table in ['user_progress', 'user_progress_reverse']) {
            final orphaned = await db.rawQuery('''
              SELECT up.word_id FROM $table up
              LEFT JOIN words w ON w.id = up.word_id
              WHERE w.id IS NULL AND up.user_id = ?
            ''', [userId]);
            if (orphaned.isNotEmpty) {
              final orphanIds = orphaned.map((r) => r['word_id']).toList();
              debugPrint("🧹 Cleaning ${orphanIds.length} orphaned records from $table");
              final placeholders = orphanIds.map((_) => '?').join(',');
              await db.rawDelete(
                'DELETE FROM $table WHERE word_id IN ($placeholders) AND user_id = ?',
                [...orphanIds, userId],
              );
            }
          }
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
    debugPrint('🔄 syncProgress started for user=$userId');
    final db = await instance.database;
    final supabase = Supabase.instance.client;

    // Check local attempt_logs before push
    final localLogs = await db.rawQuery(
      'SELECT COUNT(*) as total, SUM(CASE WHEN synced=0 THEN 1 ELSE 0 END) as unsynced FROM attempt_logs WHERE user_id=?',
      [userId]
    );
    debugPrint('📋 attempt_logs: total=${localLogs.first['total']}, unsynced=${localLogs.first['unsynced']}');

    await _pushPendingData(db, supabase, userId);
    debugPrint('✅ _pushPendingData done');

    await _pullDailyStats(db, supabase, userId);

    // Check local daily_stats after pull
    final localStats = await db.rawQuery(
      'SELECT date, attempts_sum FROM daily_stats WHERE user_id=? ORDER BY date DESC LIMIT 5',
      [userId]
    );
    debugPrint('📊 local daily_stats after pull:');
    for (var row in localStats) {
      debugPrint('   ${row['date']} → attempts=${row['attempts_sum']}');
    }
  }

  Future<void> _pushPendingData(Database db, SupabaseClient supabase, String userId) async {
    try {
      // Upload progress for both directions
      for (final isReversed in [false, true]) {
        final localTable = _progressTable(isReversed);
        final supaTable = _supabaseProgressTable(isReversed);

        final unsyncedProgress = await db.rawQuery('''
          SELECT up.* FROM $localTable up
          INNER JOIN words w ON w.id = up.word_id
          WHERE up.user_id = ? AND up.needs_sync = 1
        ''', [userId]);

        if (unsyncedProgress.isNotEmpty) {
          debugPrint("☁️ Uploading ${unsyncedProgress.length} ${isReversed ? 'reverse' : 'normal'} progress records...");

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

            await supabase.from(supaTable).upsert(
              progressPayload,
              onConflict: 'user_id, word_id'
            );
          }

          await db.update(
            localTable,
            {'needs_sync': 0},
            where: 'user_id = ? AND needs_sync = 1',
            whereArgs: [userId]
          );
        }
      }

      // Aggregate attempt logs into daily_stats
      await _aggregateAndSyncDailyStats(db, supabase, userId);

    } catch (e) {
      debugPrint("❌ Push error: $e");
      rethrow;
    }
  }

  /// Snapshots current progress + aggregates attempt logs into daily_stats
  Future<void> _aggregateAndSyncDailyStats(Database db, SupabaseClient supabase, String userId) async {
    try {
      // 1. Count today's attempts from unsynced logs
      final unsyncedLogs = await db.rawQuery('''
        SELECT
          DATE(attempted_at) as date,
          COUNT(*) as total_attempts
        FROM attempt_logs
        WHERE user_id = ? AND DATE(attempted_at) IN (
          SELECT DISTINCT DATE(attempted_at) FROM attempt_logs WHERE user_id = ? AND synced = 0
        )
        GROUP BY DATE(attempted_at)
      ''', [userId, userId]);

      // 2. Snapshot current user_progress state:
      //    learned = consolidating/learned with next_due_at in the future (not due)
      //    reviewing = learning status OR consolidating/learned with next_due_at past/now/null
      final now = DateTime.now().toIso8601String();
      final progressSnapshot = await db.rawQuery('''
        SELECT
          SUM(CASE
            WHEN (status = 'consolidating' OR status = 'learned')
              AND next_due_at IS NOT NULL AND next_due_at > ?
            THEN 1 ELSE 0
          END) as learned_count,
          SUM(CASE
            WHEN status = 'learning'
              OR ((status = 'consolidating' OR status = 'learned')
                  AND (next_due_at IS NULL OR next_due_at <= ?))
            THEN 1 ELSE 0
          END) as reviewing_count
        FROM user_progress
        WHERE user_id = ? AND status != 'new'
      ''', [now, now, userId]);

      final learned = (progressSnapshot.first['learned_count'] as int?) ?? 0;
      final reviewing = (progressSnapshot.first['reviewing_count'] as int?) ?? 0;
      final totalWords = learned + reviewing;

      debugPrint("📊 Progress snapshot: learned=$learned, reviewing=$reviewing, total=$totalWords");

      // 3. Build payload — always sync today's snapshot even if no new attempts
      final today = DateTime.now();
      final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      // Map attempt counts by date
      Map<String, int> attemptsByDate = {};
      for (var log in unsyncedLogs) {
        attemptsByDate[log['date'] as String] = (log['total_attempts'] as int?) ?? 0;
      }

      // Ensure today is always included (for the progress snapshot)
      if (!attemptsByDate.containsKey(todayStr)) {
        attemptsByDate[todayStr] = 0;
      }

      // Today: upsert progress snapshot. Only include attempts_sum if we have new unsynced logs.
      final hasTodayUnsynced = attemptsByDate.containsKey(todayStr) && (attemptsByDate[todayStr] ?? 0) > 0;
      final todayPayload = <String, dynamic>{
        'user_id': userId,
        'date': todayStr,
        'total_words': totalWords,
        'learned_count': learned,
        'reviewing_count': reviewing,
      };
      if (hasTodayUnsynced) todayPayload['attempts_sum'] = attemptsByDate[todayStr];
      debugPrint('📤 Upserting daily_stats for today=$todayStr hasTodayUnsynced=$hasTodayUnsynced learned=$learned reviewing=$reviewing');
      await supabase.from('daily_stats').upsert(todayPayload, onConflict: 'user_id, date');
      debugPrint('✅ daily_stats upsert done');

      // Past dates: only update attempts_sum — never overwrite learned/reviewing
      final pastDates = attemptsByDate.entries.where((e) => e.key != todayStr).toList();
      for (var entry in pastDates) {
        await supabase.rpc('upsert_attempts_only', params: {
          'p_user_id': userId,
          'p_date': entry.key,
          'p_attempts': entry.value,
        });
      }
      debugPrint("   ✅ Synced daily_stats: today + ${pastDates.length} past dates (attempts only)");

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
      final cloudBooks = await supabase.from('books').select('*, lessons(count)');
      debugPrint("   Found ${cloudBooks.length} books in cloud");
      for (var b in cloudBooks) {
        debugPrint("   📖 Book: id=${b['id']} title=${b['title']} teacher_id=${b['teacher_id']}");
      }

      final bookBatch = db.batch();
      for (var b in cloudBooks) {
        final lessonCount = (b['lessons'] is List && (b['lessons'] as List).isNotEmpty)
            ? (b['lessons'] as List).first['count'] as int? ?? 0
            : 0;
        bookBatch.insert('books', {
          'id': b['id'],
          'title': b['title'],
          'level': b['level'],
          'teacher_id': b['teacher_id'],
          'source_language': b['source_language'] ?? 'es',
          'total_lessons': lessonCount,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint("   Committing books batch...");
      await bookBatch.commit(noResult: true);
      debugPrint("   ✅ Saved ${cloudBooks.length} books to local DB");

      // 3. Determine scope: current teacher's books only
      debugPrint("📥 Step 3: Getting current teacher...");
      var currentTeacherId = await getCurrentTeacherId();

      // Auto-select first teacher if none selected (first install)
      if (currentTeacherId == null && cloudTeachers.isNotEmpty) {
        currentTeacherId = cloudTeachers.first['id'] as int;
        await setCurrentTeacherId(currentTeacherId);
        // Also auto-select first book for this teacher
        final firstTeacherBooks = cloudBooks
            .where((b) => b['teacher_id'] == currentTeacherId)
            .toList();
        if (firstTeacherBooks.isNotEmpty) {
          await setCurrentBookId(firstTeacherBooks.first['id'] as int);
        }
        debugPrint("👨‍🏫 Auto-selected teacher $currentTeacherId on first install");
      }

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
        // Find which word IDs we're missing locally (chunked to avoid SQLite 999 variable limit)
        final existingWordIds = <int>{};
        final allNeeded = neededWordIds.toList();
        const int chunkSize = 500;
        for (var i = 0; i < allNeeded.length; i += chunkSize) {
          final chunk = allNeeded.sublist(i, (i + chunkSize < allNeeded.length) ? i + chunkSize : allNeeded.length);
          final rows = await db.rawQuery(
            'SELECT id FROM words WHERE id IN (${chunk.map((_) => '?').join(',')})',
            chunk,
          );
          existingWordIds.addAll(rows.map((r) => r['id'] as int));
        }

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
      // Pull both directions
      for (final isReversed in [false, true]) {
        final localTable = _progressTable(isReversed);
        final supaTable = _supabaseProgressTable(isReversed);

        List<dynamic> remoteProgress = [];
        int pageStart = 0;
        const int pageLimit = 1000;
        bool more = true;

        while (more) {
          final page = await supabase
            .from(supaTable)
            .select()
            .eq('user_id', userId)
            .range(pageStart, pageStart + pageLimit - 1);
          remoteProgress.addAll(page);
          if (page.length < pageLimit) {
            more = false;
          } else {
            pageStart += pageLimit;
          }
        }

        if (remoteProgress.isNotEmpty) {
          debugPrint("📥 Downloading ${remoteProgress.length} ${isReversed ? 'reverse' : 'normal'} progress records");
          final batch = db.batch();
          final List<Map<String, dynamic>> needsStatusFix = [];
          for (var p in remoteProgress) {
            String status = p['status'] ?? 'new';
            final int attempts = p['total_attempts'] ?? 0;

            if (status == 'new' && attempts > 0) {
              status = 'learning';
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

            batch.insert(localTable, {
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

          if (needsStatusFix.isNotEmpty) {
            debugPrint("   🔧 Pushing ${needsStatusFix.length} auto-fixed statuses back to $supaTable");
            await supabase.from(supaTable).upsert(
              needsStatusFix,
              onConflict: 'user_id, word_id'
            );
          }
        }
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

      // Clear local daily_stats for this user so deleted cloud rows don't linger
      await db.delete('daily_stats', where: 'user_id = ?', whereArgs: [userId]);

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
    required bool isCorrect,
    bool isReversed = false,
  }) async {
    final db = await instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      debugPrint("❌ Cannot save progress: No user logged in");
      return;
    }

    final table = _progressTable(isReversed);

    try {
      // Save progress to correct directional table
      await db.insert(table, {
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

      // Log attempt (shared — direction-agnostic)
      await db.insert('attempt_logs', {
        'user_id': userId,
        'word_id': wordId,
        'correct': isCorrect ? 1 : 0,
        'attempted_at': DateTime.now().toUtc().toIso8601String(),
        'synced': 0
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

    } catch (e) {
      debugPrint("❌ Failed to save progress: $e");
      rethrow;
    }
  }

  /// Get current streak count (for notifications)
  Future<int> getStreakCount() async {
    try {
      final db = await instance.database;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return 0;

      final result = await db.query(
        'daily_stats',
        columns: ['date'],
        where: 'user_id = ? AND attempts_sum > 0',
        whereArgs: [userId],
        orderBy: 'date DESC',
      );
      if (result.isEmpty) return 0;

      List<String> sortedDates = result.map((r) => r['date'] as String).toList();
      DateTime now = DateTime.now();
      String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      DateTime yest = now.subtract(const Duration(days: 1));
      String yesterdayStr = "${yest.year}-${yest.month.toString().padLeft(2, '0')}-${yest.day.toString().padLeft(2, '0')}";

      String lastPlayed = sortedDates.first;
      int streak = 0;
      String? nextDateToFind;

      if (lastPlayed == todayStr) {
        streak = 1;
        nextDateToFind = yesterdayStr;
      } else if (lastPlayed == yesterdayStr) {
        streak = 1;
        DateTime dby = now.subtract(const Duration(days: 2));
        nextDateToFind = "${dby.year}-${dby.month.toString().padLeft(2, '0')}-${dby.day.toString().padLeft(2, '0')}";
      } else {
        return 0;
      }

      if (streak > 0) {
        for (int i = 1; i < sortedDates.length; i++) {
          if (sortedDates[i] == nextDateToFind) {
            streak++;
            DateTime prev = DateTime.parse(nextDateToFind!).subtract(const Duration(days: 1));
            nextDateToFind = "${prev.year}-${prev.month.toString().padLeft(2, '0')}-${prev.day.toString().padLeft(2, '0')}";
          } else {
            break;
          }
        }
      }
      return streak;
    } catch (e) {
      return 0;
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

  Future<List<LessonData>> getDashboardLessons({bool isReversed = false}) async {
    final db = await instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      debugPrint("❌ No user logged in");
      return [];
    }

    final progressTable = _progressTable(isReversed);

    try {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);

      // Get current book selection (filter lessons by book)
      final currentBookId = await getCurrentBookId();

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
        LEFT JOIN $progressTable up ON w.id = up.word_id AND up.user_id = ?
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

  Future<int?> getCurrentLessonIndex() async {
    final db = await database;
    try {
      final result = await db.query('app_meta', where: 'key = ?', whereArgs: ['current_lesson_index']);
      if (result.isEmpty) return null;
      final value = result.first['value'] as String?;
      return value != null ? int.tryParse(value) : null;
    } catch (e) {
      return null;
    }
  }

  Future<void> setCurrentLessonIndex(int index) async {
    final db = await database;
    try {
      await db.insert('app_meta',
        {'key': 'current_lesson_index', 'value': index.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace
      );
    } catch (e) {
      debugPrint("❌ Error setting current_lesson_index: $e");
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
      // Try fetching from Supabase first
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final res = await Supabase.instance.client
            .from('profiles')
            .select('display_name')
            .eq('id', userId)
            .maybeSingle();
        final remote = res?['display_name'] as String?;
        if (remote != null && remote.isNotEmpty) {
          // Cache locally
          await db.insert('app_meta', {'key': 'display_name', 'value': remote},
              conflictAlgorithm: ConflictAlgorithm.replace);
          return remote;
        }
      }
      // Fall back to local cache
      final result = await db.query('app_meta',
        where: 'key = ?',
        whereArgs: ['display_name']
      );
      if (result.isEmpty) return null;
      return result.first['value'] as String?;
    } catch (e) {
      debugPrint("❌ Error getting display_name: $e");
      // Fall back to local cache on error
      try {
        final db2 = await database;
        final result = await db2.query('app_meta',
          where: 'key = ?',
          whereArgs: ['display_name']
        );
        if (result.isEmpty) return null;
        return result.first['value'] as String?;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> setDisplayName(String name) async {
    final db = await database;
    try {
      // Save locally
      await db.insert('app_meta',
        {'key': 'display_name', 'value': name},
        conflictAlgorithm: ConflictAlgorithm.replace
      );
      // Sync to Supabase
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client
            .from('profiles')
            .upsert({'id': userId, 'display_name': name});
      }
    } catch (e) {
      debugPrint("❌ Error setting display_name: $e");
    }
  }

  // =========================================================
  // 💳 SUBSCRIPTION CACHE (offline access)
  // =========================================================

  /// Ensures trial_started_at is set locally and synced to Supabase.
  /// Call once after the user is authenticated.
  Future<void> ensureTrialStarted() async {
    final db = await database;

    // 1. Get or set local trial start date
    final localRes = await db.query('app_meta', where: 'key = ?', whereArgs: ['trial_started_at']);
    String localDate;
    if (localRes.isEmpty) {
      localDate = DateTime.now().toUtc().toIso8601String();
      await db.insert('app_meta', {'key': 'trial_started_at', 'value': localDate},
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      localDate = localRes.first['value'] as String;
    }

    // 2. Sync to Supabase profiles — only if Supabase value is null or local is earlier
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('trial_started_at')
          .eq('id', userId)
          .maybeSingle();

      final remoteDate = profileRes?['trial_started_at'] as String?;
      final localDt = DateTime.parse(localDate);
      final remoteDt = remoteDate != null ? DateTime.tryParse(remoteDate) : null;

      // Use whichever is earlier (handles reinstalls correctly)
      final useDate = (remoteDt != null && remoteDt.isBefore(localDt)) ? remoteDate! : localDate;

      if (remoteDate == null || remoteDate != useDate) {
        await Supabase.instance.client
            .from('profiles')
            .upsert({'id': userId, 'trial_started_at': useDate});
        // Also update local if remote was earlier
        if (useDate != localDate) {
          await db.insert('app_meta', {'key': 'trial_started_at', 'value': useDate},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    } catch (e) {
      debugPrint("⚠️ ensureTrialStarted sync error: $e");
    }
  }

  /// Get cached subscription state (for offline access)
  Future<Map<String, String?>> getSubscriptionCache() async {
    final db = await database;
    try {
      final keys = ['sub_access_level', 'sub_trial_days_left', 'sub_expires_at'];
      final result = await db.query('app_meta',
        where: 'key IN (?, ?, ?)',
        whereArgs: keys,
      );
      final map = <String, String?>{};
      for (var row in result) {
        map[row['key'] as String] = row['value'] as String?;
      }
      return map;
    } catch (e) {
      debugPrint("❌ Error reading subscription cache: $e");
      return {};
    }
  }

  /// Save subscription state to local cache
  Future<void> setSubscriptionCache({
    required String accessLevel,
    required int trialDaysLeft,
    String? expiresAt,
  }) async {
    final db = await database;
    try {
      final batch = db.batch();
      batch.insert('app_meta',
        {'key': 'sub_access_level', 'value': accessLevel},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.insert('app_meta',
        {'key': 'sub_trial_days_left', 'value': trialDaysLeft.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.insert('app_meta',
        {'key': 'sub_expires_at', 'value': expiresAt ?? ''},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint("❌ Error saving subscription cache: $e");
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
          b.total_lessons,
          COUNT(l.id) as lesson_count
        FROM books b
        LEFT JOIN lessons l ON l.book_id = b.id
        $whereClause
        GROUP BY b.id, b.title, b.level, b.teacher_id, b.source_language, b.total_lessons
        ORDER BY b.id ASC
      ''', whereArgs);

      List<BookData> books = [];
      for (var row in booksQuery) {
        final localCount = row['lesson_count'] as int;
        final cloudCount = row['total_lessons'] as int? ?? 0;
        books.add(BookData(
          id: row['id'] as int,
          title: row['title'] as String,
          level: row['level'] as String?,
          teacherId: row['teacher_id'] as int?,
          lessonCount: localCount > 0 ? localCount : cloudCount,
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

  Future<void> clearAllLocalData() async {
    final db = await database;
    await db.delete('user_progress');
    await db.delete('user_progress_reverse');
    await db.delete('daily_stats');
    await db.delete('attempt_logs');
    await db.delete('app_meta');
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
