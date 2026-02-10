import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _streak = 0;
  int _totalLearnedWords = 0; // New Stat
  int _currentLessonIndex = 0;
  String _selectedMode = 'Test';
  String _sourceLanguage = 'es'; // 'es' for Spanish, 'en' for English
  String _selectedLanguage = 'Gr -> Esp';
  int _bottomNavIndex = 0;
  bool _isLoading = true;
  List<LessonData> _lessons = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    await _fetchDashboardData();
    await _calculateStreakAndStats(); // Updated function

    if (_lessons.isEmpty) {
      if (mounted) setState(() => _isLoading = true);
      debugPrint("📱 Local DB is empty. Starting First-Time Sync...");
      try {
        await LocalDB.instance.syncEverything();

        // Auto-select first teacher and book if none selected
        final currentTeacher = await LocalDB.instance.getCurrentTeacherId();
        final currentBook = await LocalDB.instance.getCurrentBookId();

        if (currentTeacher == null || currentBook == null) {
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
      } catch (e) {
        debugPrint("⚠️ First Sync Error: $e");
      }
      if (mounted) await _fetchDashboardData();
    } else {
      debugPrint("🔄 Starting Background Sync...");
      LocalDB.instance.syncEverything().then((_) async {
         debugPrint("✅ Background Sync Complete. Refreshing UI.");

         // Auto-select first teacher and book if none selected
         final currentTeacher = await LocalDB.instance.getCurrentTeacherId();
         final currentBook = await LocalDB.instance.getCurrentBookId();

         if (currentTeacher == null || currentBook == null) {
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

         if (mounted) {
           _fetchDashboardData();
           _calculateStreakAndStats();
         }
      });
    }
  }

  Future<void> _fetchDashboardData() async {
    try {
      final data = await LocalDB.instance.getDashboardLessons();
      final srcLang = await LocalDB.instance.getBookSourceLanguage();
      if (mounted) {
        final shortLabel = S.sourceLanguageShort(srcLang);
        setState(() {
          _lessons = data;
          _sourceLanguage = srcLang;
          _selectedLanguage = 'Gr -> $shortLabel';
          _isLoading = false;
        });
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
      final learnedRes = await db.rawQuery("SELECT COUNT(*) FROM user_progress WHERE status IN ('learned', 'consolidating')");
      int learnedCount = Sqflite.firstIntValue(learnedRes) ?? 0;

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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.quickStats, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildPopupStat(S.dayStreak, "$_streak", Colors.orange, Icons.local_fire_department),
                  Container(width: 1, height: 50, color: Colors.grey.shade800),
                  _buildPopupStat(S.wordsLearned, "$_totalLearnedWords", AppColors.success, Icons.school),
                ],
              ),
              const SizedBox(height: 24),
              Text(S.keepGoing, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 10),
            ],
          ),
        );
      }
    );
  }

  Widget _buildPopupStat(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
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
                                                child: Icon(
                                                  Icons.chevron_right,
                                                  color: isCurrentTeacher ? AppColors.primary : Colors.grey,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.person,
                                                color: isCurrentTeacher ? AppColors.primary : Colors.grey,
                                                size: 20,
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
                                                      Icon(
                                                        Icons.menu_book,
                                                        color: isSelected ? AppColors.primary : Colors.grey.shade600,
                                                        size: 18,
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
                                                      if (isSelected)
                                                        const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _bottomNavIndex,
        children: [
          _buildLearnView(),
          const StatsPage(),
          _buildLibraryView(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (i) => setState(() => _bottomNavIndex = i),
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home_filled), label: S.learn),
          BottomNavigationBarItem(icon: const Icon(Icons.bar_chart), label: S.stats),
          BottomNavigationBarItem(icon: const Icon(Icons.book), label: S.library),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: S.profile),
        ],
      ),
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
        leading: IconButton(icon: Icon(Icons.menu_book, color: AppColors.primary, size: r.iconSize(24)), onPressed: _showBookSelector),
        title: Column(
          children: [
            Text("${S.sourceLanguageName(_sourceLanguage)} A1", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(18), letterSpacing: 1.5)),
            Text(S.beginnerCourse, style: TextStyle(color: Colors.grey, fontSize: r.fontSize(12))),
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
                  Text("🔥", style: TextStyle(fontSize: r.fontSize(16))),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _lessons.isEmpty
              ? Center(child: Text(S.noLessonsFound, style: TextStyle(color: Colors.white, fontSize: r.fontSize(16))))
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
                        controller: PageController(viewportFraction: r.device(phone: 0.85, tablet: 0.6)),
                        itemCount: _lessons.length,
                        onPageChanged: (index) => setState(() => _currentLessonIndex = index),
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
                              _buildModeBtn("Game", S.game, Icons.sports_esports),
                              r.gapW(10),
                              _buildModeBtn("Test", S.test, Icons.quiz),
                              r.gapW(10),
                              _buildModeBtn("Survival", S.survival, Icons.timer),
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
                                final bool isReversed = _selectedLanguage.startsWith('Gr');
                                Route? route;

                                if (_selectedMode == 'Game') {
                                  route = MaterialPageRoute(builder: (context) => GameQuizPage(lessonId: selectedLesson.id, isReversed: isReversed, sourceLanguage: _sourceLanguage));
                                } else if (_selectedMode == 'Test') {
                                  route = MaterialPageRoute(builder: (context) => BubblePage(lessonId: selectedLesson.id, isReversed: isReversed, sourceLanguage: _sourceLanguage));
                                } else if (_selectedMode == 'Survival') {
                                  // Show mode selection dialog for Survival
                                  final bool? isPracticeMode = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: AppColors.cardColor,
                                      title: Text(S.chooseMode, style: TextStyle(color: Colors.white, fontSize: r.fontSize(18))),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: Icon(Icons.school, color: AppColors.primary, size: r.iconSize(24)),
                                            title: Text(S.reviewMode, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(14))),
                                            subtitle: Text(S.onlyDueWords, style: TextStyle(color: Colors.white70, fontSize: r.fontSize(12))),
                                            onTap: () => Navigator.pop(ctx, false),
                                          ),
                                          r.gapH(8),
                                          ListTile(
                                            leading: Icon(Icons.sports_esports, color: Colors.blue, size: r.iconSize(24)),
                                            title: Text(S.practiceMode, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(14))),
                                            subtitle: Text(S.allWordsFromLesson, style: TextStyle(color: Colors.white70, fontSize: r.fontSize(12))),
                                            onTap: () => Navigator.pop(ctx, true),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  if (isPracticeMode != null) {
                                    route = MaterialPageRoute(
                                      builder: (context) => SurvivalPage(
                                        lessonId: selectedLesson.id,
                                        isReversed: isReversed,
                                        isPracticeMode: isPracticeMode,
                                        sourceLanguage: _sourceLanguage,
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
                      child: Center(
                        child: Text(S.libraryTitle.toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(18), letterSpacing: 1.5)),
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
      onTap: () => setState(() => _selectedLanguage = label),
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
          gradient: isActive ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF2C2C2C), const Color(0xFF1E1E1E)]) : const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF1A1A1A)]),
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

    return Padding(
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
          Icon(Icons.keyboard_arrow_down, color: Colors.grey.withOpacity(0.5), size: r.iconSize(20)),

          Container(
            padding: r.padding(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(r.radius(16))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(lesson.learned, S.mastered, AppColors.primary),
                Container(width: 1, height: r.scale(24), color: Colors.grey.shade800),
                _buildStatItem(lesson.learning, S.review, AppColors.accent),
                Container(width: 1, height: r.scale(24), color: Colors.grey.shade800),
                _buildStatItem(lesson.unseen, S.newWord, Colors.grey)
              ]
            ),
          )
        ],
      ),
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
          Icon(Icons.keyboard_arrow_up, color: Colors.grey.withOpacity(0.5), size: 20),
        ],
      ),
    );
  }
  Widget _buildStatItem(int count, String label, Color color) {
    final r = Responsive(context);
    return Column(children: [
      Text("$count", style: TextStyle(fontSize: r.fontSize(18), fontWeight: FontWeight.bold, color: color)),
      Text(label, style: TextStyle(fontSize: r.fontSize(10), color: Colors.grey.shade400))
    ]);
  }
  Widget _buildModeBtn(String key, String displayLabel, IconData icon) {
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
              Icon(icon, size: r.iconSize(18), color: isSelected ? Colors.black : Colors.grey),
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

  const _LibraryLessonTile({
    required this.lessonId,
    required this.title,
    required this.chapterNumber,
    required this.wordCount,
    required this.sourceLanguage,
  });

  @override
  State<_LibraryLessonTile> createState() => _LibraryLessonTileState();
}

