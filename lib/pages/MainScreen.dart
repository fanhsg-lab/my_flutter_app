import 'dart:math' as math;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heroicons/heroicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../local_db.dart';
import '../responsive.dart';
import '../services/app_strings.dart';
import 'gameMode.dart';
import 'bubble.dart';
import 'survival_mode.dart';
import 'statistics.dart';
import 'profile.dart';
import 'package:sqflite/sqflite.dart';
import 'package:fl_chart/fl_chart.dart'; // Needed for the Bar Chart
import '../services/subscription_service.dart';
import 'paywall.dart';

class MainScreen extends StatefulWidget {
  final VoidCallback? onReady;
  const MainScreen({super.key, this.onReady});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _streak = 0;
  int _totalLearnedWords = 0;
  int _currentLessonIndex = 0;
  String _selectedMode = 'Test';
  String _sourceLanguage = 'es';
  String _selectedLanguage = 'Gr -> Esp';
  String _bookTitle = '';
  String _bookLevel = '';
  int _bottomNavIndex = 0;
  bool _isLoading = false;
  bool _initialLoadDone = false;
  List<LessonData> _lessons = [];

  PageController? _lessonPageController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initialLoad();
  }

  @override
  void dispose() {
    _lessonPageController?.dispose();
    super.dispose();
  }

  void _navigateToTab(int index) {
    if (index == _bottomNavIndex) return;
    setState(() => _bottomNavIndex = index);
    if (index == 0 && _lessonPageController != null && _lessonPageController!.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_lessonPageController!.hasClients) {
          _lessonPageController!.jumpToPage(_currentLessonIndex);
        }
      });
    }
  }

  Future<void> _initialLoad() async {
    // Read local data only → signal onReady so splash can fade
    await _autoSelectTeacherAndBook();
    if (!mounted) return;
    // Initialize subscription state (cached first, then server refresh)
    await SubscriptionService.instance.initialize();
    if (!mounted) return;
    await _fetchDashboardData();
    if (!mounted) return;
    await _calculateStreakAndStats();

    if (_lessons.isEmpty) {
      // First use — no local data, sync immediately and show loader
      if (mounted) setState(() => _isLoading = true);
      try {
        await LocalDB.instance.syncEverything();
      } catch (e) {
        debugPrint("⚠️ First Sync Error: $e");
      }
      if (!mounted) return;

      // Always force-select teacher/book from local DB after first sync
      // (sync may set app_meta but getAllBooks() is the source of truth for what's available)
      await _autoSelectTeacherAndBook(force: true);
      if (!mounted) return;

      final bookAfterSync = await LocalDB.instance.getCurrentBookId();
      debugPrint("🔍 First install: bookId after sync=$bookAfterSync, mounted=$mounted");

      await _fetchDashboardData();
      debugPrint("🔍 First install: lessons after fetchDashboardData=${_lessons.length}");
      await _calculateStreakAndStats();

      if (_lessons.isEmpty) {
        debugPrint("⚠️ No lessons after sync — user may need to refresh");
      }
    } else {
      // Has local data — sync later after splash is fully gone
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (!mounted) return;
        LocalDB.instance.syncEverything().then((_) async {
          debugPrint("✅ Background Sync Complete. Refreshing UI.");
          await _autoSelectTeacherAndBook();
          if (mounted) {
            _fetchDashboardData();
            _calculateStreakAndStats();
          }
        }).catchError((e) {
          debugPrint("⚠️ Background Sync Error: $e");
        });
      });
    }
  }

  Future<void> _autoSelectTeacherAndBook({bool force = false}) async {
    final currentTeacher = await LocalDB.instance.getCurrentTeacherId();
    final currentBook = await LocalDB.instance.getCurrentBookId();

    if (force || currentTeacher == null || currentBook == null) {
      final teachers = await LocalDB.instance.getAllTeachers();
      if (teachers.isNotEmpty) {
        final firstTeacher = teachers.first;
        await LocalDB.instance.setCurrentTeacherId(firstTeacher.id);

        final books = await LocalDB.instance.getAllBooks(teacherId: firstTeacher.id);
        if (books.isNotEmpty) {
          await LocalDB.instance.setCurrentBookId(books.first.id);
          debugPrint("👨‍🏫 Auto-selected Teacher ${firstTeacher.id} and Book ${books.first.id}");
        }
      }
    }
  }

  Future<void> _fetchDashboardData() async {
    try {
      final savedDirection = await LocalDB.instance.getWordDirection();
      final isReversed = savedDirection == 'reverse';
      final data = await LocalDB.instance.getDashboardLessons(isReversed: isReversed);
      final srcLang = await LocalDB.instance.getBookSourceLanguage();
      final bookId = await LocalDB.instance.getCurrentBookId();
      String bookTitle = '';
      String bookLevel = '';
      if (bookId != null) {
        final db = await LocalDB.instance.database;
        final rows = await db.query('books', where: 'id = ?', whereArgs: [bookId]);
        if (rows.isNotEmpty) {
          bookTitle = rows.first['title'] as String? ?? '';
          bookLevel = rows.first['level'] as String? ?? '';
        }
      }
      if (mounted) {
        final shortLabel = S.sourceLanguageShort(srcLang);
        final directionLabel = isReversed
            ? 'Gr -> $shortLabel'
            : '$shortLabel -> Gr';
        final savedLessonIndex = await LocalDB.instance.getCurrentLessonIndex();
        final restoredIndex = (savedLessonIndex != null && savedLessonIndex < data.length)
            ? savedLessonIndex : 0;
        setState(() {
          _lessons = data;
          if (!_initialLoadDone || srcLang != _sourceLanguage) _selectedLanguage = directionLabel;
          _sourceLanguage = srcLang;
          _bookTitle = bookTitle;
          _bookLevel = bookLevel;
          _isLoading = false;
          if (!_initialLoadDone) {
            _currentLessonIndex = restoredIndex;
            _initialLoadDone = true;
            widget.onReady?.call();
          }
        });
        if (restoredIndex > 0 && _lessonPageController != null && _lessonPageController!.hasClients) {
          _lessonPageController!.jumpToPage(restoredIndex);
        }
      }
    } catch (e) {
      debugPrint("⚠️ UI Read Error: $e");
    }
  }

  // 🔥 NEW: Calculate Streak AND Total Learned Words locally
  // 🔥 FIX: Calculates CONSECUTIVE days, not total days
  // 🔥 FIX: Uses daily_stats (synced from cloud) instead of attempt_logs (local only)
  Future<void> _calculateStreakAndStats() async {
    try {
      final db = await LocalDB.instance.database;
      final userId = Supabase.instance.client.auth.currentUser?.id;

      if (userId == null) {
        if (mounted) setState(() => _streak = 0);
        return;
      }

      // --- 1. GET ALL ACTIVE DAYS FROM SYNCED daily_stats ---
      final result = await db.query(
        'daily_stats',
        columns: ['date'],
        where: 'user_id = ? AND attempts_sum > 0',
        whereArgs: [userId],
        orderBy: 'date DESC',
      );

      if (result.isEmpty) {
        debugPrint("❌ No activity found in daily_stats for streak.");
        if (mounted) setState(() => _streak = 0);
        return;
      }

      // --- 2. GET SORTED DATES (Already in YYYY-MM-DD format) ---
      List<String> sortedDates = result.map((row) => row['date'] as String).toList();

      debugPrint("📅 Found ${sortedDates.length} active days.");
      debugPrint("📅 Most Recent Play: ${sortedDates.first}");

      // --- 3. CALCULATE STREAK ---
      int streak = 0;
      DateTime now = DateTime.now();

      // Strings for Today and Yesterday
      String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      DateTime yest = now.subtract(const Duration(days: 1));
      String yesterdayStr = "${yest.year}-${yest.month.toString().padLeft(2, '0')}-${yest.day.toString().padLeft(2, '0')}";

      String lastPlayed = sortedDates.first;

      // Step A: Check if Streak is ALIVE
      // To keep a streak, you must have played Today OR Yesterday.
      String? nextDateToFind;

      if (lastPlayed == todayStr) {
        streak = 1;
        nextDateToFind = yesterdayStr; // If played today, next we look for yesterday
      } else if (lastPlayed == yesterdayStr) {
        streak = 1;
        // If played yesterday (but not today), streak is 1. Next we look for day before yesterday.
        DateTime dby = now.subtract(const Duration(days: 2));
        nextDateToFind = "${dby.year}-${dby.month.toString().padLeft(2, '0')}-${dby.day.toString().padLeft(2, '0')}";
      } else {
        // If last played was 2+ days ago, Streak is broken.
        debugPrint("💔 Streak broken. Last played: $lastPlayed, Today: $todayStr");
        streak = 0;
      }

      // Step B: Count Backwards if streak is alive
      if (streak > 0) {
        // Skip the first date (we already counted it)
        for (int i = 1; i < sortedDates.length; i++) {
          if (sortedDates[i] == nextDateToFind) {
            streak++;
            // Calculate the NEXT previous day
            DateTime prev = DateTime.parse(nextDateToFind!).subtract(const Duration(days: 1));
            nextDateToFind = "${prev.year}-${prev.month.toString().padLeft(2, '0')}-${prev.day.toString().padLeft(2, '0')}";
          } else {
             // Gap found! Stop counting.
             break;
          }
        }
      }

      debugPrint("🔥 Final Streak Calculation: $streak");

      // --- 4. STATS (Words Learned) ---
      final direction = await LocalDB.instance.getWordDirection();
      final progressTable = direction == 'reverse' ? 'user_progress' : 'user_progress_reverse';

      // Filter by current book's lessons only
      final lessonIds = _lessons.map((l) => l.id).toList();
      int learnedCount = 0;
      if (lessonIds.isNotEmpty) {
        final placeholders = lessonIds.map((_) => '?').join(',');
        final learnedRes = await db.rawQuery('''
          SELECT COUNT(DISTINCT p.word_id) FROM $progressTable p
          JOIN lesson_words lw ON lw.word_id = p.word_id
          WHERE p.user_id = ? AND p.status IN ('learned', 'consolidating')
          AND lw.lesson_id IN ($placeholders)
        ''', [userId, ...lessonIds]);
        learnedCount = Sqflite.firstIntValue(learnedRes) ?? 0;
      }

      if (mounted) {
        setState(() {
          _streak = streak;
          _totalLearnedWords = learnedCount;
        });
      }
    } catch (e) {
      debugPrint("⚠️ Streak Calculation Error: $e");
    }
  }

  void _showStreakDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(S.quickStats, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPopupStat(S.dayStreak, "$_streak", Colors.orange, HeroIcon(HeroIcons.fire, style: HeroIconStyle.solid, size: 32, color: Colors.orange)),
                    Container(width: 1, height: 50, color: Colors.grey.shade800),
                    _buildPopupStat(S.wordsLearned, "$_totalLearnedWords", AppColors.success, HeroIcon(HeroIcons.academicCap, style: HeroIconStyle.solid, size: 32, color: AppColors.success)),
                  ],
                ),
                const SizedBox(height: 24),
                Text(S.keepGoing, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
        );
      }
    );
  }

  void _showProgressInfo() {
    final isEl = S.locale == 'el';
    final base = TextStyle(color: Colors.grey.shade300, fontSize: 14, height: 1.75);
    const orange = TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold);
    final greyBold = TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold);
    const white = TextStyle(color: Colors.white, fontWeight: FontWeight.bold);

    const accent = TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold);

    final Widget content = isEl
        ? RichText(text: TextSpan(style: base, children: [
            TextSpan(text: '⚠️  Μόνο το ', style: base),
            TextSpan(text: 'Test mode', style: orange),
            TextSpan(text: ' μετράει για την πρόοδο και τα στατιστικά σου. Το Game και το Survival δεν αλλάζουν την κατάσταση των λέξεων.\n\n', style: base),

            TextSpan(text: 'Κατάσταση λέξεων:\n', style: white),
            TextSpan(text: '●  ', style: greyBold),
            TextSpan(text: 'Νέα', style: greyBold),
            TextSpan(text: '  —  δεν έχει δοκιμαστεί ακόμα στο Test\n', style: base),
            TextSpan(text: '●  ', style: accent),
            TextSpan(text: 'Σε εκμάθηση', style: accent),
            TextSpan(text: '  —  ενεργά σε δοκιμασία, δεν έχει κατακτηθεί ακόμα\n', style: base),
            TextSpan(text: '●  ', style: orange),
            TextSpan(text: 'Εκμαθημένη', style: orange),
            TextSpan(text: '  —  καλά εδραιωμένη, δεν χρειάζεται επανάληψη αυτή τη στιγμή\n\n', style: base),

            TextSpan(text: 'Η καμπύλη λήθης:\n', style: white),
            TextSpan(text: 'Μόλις μια λέξη γίνει ', style: base),
            TextSpan(text: 'Εκμαθημένη', style: orange),
            TextSpan(text: ', ο αλγόριθμος την προγραμματίζει για μελλοντική επανάληψη. ⏳ Με τον χρόνο, υποθέτει ότι θα την ξεχάσεις — και την επαναφέρει αυτόματα στη ', style: base),
            TextSpan(text: '🔄 δεξαμενή εκμάθησης', style: accent),
            TextSpan(text: '. Όσες περισσότερες φορές την ανακαλέσεις σωστά, τόσο αργότερα θα επιστρέψει.', style: base),
          ]))
        : RichText(text: TextSpan(style: base, children: [
            TextSpan(text: '⚠️  Only ', style: base),
            TextSpan(text: 'Test mode', style: orange),
            TextSpan(text: ' counts toward your progress and statistics. Game and Survival do not change word status.\n\n', style: base),

            TextSpan(text: 'Word states:\n', style: white),
            TextSpan(text: '●  ', style: greyBold),
            TextSpan(text: 'New', style: greyBold),
            TextSpan(text: '  —  not tested yet in Test mode\n', style: base),
            TextSpan(text: '●  ', style: accent),
            TextSpan(text: 'Learning', style: accent),
            TextSpan(text: '  —  actively being tested, not yet mastered\n', style: base),
            TextSpan(text: '●  ', style: orange),
            TextSpan(text: 'Mastered', style: orange),
            TextSpan(text: '  —  well established, no review needed right now\n\n', style: base),

            TextSpan(text: 'The forgetting curve:\n', style: white),
            TextSpan(text: 'Once a word is ', style: base),
            TextSpan(text: 'Mastered', style: orange),
            TextSpan(text: ', the algorithm schedules it for a future review. ⏳ Over time it assumes you\'ll forget — and automatically puts it back into your ', style: base),
            TextSpan(text: '🔄 learning pool', style: accent),
            TextSpan(text: '. The more times you\'ve recalled it correctly, the longer before it returns.', style: base),
          ]));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).padding.bottom + 24),
        decoration: BoxDecoration(
          color: AppColors.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: const HeroIcon(HeroIcons.informationCircle, color: AppColors.primary, size: 20, style: HeroIconStyle.outline),
              ),
              const SizedBox(width: 12),
              Text(
                isEl ? 'Πώς λειτουργεί η Πρόοδος' : 'How Progress Works',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ]),
            const SizedBox(height: 16),
            Container(height: 1, color: Colors.white10),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupStat(String label, String value, Color color, Widget iconWidget) {
    return Column(
      children: [
        iconWidget,
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  // 👨‍🏫 TEACHER & BOOK SELECTOR DIALOG (Collapsible)
  Future<void> _showBookSelector() async {
    try {
      final teachers = await LocalDB.instance.getAllTeachers();
      final currentBookId = await LocalDB.instance.getCurrentBookId();
      final currentTeacherId = await LocalDB.instance.getCurrentTeacherId();

      if (!mounted) return;

      if (teachers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.noTeachers))
        );
        return;
      }

      // Track which teachers are expanded (current teacher starts expanded)
      Set<int> expandedTeachers = {if (currentTeacherId != null) currentTeacherId};

      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.cardColor,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                expand: false,
                builder: (context, scrollController) {
                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          S.selectTeacherBook,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          S.tapTeacherHint,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            itemCount: teachers.length,
                            itemBuilder: (context, index) {
                              final teacher = teachers[index];
                              final isCurrentTeacher = teacher.id == currentTeacherId;
                              final isExpanded = expandedTeachers.contains(teacher.id);

                              return FutureBuilder<List<BookData>>(
                                future: LocalDB.instance.getAllBooks(teacherId: teacher.id),
                                builder: (context, snapshot) {
                                  final books = snapshot.data ?? [];

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Teacher Header (Tappable to expand/collapse)
                                      GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            if (isExpanded) {
                                              expandedTeachers.remove(teacher.id);
                                            } else {
                                              expandedTeachers.add(teacher.id);
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isCurrentTeacher
                                              ? AppColors.primary.withOpacity(0.1)
                                              : AppColors.background.withOpacity(0.5),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              // Expand/Collapse Icon
                                              AnimatedRotation(
                                                turns: isExpanded ? 0.25 : 0,
                                                duration: const Duration(milliseconds: 200),
                                                child: HeroIcon(
                                                  HeroIcons.chevronRight,
                                                  color: isCurrentTeacher ? AppColors.primary : Colors.grey,
                                                  size: 20, style: HeroIconStyle.outline,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              HeroIcon(
                                                HeroIcons.user,
                                                color: isCurrentTeacher ? AppColors.primary : Colors.grey,
                                                size: 20, style: HeroIconStyle.outline,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      teacher.name,
                                                      style: TextStyle(
                                                        color: isCurrentTeacher ? AppColors.primary : Colors.white,
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    if (teacher.description != null)
                                                      Text(
                                                        teacher.description!,
                                                        style: const TextStyle(
                                                          color: Colors.grey,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                S.nBooks(teacher.bookCount),
                                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),

                                      // Books under this teacher (only show if expanded)
                                      if (isExpanded)
                                        AnimatedSize(
                                          duration: const Duration(milliseconds: 200),
                                          child: Column(
                                            children: books.map((book) {
                                              final isSelected = book.id == currentBookId;
                                              return GestureDetector(
                                                onTap: () async {
                                                  final teacherChanged = teacher.id != currentTeacherId;
                                                  await LocalDB.instance.setCurrentTeacherId(teacher.id);
                                                  await LocalDB.instance.setCurrentBookId(book.id);
                                                  if (mounted) {
                                                    Navigator.pop(context);
                                                    setState(() => _currentLessonIndex = 0);
                                                    _lessonPageController?.jumpToPage(0);
                                                    LocalDB.instance.setCurrentLessonIndex(0);
                                                    if (teacherChanged) {
                                                      // Teacher changed — re-sync to download new teacher's words
                                                      setState(() => _isLoading = true);
                                                      await LocalDB.instance.syncEverything();
                                                    }
                                                    _fetchDashboardData();
                                                  }
                                                },
                                                child: Container(
                                                  margin: const EdgeInsets.only(left: 28, bottom: 8),
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                      ? AppColors.primary.withOpacity(0.2)
                                                      : AppColors.background,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: isSelected ? AppColors.primary : Colors.grey.shade800,
                                                      width: isSelected ? 2 : 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      HeroIcon(
                                                        HeroIcons.bookOpen,
                                                        color: isSelected ? AppColors.primary : Colors.grey.shade600,
                                                        size: 18, style: HeroIconStyle.outline,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              book.title,
                                                              style: TextStyle(
                                                                color: isSelected ? AppColors.primary : Colors.white,
                                                                fontSize: 14,
                                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                            ),
                                                            Text(
                                                              "${book.level ?? 'N/A'} • ${S.nLessons(book.lessonCount)}",
                                                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      _languageFlag(book.sourceLanguage),
                                                      if (isSelected) ...[
                                                        const SizedBox(width: 6),
                                                        const HeroIcon(HeroIcons.checkCircle, color: AppColors.primary, size: 16, style: HeroIconStyle.solid),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint("Error showing teacher/book selector: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything until initial data is loaded (splash already preloaded it)
    if (!_initialLoadDone) {
      return Scaffold(backgroundColor: AppColors.background, body: const SizedBox.shrink());
    }

    // Build pages ONCE outside the animation builder
    final pages = <Widget>[
      _buildLearnViewWithPaywall(),
      const StatsPage(),
      _buildLibraryView(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _bottomNavIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: _navigateToTab,
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey.shade400,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: HeroIcon(HeroIcons.home, style: HeroIconStyle.outline, size: 22),
            activeIcon: HeroIcon(HeroIcons.home, style: HeroIconStyle.solid, size: 22, color: AppColors.primary),
            label: S.learn,
          ),
          BottomNavigationBarItem(
            icon: HeroIcon(HeroIcons.chartBar, style: HeroIconStyle.outline, size: 22),
            activeIcon: HeroIcon(HeroIcons.chartBar, style: HeroIconStyle.solid, size: 22, color: AppColors.primary),
            label: S.stats,
          ),
          BottomNavigationBarItem(
            icon: HeroIcon(HeroIcons.bookOpen, style: HeroIconStyle.outline, size: 22),
            activeIcon: HeroIcon(HeroIcons.bookOpen, style: HeroIconStyle.solid, size: 22, color: AppColors.primary),
            label: S.library,
          ),
          BottomNavigationBarItem(
            icon: HeroIcon(HeroIcons.user, style: HeroIconStyle.outline, size: 22),
            activeIcon: HeroIcon(HeroIcons.user, style: HeroIconStyle.solid, size: 22, color: AppColors.primary),
            label: S.profile,
          ),
        ],
      ),
    );
  }

  Widget _buildLearnViewWithPaywall() {
    return ValueListenableBuilder<SubscriptionState>(
      valueListenable: SubscriptionService.instance.state,
      builder: (context, subState, _) {
        final r = Responsive(context);
        return Stack(
          children: [
            _buildLearnView(),
            // Trial banner (last 14 days)
            if (subState.access == AccessLevel.trial && subState.trialDaysLeft <= 14)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(4)),
                    padding: EdgeInsets.symmetric(horizontal: r.spacing(12), vertical: r.spacing(8)),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(r.radius(10)),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, color: AppColors.primary, size: r.iconSize(16)),
                        SizedBox(width: r.spacing(8)),
                        Expanded(
                          child: Text(
                            '${S.freeTrialDaysLeft}: ${S.trialDaysN(subState.trialDaysLeft)}',
                            style: TextStyle(color: AppColors.primary, fontSize: r.fontSize(12), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Paywall overlay when locked
            if (!subState.canLearn)
              const PaywallOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildLearnView() {
    final r = Responsive(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: HeroIcon(HeroIcons.bookOpen, color: AppColors.primary, size: r.iconSize(24), style: HeroIconStyle.outline), onPressed: _showBookSelector),
        title: Column(
          children: [
            Text(_bookTitle.isNotEmpty ? _bookTitle : S.sourceLanguageName(_sourceLanguage), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(18), letterSpacing: 1.5)),
            if (_bookLevel.isNotEmpty) Text("Level: $_bookLevel", style: TextStyle(color: Colors.grey, fontSize: r.fontSize(12))),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _showStreakDetails,
            child: Container(
              margin: r.padding(right: 16, top: 10, bottom: 10),
              padding: r.padding(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(r.radius(20)),
                border: Border.all(color: Colors.orange, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("$_streak", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: r.fontSize(16))),
                  r.gapW(4),
                  HeroIcon(HeroIcons.fire, color: Colors.orange, size: r.iconSize(18), style: HeroIconStyle.solid),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: _PoppingBubbleLoader())
          : _lessons.isEmpty
              ? Center(
                  child: GestureDetector(
                    onTap: _showBookSelector,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HeroIcon(HeroIcons.bookOpen, color: AppColors.primary, size: r.iconSize(48), style: HeroIconStyle.outline),
                        r.gapH(16),
                        Text(S.selectBook, style: TextStyle(color: Colors.white, fontSize: r.fontSize(16), fontWeight: FontWeight.bold)),
                        r.gapH(8),
                        Text(S.tapToSelectBook, style: TextStyle(color: Colors.grey, fontSize: r.fontSize(13))),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    r.gapH(5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLanguageBtn("${S.sourceLanguageShort(_sourceLanguage)} -> Gr"),
                        r.gapW(12),
                        _buildLanguageBtn("Gr -> ${S.sourceLanguageShort(_sourceLanguage)}"),
                      ],
                    ),
                    r.gapH(5),
                    Expanded(
                      child: PageView.builder(
                        controller: _lessonPageController ??= PageController(
                          viewportFraction: r.device(phone: 0.85, tablet: 0.6),
                          initialPage: _currentLessonIndex,
                        ),
                        itemCount: _lessons.length,
                        onPageChanged: (index) {
                          setState(() => _currentLessonIndex = index);
                          LocalDB.instance.setCurrentLessonIndex(index);
                        },
                        itemBuilder: (context, index) {
                          bool isActive = index == _currentLessonIndex;
                          return AnimatedScale(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutBack,
                            scale: isActive ? 1.0 : 0.9,
                            child: _buildLessonCard(_lessons[index], isActive),
                          );
                        },
                      ),
                    ),
                    r.gapH(5),
                    Container(
                      padding: r.padding(left: 20, right: 20, top: 15, bottom: 15),
                      decoration: BoxDecoration(
                        color: AppColors.cardColor,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(r.radius(30))),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(S.selectMode, style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.fontSize(12), color: Colors.white54)),
                          r.gapH(12),
                          Row(
                            children: [
                              _buildModeBtn("Game", S.game, HeroIcons.puzzlePiece),
                              r.gapW(10),
                              _buildModeBtn("Test", S.test, HeroIcons.clipboardDocumentCheck),
                              r.gapW(10),
                              _buildModeBtn("Survival", S.survival, HeroIcons.clock),
                            ],
                          ),
                          r.gapH(15),
                          SizedBox(
                            width: double.infinity,
                            height: r.scale(48).clamp(44, 56),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.radius(12))),
                              ),
                              onPressed: () async {
                                final selectedLesson = _lessons[_currentLessonIndex];
                                bool isReversed = _selectedLanguage.startsWith('Gr');
                                // English books have swapped columns (en=English, es=Greek)
                                // so flip the direction
                                if (_sourceLanguage == 'en') isReversed = !isReversed;
                                Route? route;

                                if (_selectedMode == 'Game') {
                                  route = MaterialPageRoute(builder: (context) => GameQuizPage(lessonId: selectedLesson.id, isReversed: isReversed, sourceLanguage: _sourceLanguage));
                                } else if (_selectedMode == 'Test') {
                                  route = MaterialPageRoute(builder: (context) => BubblePage(lessonId: selectedLesson.id, isReversed: isReversed, sourceLanguage: _sourceLanguage));
                                } else if (_selectedMode == 'Survival') {
                                  final db = await LocalDB.instance.database;
                                  final countResult = await db.rawQuery(
                                    'SELECT COUNT(*) as cnt FROM lesson_words WHERE lesson_id = ?',
                                    [selectedLesson.id],
                                  );
                                  final totalWords = (countResult.first['cnt'] as int? ?? 20).clamp(1, 9999);
                                  RangeValues _range = RangeValues(0, totalWords.toDouble());
                                  bool _hardcore = false;
                                  final RangeValues? picked = await showDialog<RangeValues>(
                                    context: context,
                                    barrierColor: Colors.black87,
                                    builder: (ctx) => StatefulBuilder(
                                      builder: (ctx, setDialogState) {
                                        final int wordCount = (_range.end - _range.start).round();
                                        return Dialog(
                                          backgroundColor: Colors.transparent,
                                          insetPadding: EdgeInsets.symmetric(horizontal: r.spacing(24), vertical: r.spacing(40)),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: AppColors.cardColor,
                                              borderRadius: BorderRadius.circular(r.radius(28)),
                                              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Header
                                                Container(
                                                  width: double.infinity,
                                                  padding: EdgeInsets.symmetric(vertical: r.spacing(24), horizontal: r.spacing(24)),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [AppColors.primary.withOpacity(0.12), Colors.transparent],
                                                      begin: Alignment.topCenter,
                                                      end: Alignment.bottomCenter,
                                                    ),
                                                    borderRadius: BorderRadius.vertical(top: Radius.circular(r.radius(28))),
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      Text(S.survival, style: TextStyle(color: Colors.white, fontSize: r.fontSize(22), fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                                    ],
                                                  ),
                                                ),

                                                Padding(
                                                  padding: EdgeInsets.symmetric(horizontal: r.spacing(24)),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      SizedBox(height: r.spacing(16)),
                                                      // Word range display
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text("Word range", style: TextStyle(color: Colors.white54, fontSize: r.fontSize(12))),
                                                          Container(
                                                            padding: EdgeInsets.symmetric(horizontal: r.spacing(10), vertical: r.spacing(4)),
                                                            decoration: BoxDecoration(
                                                              color: AppColors.primary.withOpacity(0.15),
                                                              borderRadius: BorderRadius.circular(r.radius(20)),
                                                              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                                            ),
                                                            child: Text(
                                                              "${_range.start.round()} – ${_range.end.round()}  •  $wordCount word${wordCount == 1 ? '' : 's'}",
                                                              style: TextStyle(color: AppColors.primary, fontSize: r.fontSize(12), fontWeight: FontWeight.bold),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(height: r.spacing(4)),
                                                      RangeSlider(
                                                        values: _range,
                                                        min: 0,
                                                        max: totalWords.toDouble(),
                                                        divisions: totalWords,
                                                        activeColor: AppColors.primary,
                                                        inactiveColor: Colors.white12,
                                                        onChanged: (v) => setDialogState(() => _range = v),
                                                      ),

                                                      SizedBox(height: r.spacing(8)),
                                                      // Hardcore toggle
                                                      GestureDetector(
                                                        onTap: () => setDialogState(() => _hardcore = !_hardcore),
                                                        child: AnimatedContainer(
                                                          duration: const Duration(milliseconds: 200),
                                                          padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(12)),
                                                          decoration: BoxDecoration(
                                                            color: _hardcore ? Colors.redAccent.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                                                            borderRadius: BorderRadius.circular(r.radius(14)),
                                                            border: Border.all(
                                                              color: _hardcore ? Colors.redAccent.withOpacity(0.5) : Colors.white.withOpacity(0.08),
                                                              width: 1.5,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Icon(LucideIcons.skull, color: _hardcore ? Colors.redAccent : Colors.white54, size: r.fontSize(22)),
                                                              SizedBox(width: r.spacing(12)),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text("Hardcore", style: TextStyle(color: _hardcore ? Colors.redAccent : Colors.white, fontSize: r.fontSize(14), fontWeight: FontWeight.bold)),
                                                                    Text("Type freely — mistakes shown at end", style: TextStyle(color: Colors.white38, fontSize: r.fontSize(10))),
                                                                  ],
                                                                ),
                                                              ),
                                                              AnimatedContainer(
                                                                duration: const Duration(milliseconds: 200),
                                                                width: r.scale(22),
                                                                height: r.scale(22),
                                                                decoration: BoxDecoration(
                                                                  shape: BoxShape.circle,
                                                                  color: _hardcore ? Colors.redAccent : Colors.transparent,
                                                                  border: Border.all(color: _hardcore ? Colors.redAccent : Colors.white38, width: 2),
                                                                ),
                                                                child: _hardcore ? Icon(Icons.check, color: Colors.white, size: r.scale(14)) : null,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: r.spacing(20)),
                                                    ],
                                                  ),
                                                ),

                                                // Buttons
                                                Padding(
                                                  padding: EdgeInsets.fromLTRB(r.spacing(24), 0, r.spacing(24), r.spacing(20)),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: OutlinedButton(
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor: Colors.white54,
                                                            side: BorderSide(color: Colors.white12),
                                                            padding: EdgeInsets.symmetric(vertical: r.spacing(13)),
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.radius(12))),
                                                          ),
                                                          onPressed: () => Navigator.pop(ctx),
                                                          child: Text(S.cancel, style: TextStyle(fontSize: r.fontSize(14))),
                                                        ),
                                                      ),
                                                      SizedBox(width: r.spacing(12)),
                                                      Expanded(
                                                        flex: 2,
                                                        child: ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: _hardcore ? Colors.redAccent : AppColors.primary,
                                                            foregroundColor: Colors.white,
                                                            padding: EdgeInsets.symmetric(vertical: r.spacing(13)),
                                                            elevation: 0,
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.radius(12))),
                                                          ),
                                                          onPressed: wordCount == 0 ? null : () => Navigator.pop(ctx, _range),
                                                          child: Text(S.ok, style: TextStyle(fontSize: r.fontSize(14), fontWeight: FontWeight.bold)),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );

                                  if (picked != null) {
                                    route = MaterialPageRoute(
                                      builder: (context) => SurvivalPage(
                                        lessonId: selectedLesson.id,
                                        isReversed: isReversed,
                                        wordRangeStart: picked.start.round(),
                                        wordRangeEnd: picked.end.round(),
                                        sourceLanguage: _sourceLanguage,
                                        isHardcore: _hardcore,
                                      )
                                    );
                                  }
                                }

                                if (route != null) {
                                  await Navigator.push(context, route);
                                  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                                  _fetchDashboardData();
                                  _calculateStreakAndStats();
                                }
                              },
                              child: Text(S.startLesson, style: TextStyle(fontSize: r.fontSize(16), fontWeight: FontWeight.bold, color: Colors.black)),
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
    );
  }

  void _showLibraryInfo(BuildContext ctx, Responsive r) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(r.spacing(24)),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(r.radius(20)),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(r.spacing(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    HeroIcon(HeroIcons.bookOpen, color: AppColors.primary, size: r.iconSize(20), style: HeroIconStyle.solid),
                    SizedBox(width: r.spacing(10)),
                    Text('How to read the Library', style: TextStyle(color: Colors.white, fontSize: r.fontSize(16), fontWeight: FontWeight.w800)),
                  ],
                ),
                SizedBox(height: r.spacing(16)),
                // Word status section label
                Text('WORD STATUS', style: TextStyle(color: Colors.white38, fontSize: r.fontSize(10), fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                SizedBox(height: r.spacing(10)),
                _infoRow(r, _dot(r, Colors.grey.shade700), 'New', 'Haven\'t studied this word yet.'),
                _infoRow(r, _dot(r, AppColors.primary.withOpacity(0.25)), 'Learning', 'Seen but still being drilled — not yet in spaced repetition.'),
                _infoRow(r, _dot(r, AppColors.accent), 'Due for review', 'In spaced repetition and due — needs a review now.'),
                _infoRow(r, _dot(r, AppColors.primary), 'Mastered', 'Scheduled in the future — not due yet.'),
                SizedBox(height: r.spacing(14)),
                Divider(color: Colors.white.withOpacity(0.07), height: 1),
                SizedBox(height: r.spacing(14)),
                // Other metrics
                Text('OTHER METRICS', style: TextStyle(color: Colors.white38, fontSize: r.fontSize(10), fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                SizedBox(height: r.spacing(10)),
                _infoRow(r, _pill(r, AppColors.primary), 'Strength bar', 'Thin bar beside each word — longer = stronger memory. Colour matches the word\'s status dot.'),
                _infoRow(r, _pct(r), 'Accuracy %', 'How often you answered correctly out of all attempts.'),
                _infoRow(r, _circle(r), 'Lesson circle', 'Big % = Mastered words. Inner arc = words still in Review.'),
                SizedBox(height: r.spacing(18)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(vertical: r.spacing(13)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.radius(12))),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('Got it', style: TextStyle(fontSize: r.fontSize(14), fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(Responsive r, Color color) => Container(
    width: r.scale(10), height: r.scale(10),
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  Widget _pill(Responsive r, Color color) => Container(
    width: r.scale(18), height: r.scale(5),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: color),
  );

  Widget _pct(Responsive r) => Text('%', style: TextStyle(color: AppColors.primary, fontSize: r.fontSize(12), fontWeight: FontWeight.w800));

  Widget _circle(Responsive r) => SizedBox(
    width: r.scale(16), height: r.scale(16),
    child: CircularProgressIndicator(
      value: 0.6,
      strokeWidth: r.scale(2.5),
      backgroundColor: AppColors.accent.withOpacity(0.4),
      valueColor: AlwaysStoppedAnimation(AppColors.primary),
    ),
  );

  Widget _infoRow(Responsive r, Widget icon, String title, String body) {
    return Padding(
      padding: EdgeInsets.only(bottom: r.spacing(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: r.scale(24), child: Center(child: icon)),
          SizedBox(width: r.spacing(10)),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: '$title  ', style: TextStyle(color: Colors.white, fontSize: r.fontSize(13), fontWeight: FontWeight.w700)),
                  TextSpan(text: body, style: TextStyle(color: Colors.white54, fontSize: r.fontSize(12), height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryView() {
    final r = Responsive(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _lessons.isEmpty
            ? Center(child: Text(S.noLessonsInBook, style: TextStyle(color: Colors.grey, fontSize: r.fontSize(14))))
            : ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(8)),
                itemCount: _lessons.length + 1, // +1 for header
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: EdgeInsets.only(top: r.spacing(8), bottom: r.spacing(12)),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(S.libraryTitle.toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(18), letterSpacing: 1.5)),
                          Positioned(
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _showLibraryInfo(context, r),
                              child: HeroIcon(HeroIcons.informationCircle, color: AppColors.primary, size: r.iconSize(18), style: HeroIconStyle.outline),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final lesson = _lessons[index - 1];
                  final totalWords = lesson.learned + lesson.learning + lesson.unseen;
                  return _LibraryLessonTile(
                    lessonId: lesson.id,
                    title: lesson.title,
                    chapterNumber: lesson.chapter_number,
                    wordCount: totalWords,
                    sourceLanguage: _sourceLanguage,
                    isReversed: _selectedLanguage.startsWith('Gr'),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildLanguageBtn(String label) {
    final r = Responsive(context);
    bool isSelected = _selectedLanguage == label;
    return GestureDetector(
      onTap: () async {
        setState(() => _selectedLanguage = label);
        final isReversed = label.startsWith('Gr');
        await LocalDB.instance.setWordDirection(isReversed ? 'reverse' : 'normal');
        _fetchDashboardData();
        LocalDB.instance.notifyDataChanged();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: r.padding(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(r.radius(20)),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade700),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontWeight: FontWeight.bold, fontSize: r.fontSize(14))),
      ),
    );
  }



  String _languageCode(String lang) {
    switch (lang) {
      case 'es': return 'ES';
      case 'en': return 'EN';
      case 'fr': return 'FR';
      case 'de': return 'DE';
      case 'it': return 'IT';
      case 'pt': return 'PT';
      case 'el': return 'GR';
      case 'ja': return 'JA';
      case 'zh': return 'ZH';
      case 'ko': return 'KO';
      default:   return '??';
    }
  }

  Widget _languageFlag(String lang) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.flag, size: 14, color: AppColors.primary),
        const SizedBox(width: 3),
        Text(_languageCode(lang), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
      ],
    );
  }

  Widget _buildLessonCard(LessonData lesson, bool isActive) {
    final r = Responsive(context);
    final cardSize = r.lessonCardSize;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: cardSize.width,
        height: cardSize.height,
        // Remove padding here so PageView fills the whole card
        decoration: BoxDecoration(
          gradient: isActive ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF151618), const Color(0xFF111214)]) : const LinearGradient(colors: [Color(0xFF111214), Color(0xFF111214)]),
          borderRadius: BorderRadius.circular(r.radius(30)),
          boxShadow: isActive ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))] : [],
          border: Border.all(color: isActive ? AppColors.primary : Colors.grey.shade900, width: isActive ? 2 : 1),
        ),
        // ↕️ VERTICAL SCROLL ENABLED HERE ↕️
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r.radius(30)),
          child: PageView(
            scrollDirection: Axis.vertical,
            children: [
              // PAGE 1: The Classic Circle
              _buildCardPage1(lesson, isActive),

              // PAGE 2: The New Bar Chart
              _buildCardPage2(lesson),
            ],
          ),
        ),
      ),
    );
  }

  // --- PAGE 1: CIRCLE VIEW (Your original design) ---
  Widget _buildCardPage1(LessonData lesson, bool isActive) {
    final r = Responsive(context);
    int total = lesson.learned + lesson.learning + lesson.unseen;
    double progressPct = total == 0 ? 0.0 : (lesson.learned / total);
    double learningPct = total == 0 ? 0.0 : ((lesson.learned + lesson.learning) / total);
    final circleSize = r.progressCircleSize;
    final strokeWidth = r.scale(12).clamp(8.0, 16.0);

    return Stack(
      children: [
        Padding(
          padding: r.padding(horizontal: 24, vertical: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(children: [
                Text(S.chapterN(lesson.chapter_number), style: TextStyle(fontSize: r.fontSize(14), fontWeight: FontWeight.bold, color: Colors.white)),
                r.gapH(8),
                Text(lesson.title.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: r.fontSize(15), letterSpacing: 1.3, fontWeight: FontWeight.bold, color: isActive ? AppColors.primary : Colors.grey))
          ]),
          SizedBox(
            height: circleSize,
            width: circleSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(value: 1.0, valueColor: AlwaysStoppedAnimation(Colors.grey.shade800), strokeWidth: strokeWidth),
                CircularProgressIndicator(value: learningPct, valueColor: AlwaysStoppedAnimation(AppColors.accent.withOpacity(0.5)), strokeWidth: strokeWidth),
                CircularProgressIndicator(value: progressPct, valueColor: const AlwaysStoppedAnimation(AppColors.primary), strokeWidth: strokeWidth, strokeCap: StrokeCap.round),
                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("${(progressPct * 100).toInt()}%", style: TextStyle(fontSize: r.fontSize(32), fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(S.mastered, style: TextStyle(fontSize: r.fontSize(12), color: Colors.grey))
                ])),
              ],
            ),
          ),
          // Scroll Indicator
          HeroIcon(HeroIcons.chevronDown, color: Colors.grey.withOpacity(0.5), size: r.iconSize(20), style: HeroIconStyle.outline),

          Container(
            padding: r.padding(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(r.radius(16))),
            child: Row(
              children: [
                Expanded(child: _buildStatItem(lesson.learned, S.mastered, AppColors.primary)),
                Container(width: 1, height: r.scale(24), color: Colors.grey.shade800),
                Expanded(child: _buildStatItem(lesson.learning, S.review, AppColors.accent)),
                Container(width: 1, height: r.scale(24), color: Colors.grey.shade800),
                Expanded(child: _buildStatItem(lesson.unseen, S.newWord, Colors.grey)),
              ]
            ),
          )
        ],
      ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: GestureDetector(
            onTap: _showProgressInfo,
            child: HeroIcon(HeroIcons.informationCircle, color: Colors.grey.withOpacity(0.4), size: r.iconSize(18), style: HeroIconStyle.outline),
          ),
        ),
      ],
    );
  }

  // --- PAGE 2: BAR CHART VIEW (New) ---
  // --- PAGE 2: BAR CHART VIEW (Clean Layout) ---
  Widget _buildCardPage2(LessonData lesson) {
    // Labels corresponding to indices 0..6
    final labels = S.forecastLabelsCard;

    // Calculate Max Y for chart scaling
    int maxVal = 0;
    if (lesson.forecast.isNotEmpty) {
      maxVal = lesson.forecast.reduce((a, b) => a > b ? a : b);
    }
    if (maxVal == 0) maxVal = 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), // Adjusted padding
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header
          Column(children: [
            Text(S.upcomingReviews, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(lesson.title.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, letterSpacing: 1.1, color: Colors.grey))
          ]),

          const SizedBox(height: 10),

          // The Chart
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                maxY: maxVal.toDouble() + 1,
                barTouchData: BarTouchData(enabled: false), // No interaction needed

                titlesData: FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),

                  // ⬇️ HERE IS THE MAGIC: Number + Label at the bottom ⬇️
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32, // More space for double text
                      getTitlesWidget: (value, meta) {
                        int idx = value.toInt();
                        if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();

                        // Get the count for this specific column
                        int count = lesson.forecast[idx];

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. The Number (Count)
                            Text(
                              count > 0 ? "$count" : "-", // Show "-" if 0 for cleaner look
                              style: TextStyle(
                                color: count > 0 ? Colors.white : Colors.grey.withOpacity(0.3),
                                fontSize: 12,
                                fontWeight: FontWeight.bold
                              )
                            ),
                            // 2. The Label (Day)
                            Text(
                              labels[idx],
                              style: const TextStyle(color: Colors.grey, fontSize: 10)
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),

                barGroups: lesson.forecast.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.toDouble(),
                        // Red for Late, Primary Color for future
                        color: entry.key == 0 ? Colors.redAccent : AppColors.primary,
                        width: 12, // Slightly thinner bars for elegance
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxVal.toDouble() + 1,
                          color: Colors.white.withOpacity(0.05)
                        ),
                      ),
                    ],
                    // 🚫 No more floating tooltips overlapping each other!
                    showingTooltipIndicators: [],
                  );
                }).toList(),
              ),
            ),
          ),

          // Scroll Indicator
          const SizedBox(height: 10),
          HeroIcon(HeroIcons.chevronUp, color: Colors.grey.withOpacity(0.5), size: 20, style: HeroIconStyle.outline),
        ],
      ),
    );
  }
  Widget _buildStatItem(int count, String label, Color color) {
    final r = Responsive(context);
    return Column(children: [
      Text("$count", style: TextStyle(fontSize: r.fontSize(18), fontWeight: FontWeight.bold, color: color)),
      Text(label, style: TextStyle(fontSize: r.fontSize(10), color: Colors.grey.shade400), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    ]);
  }
  Widget _buildModeBtn(String key, String displayLabel, HeroIcons icon) {
    final r = Responsive(context);
    bool isSelected = _selectedMode == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMode = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: r.padding(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(r.radius(12)),
            border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade800),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HeroIcon(icon, size: r.iconSize(18), color: isSelected ? Colors.black : Colors.grey, style: HeroIconStyle.outline),
              r.gapW(8),
              Text(
                displayLabel,
                style: TextStyle(
                  fontSize: r.fontSize(13),
                  color: isSelected ? Colors.black : Colors.grey,
                  fontWeight: FontWeight.bold
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single lesson tile that lazily loads its words when expanded.
class _LibraryLessonTile extends StatefulWidget {
  final int lessonId;
  final String title;
  final int chapterNumber;
  final int wordCount;
  final String sourceLanguage;
  final bool isReversed;

  const _LibraryLessonTile({
    required this.lessonId,
    required this.title,
    required this.chapterNumber,
    required this.wordCount,
    required this.sourceLanguage,
    required this.isReversed,
  });

  @override
  State<_LibraryLessonTile> createState() => _LibraryLessonTileState();
}

class _LibraryLessonTileState extends State<_LibraryLessonTile> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>>? _words;
  bool _isLoading = false;

  @override
  void didUpdateWidget(_LibraryLessonTile old) {
    super.didUpdateWidget(old);
    if (old.isReversed != widget.isReversed) {
      _words = null;
      _avgStrength = null;
      _loadAvgStrength();
      if (_isExpanded) _loadWords();
    }
  }
  bool _isExpanded = false;
  double? _avgStrength;

  @override
  void initState() {
    super.initState();
    _loadAvgStrength();
  }

  Future<void> _loadAvgStrength() async {
    final db = await LocalDB.instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final direction = await LocalDB.instance.getWordDirection();
    final progressTable = direction == 'reverse' ? 'user_progress' : 'user_progress_reverse';
    final result = await db.rawQuery('''
      SELECT AVG(up.strength) AS avg_strength,
             COUNT(up.id) AS attempted
      FROM lesson_words lw
      JOIN words w ON w.id = lw.word_id
      LEFT JOIN $progressTable up ON up.word_id = w.id AND up.user_id = ?
      WHERE lw.lesson_id = ?
    ''', [userId, widget.lessonId]);

    if (result.isNotEmpty && mounted) {
      final attempted = (result.first['attempted'] as num?)?.toInt() ?? 0;
      if (attempted > 0) {
        final avg = (result.first['avg_strength'] as num?)?.toDouble() ?? 0.0;
        setState(() => _avgStrength = avg);
      }
    }
  }

  Future<void> _loadWords() async {
    if (_words != null && !_isLoading) return; // already loaded
    setState(() => _isLoading = true);
    final db = await LocalDB.instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    final direction = await LocalDB.instance.getWordDirection();
    final progressTable = direction == 'reverse' ? 'user_progress' : 'user_progress_reverse';
    final rows = await db.rawQuery('''
      SELECT w.id, w.es, w.en,
             COALESCE(up.status, 'new') AS status,
             COALESCE(up.strength, 0.0) AS strength,
             COALESCE(up.total_attempts, 0) AS total_attempts,
             COALESCE(up.total_correct, 0) AS total_correct,
             up.next_due_at
      FROM lesson_words lw
      JOIN words w ON w.id = lw.word_id
      LEFT JOIN $progressTable up ON up.word_id = w.id AND up.user_id = ?
      WHERE lw.lesson_id = ?
      ORDER BY w.id ASC
    ''', [userId ?? '', widget.lessonId]);

    if (mounted) {
      setState(() {
        _words = rows;
        _isLoading = false;
      });
    }
  }

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) _loadWords();
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    return Container(
      margin: EdgeInsets.only(bottom: r.spacing(10)),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(r.radius(12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header (tappable)
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(12)),
              child: Row(
                children: [
                  Container(
                    width: r.scale(40),
                    height: r.scale(40),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(r.radius(10)),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.chapterNumber}',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: r.fontSize(16)),
                      ),
                    ),
                  ),
                  SizedBox(width: r.spacing(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(14)),
                        ),
                        Row(
                          children: [
                            Text(
                              S.nWords(widget.wordCount),
                              style: TextStyle(color: Colors.grey, fontSize: r.fontSize(11)),
                            ),
                            if (_avgStrength != null) ...[
                              Text('  ·  ', style: TextStyle(color: Colors.grey.shade700, fontSize: r.fontSize(11))),
                              Text(
                                _avgStrength!.toStringAsFixed(2),
                                style: TextStyle(
                                  color: _avgStrength! >= 0.75
                                      ? AppColors.primary
                                      : _avgStrength! >= 0.4
                                          ? AppColors.primary.withOpacity(0.5)
                                          : Colors.grey.shade500,
                                  fontSize: r.fontSize(11),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: HeroIcon(HeroIcons.chevronDown, color: Colors.grey, size: r.iconSize(20), style: HeroIconStyle.outline),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _isExpanded ? _buildContent(r) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Responsive r) {
    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.all(r.spacing(16)),
        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
      );
    }
    if (_words != null && _words!.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(r.spacing(16)),
        child: Text(S.noWordsInLesson, style: TextStyle(color: Colors.grey, fontSize: r.fontSize(12))),
      );
    }
    if (_words == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Header row
        Container(
          padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(8)),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text(S.sourceLanguageName(widget.sourceLanguage), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: r.fontSize(11), letterSpacing: 1))),
              Expanded(flex: 4, child: Text(S.greek, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: r.fontSize(11), letterSpacing: 1))),
              SizedBox(width: r.spacing(40), child: Text(S.stats, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: r.fontSize(11), letterSpacing: 1), textAlign: TextAlign.center)),
            ],
          ),
        ),
        // Word rows
        ...(_words!.map((word) {
          final status = word['status']?.toString() ?? 'new';
          final strength = (word['strength'] as num?)?.toDouble() ?? 0.0;
          final attempts = (word['total_attempts'] as int?) ?? 0;
          final correct = (word['total_correct'] as int?) ?? 0;

          final nextDueRaw = word['next_due_at'];
          final nextDue = nextDueRaw != null ? DateTime.tryParse(nextDueRaw as String)?.toUtc() : null;
          final isDue = nextDue == null || nextDue.isBefore(DateTime.now().toUtc());

          final Color statusColor;
          if ((status == 'consolidating' || status == 'learned') && !isDue) {
            statusColor = AppColors.primary;                        // bright orange = mastered
          } else if (status == 'consolidating' && isDue) {
            statusColor = AppColors.accent;                         // deep orange = due for review
          } else if (status == 'learning') {
            statusColor = AppColors.primary.withOpacity(0.25);     // very faint = still learning
          } else {
            statusColor = Colors.grey.shade700;                     // grey = never seen
          }

          return Container(
            padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(8)),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.03))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Container(
                        width: r.scale(8),
                        height: r.scale(8),
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      SizedBox(width: r.spacing(6)),
                      Expanded(
                        child: Text(
                          // English books: en=English, es=Greek (swapped)
                          word[widget.sourceLanguage == 'en' ? 'en' : 'es']?.toString() ?? '',
                          style: TextStyle(color: Colors.white, fontSize: r.fontSize(13)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    word[widget.sourceLanguage == 'en' ? 'es' : 'en']?.toString() ?? '',
                    style: TextStyle(
                      color: status == 'new' ? Colors.grey.shade600 : Colors.white,
                      fontSize: r.fontSize(13),
                    ),
                  ),
                ),
                SizedBox(
                  width: r.spacing(40),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(r.radius(3)),
                        child: SizedBox(
                          height: r.scale(4),
                          child: LinearProgressIndicator(
                            value: strength.clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withOpacity(0.08),
                            valueColor: AlwaysStoppedAnimation(statusColor),
                          ),
                        ),
                      ),
                      SizedBox(height: r.spacing(3)),
                      Text(
                        attempts > 0 ? '${((correct / attempts) * 100).round()}%' : '-',
                        style: TextStyle(color: Colors.grey, fontSize: r.fontSize(9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        })),
        SizedBox(height: r.spacing(8)),
      ],
    );
  }
}

class _PoppingBubbleLoader extends StatefulWidget {
  const _PoppingBubbleLoader();

  @override
  State<_PoppingBubbleLoader> createState() => _PoppingBubbleLoaderState();
}

class _PoppingBubbleLoaderState extends State<_PoppingBubbleLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Grow from 0 to 1 during 0..0.7, then pop during 0.7..1.0
        final isPopping = t > 0.7;
        final growT = (t / 0.7).clamp(0.0, 1.0);
        final popT = ((t - 0.7) / 0.3).clamp(0.0, 1.0);

        final baseRadius = 30.0;
        final radius = isPopping
            ? baseRadius * (1.0 + popT * 0.5)
            : baseRadius * (0.3 + growT * 0.7);
        final opacity = isPopping ? (1.0 - popT) : 1.0;

        return SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(
            painter: _BubbleLoaderPainter(
              radius: radius,
              opacity: opacity,
              popT: isPopping ? popT : 0.0,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }
}

class _BubbleLoaderPainter extends CustomPainter {
  final double radius, opacity, popT;
  final Color color;

  _BubbleLoaderPainter({
    required this.radius,
    required this.opacity,
    required this.popT,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    if (popT > 0) {
      // Expanding ring
      final ringPaint = Paint()
        ..color = color.withOpacity(0.6 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - popT);
      canvas.drawCircle(center, radius, ringPaint);

      // Particles
      final particlePaint = Paint()
        ..color = color.withOpacity(0.8 * opacity)
        ..style = PaintingStyle.fill;
      for (int i = 0; i < 6; i++) {
        final angle = (i / 6) * 3.14159 * 2;
        final dist = radius * (0.5 + popT * 2.0);
        final px = center.dx + dist * (angle.cos());
        final py = center.dy + dist * (angle.sin());
        final pSize = 3.0 * (1.0 - popT);
        canvas.drawCircle(Offset(px, py), pSize, particlePaint);
      }
    } else {
      // Growing bubble
      final fill = Paint()
        ..color = color.withOpacity(0.3 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, fill);

      final ring = Paint()
        ..color = color.withOpacity(0.7 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius, ring);

      // Highlight
      final highlight = Paint()
        ..color = Colors.white.withOpacity(0.4 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
        radius * 0.2,
        highlight,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BubbleLoaderPainter old) =>
      old.radius != radius || old.opacity != opacity || old.popT != popT;
}

extension _MathOnDouble on double {
  double cos() => math.cos(this);
  double sin() => math.sin(this);
}
