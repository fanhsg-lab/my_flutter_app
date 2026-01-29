import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart'; 
import '../local_db.dart'; 
import 'notification_service.dart'; // Import the service
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
      } catch (e) {
        debugPrint("⚠️ First Sync Error: $e");
      }
      if (mounted) await _fetchDashboardData();
    } else {
      debugPrint("🔄 Starting Background Sync...");
      LocalDB.instance.syncEverything().then((_) {
         debugPrint("✅ Background Sync Complete. Refreshing UI.");
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
      if (mounted) {
        setState(() {
          _lessons = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("⚠️ UI Read Error: $e");
    }
  }

  // 🔥 NEW: Calculate Streak AND Total Learned Words locally
  // 🔥 FIX: Calculates CONSECUTIVE days, not total days
  // 🔥 FIX: Improved Streak Calculation with Debugging
  Future<void> _calculateStreakAndStats() async {
    try {
      final db = await LocalDB.instance.database;

      // --- 1. GET ALL LOGS ---
      final result = await db.query(
        'attempt_logs',
        columns: ['attempted_at'],
        orderBy: 'attempted_at DESC',
      );

      if (result.isEmpty) {
        debugPrint("❌ No logs found in DB for streak.");
        if (mounted) setState(() => _streak = 0);
        return;
      }

      // --- 2. NORMALIZE DATES (Remove Time) ---
      // We convert everything to "YYYY-MM-DD" strings to ignore hours/minutes
      Set<String> uniqueDates = {};
      for (var row in result) {
        DateTime dt = DateTime.parse(row['attempted_at'] as String).toLocal();
        String dateKey = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
        uniqueDates.add(dateKey);
      }

      // Sort Newest -> Oldest (e.g., [2024-01-30, 2024-01-29, 2024-01-25])
      List<String> sortedDates = uniqueDates.toList()..sort((a, b) => b.compareTo(a));

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
              const Text("🔥 Quick Stats", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildPopupStat("Day Streak", "$_streak", Colors.orange, Icons.local_fire_department),
                  Container(width: 1, height: 50, color: Colors.grey.shade800),
                  _buildPopupStat("Words Learned", "$_totalLearnedWords", AppColors.success, Icons.school),
                ],
              ),
              const SizedBox(height: 24),
              const Text("Keep going! Consistency is key.", style: TextStyle(color: Colors.grey, fontSize: 14)),
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Learn"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Stats"),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: "Library"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildLearnView() {
  return Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(icon: const Icon(Icons.library_books, color: AppColors.primary), onPressed: () {}),
      title: Column(
        children: const [
          Text("Español A1", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          Text("Beginner Course", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: _showStreakDetails,
          child: Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("$_streak", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(width: 4),
                const Text("🔥", style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _lessons.isEmpty
            ? const Center(child: Text("No Lessons Found", style: TextStyle(color: Colors.white)))
            : Column(
                children: [
                  const SizedBox(height: 5), // Shrunk from 10
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLanguageBtn("Esp -> Gr"),
                      const SizedBox(width: 12),
                      _buildLanguageBtn("Gr -> Esp"),
                    ],
                  ),
                  const SizedBox(height: 5), // Shrunk from 10
                  Expanded(
                    child: PageView.builder(
                      controller: PageController(viewportFraction: 0.85), // Slightly wider to feel less "cramped"
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
                  const SizedBox(height: 5), // Shrunk from 10
                  Container(
                    // Reduced vertical padding significantly
                    padding: const EdgeInsets.fromLTRB(20, 15, 20, 15), 
                    decoration: const BoxDecoration(
                      color: AppColors.cardColor,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("SELECT MODE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white54)),
                        const SizedBox(height: 12), // Shrunk from 15
                        Row(
                          children: [
                            _buildModeBtn("Game", Icons.sports_esports),
                            const SizedBox(width: 10),
                            _buildModeBtn("Test", Icons.quiz),
                            const SizedBox(width: 10),
                            _buildModeBtn("Survival", Icons.timer),
                          ],
                        ),
                        const SizedBox(height: 15), // Shrunk from 20
                        SizedBox(
                          width: double.infinity,
                          height: 48, // Reduced from 50
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              final selectedLesson = _lessons[_currentLessonIndex];
                              final bool isReversed = _selectedLanguage == 'Gr -> Esp';
                              Route? route;

                              if (_selectedMode == 'Game') {
                                route = MaterialPageRoute(builder: (context) => GameQuizPage(lessonId: selectedLesson.id, isReversed: isReversed));
                              } else if (_selectedMode == 'Test') {
                                route = MaterialPageRoute(builder: (context) => BubblePage(lessonId: selectedLesson.id, isReversed: isReversed));
                              } else if (_selectedMode == 'Survival') {
                                route = MaterialPageRoute(builder: (context) => SurvivalPage(lessonId: selectedLesson.id, isReversed: isReversed));
                              }

                              if (route != null) {
                                await Navigator.push(context, route);
                                SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                                _fetchDashboardData();
                                _calculateStreakAndStats();
                              }
                            },
                            child: const Text("START LESSON", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
  );
}

  Widget _buildLibraryView() => const Scaffold(backgroundColor: Colors.transparent, body: Center(child: Text("Library", style: TextStyle(color: Colors.white))));
  
  Widget _buildLanguageBtn(String label) {
    bool isSelected = _selectedLanguage == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedLanguage = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade700),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLessonCard(LessonData lesson, bool isActive) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 300, height: 400, 
        // Remove padding here so PageView fills the whole card
        decoration: BoxDecoration(
          gradient: isActive ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF2C2C2C), const Color(0xFF1E1E1E)]) : const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF1A1A1A)]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: isActive ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))] : [],
          border: Border.all(color: isActive ? AppColors.primary : Colors.grey.shade900, width: isActive ? 2 : 1),
        ),
        // ↕️ VERTICAL SCROLL ENABLED HERE ↕️
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
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
    int total = lesson.learned + lesson.learning + lesson.unseen;
    double progressPct = total == 0 ? 0.0 : (lesson.learned / total);
    double learningPct = total == 0 ? 0.0 : ((lesson.learned + lesson.learning) / total);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(children: [
            Text("Chapter ${lesson.chapter_number}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)), 
            const SizedBox(height: 8), 
            Text(lesson.title.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, letterSpacing: 1.3, fontWeight: FontWeight.bold, color: isActive ? AppColors.primary : Colors.grey))
          ]),
          SizedBox(
            height: 140, width: 140,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(value: 1.0, valueColor: AlwaysStoppedAnimation(Colors.grey.shade800), strokeWidth: 12),
                CircularProgressIndicator(value: learningPct, valueColor: AlwaysStoppedAnimation(AppColors.accent.withOpacity(0.5)), strokeWidth: 12),
                CircularProgressIndicator(value: progressPct, valueColor: const AlwaysStoppedAnimation(AppColors.primary), strokeWidth: 12, strokeCap: StrokeCap.round),
                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text("${(progressPct * 100).toInt()}%", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)), const Text("Mastered", style: TextStyle(fontSize: 12, color: Colors.grey))])),
              ],
            ),
          ),
          // Scroll Indicator
          Icon(Icons.keyboard_arrow_down, color: Colors.grey.withOpacity(0.5), size: 20),
          
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround, 
              children: [
                _buildStatItem(lesson.learned, "Mastered", AppColors.primary), 
                Container(width: 1, height: 24, color: Colors.grey.shade800), 
                _buildStatItem(lesson.learning, "Review", AppColors.accent), 
                Container(width: 1, height: 24, color: Colors.grey.shade800), 
                _buildStatItem(lesson.unseen, "New", Colors.grey)
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
    final labels = ["Late", "Tmrw", "+2d", "+3d", "+4d", "+5d", "+6d"];
    
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
            const Text("Upcoming Reviews", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)), 
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
  Widget _buildStatItem(int count, String label, Color color) { return Column(children: [Text("$count", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade400))]); }
  Widget _buildModeBtn(String label, IconData icon) {
  bool isSelected = _selectedMode == label;
  return Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _selectedMode = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10), // Slimmer padding
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade800),
        ),
        child: Row( // Row uses 50% less vertical space than Column
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.black : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label, 
              style: TextStyle(
                fontSize: 13, 
                color: isSelected ? Colors.black : Colors.grey, 
                fontWeight: FontWeight.bold
              )
            ),
          ],
        ),
      ),
    ),
  );
}}