class _LibraryLessonTileState extends State<_LibraryLessonTile> {
  List<Map<String, dynamic>>? _words;
  bool _isLoading = false;

  Future<void> _loadWords() async {
    if (_words != null) return; // already loaded
    setState(() => _isLoading = true);
    final db = await LocalDB.instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    debugPrint("🔍 LIBRARY _loadWords lesson=${widget.lessonId} userId=$userId");

    final rows = await db.rawQuery('''
      SELECT w.id, w.es, w.en,
             COALESCE(up.status, 'new') AS status,
             COALESCE(up.strength, 0.0) AS strength,
             COALESCE(up.total_attempts, 0) AS total_attempts,
             COALESCE(up.total_correct, 0) AS total_correct
      FROM lesson_words lw
      JOIN words w ON w.id = lw.word_id
      LEFT JOIN user_progress up ON up.word_id = w.id AND up.user_id = ?
      WHERE lw.lesson_id = ?
      ORDER BY w.id ASC
    ''', [userId ?? '', widget.lessonId]);

    // DEBUG: Log all words and their statuses for this lesson
    debugPrint("🔍 LIBRARY lesson=${widget.lessonId} found ${rows.length} words");
    for (var r in rows) {
      if (r['id'] == 1008 || r['status'] != 'new') {
        debugPrint("   🔍 word=${r['id']} es=${r['es']} status=${r['status']} attempts=${r['total_attempts']}");
      }
    }

    if (mounted) {
      setState(() {
        _words = rows;
        _isLoading = false;
      });
    }
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(4)),
          childrenPadding: EdgeInsets.zero,
          onExpansionChanged: (expanded) {
            if (expanded) _loadWords();
          },
          leading: Container(
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
          title: Text(
            widget.title,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(14)),
          ),
          subtitle: Text(
            S.nWords(widget.wordCount),
            style: TextStyle(color: Colors.grey, fontSize: r.fontSize(11)),
          ),
          iconColor: Colors.grey,
          collapsedIconColor: Colors.grey,
          children: [
            if (_isLoading)
              Padding(
                padding: EdgeInsets.all(r.spacing(16)),
                child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
              )
            else if (_words != null && _words!.isEmpty)
              Padding(
                padding: EdgeInsets.all(r.spacing(16)),
                child: Text(S.noWordsInLesson, style: TextStyle(color: Colors.grey, fontSize: r.fontSize(12))),
              )
            else if (_words != null)
              // Header row
              ...[
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

                  // Status color
                  final Color statusColor;
                  if (status == 'learned') {
                    statusColor = AppColors.primary;
                  } else if (status == 'learning') {
                    statusColor = AppColors.accent;
                  } else {
                    statusColor = Colors.grey.shade700;
                  }

                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(8)),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.white.withOpacity(0.03))),
                    ),
                    child: Row(
                      children: [
                        // Spanish word
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
                                  word['es']?.toString() ?? '',
                                  style: TextStyle(color: Colors.white, fontSize: r.fontSize(13)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Greek word
                        Expanded(
                          flex: 4,
                          child: Text(
                            word['en']?.toString() ?? '',
                            style: TextStyle(color: Colors.white70, fontSize: r.fontSize(13)),
                          ),
                        ),
                        // Strength bar + accuracy
                        SizedBox(
                          width: r.spacing(40),
                          child: Column(
                            children: [
                              // Strength bar
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
                              // Accuracy text
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
          ],
        ),
      ),
    );
  }
}
