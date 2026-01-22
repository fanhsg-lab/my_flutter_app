import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 1. Need this for orientation control
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart'; 
import '../local_db.dart'; 
import 'gameMode.dart'; 
import 'bubble.dart'; 
import 'statistics.dart'; 
import 'profile.dart'; 

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _streak = 0;
  int _currentLessonIndex = 0;
  String _selectedMode = 'Test'; 
  String _selectedLanguage = 'Gr -> Esp'; 
  int _bottomNavIndex = 0; 
  bool _isLoading = true;
  List<LessonData> _lessons = [];

  @override
  void initState() {
    super.initState();
    
    // 🚨 2. LOCK TO VERTICAL (PORTRAIT)
    // This forces the screen to rotate back instantly when you return from the game.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _initialLoad();
  }

  Future<void> _initialLoad() async {
    await _fetchDashboardData();

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
         if (mounted) _fetchDashboardData();
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
      debugPrint("⚠️ UI Read Error (DB Locked?): $e");
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _lessons.isEmpty
              ? const Center(child: Text("No Lessons Found", style: TextStyle(color: Colors.white)))
              : Column(
                  children: [
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLanguageBtn("Esp -> Gr"),
                        const SizedBox(width: 12),
                        _buildLanguageBtn("Gr -> Esp"),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: PageView.builder(
                        controller: PageController(viewportFraction: 0.8),
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
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
                      decoration: const BoxDecoration(
                        color: AppColors.cardColor,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Select Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white70)),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              _buildModeBtn("Game", Icons.sports_esports),
                              const SizedBox(width: 10),
                              _buildModeBtn("Test", Icons.quiz),
                              const SizedBox(width: 10),
                              _buildModeBtn("Survival", Icons.timer),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () async {
                                final selectedLesson = _lessons[_currentLessonIndex];
                                final bool isReversed = _selectedLanguage == 'Gr -> Esp';
                                Route? route;

                                if (_selectedMode == 'Game') {
                                  route = MaterialPageRoute(
                                    builder: (context) => GameQuizPage(lessonId: selectedLesson.id, isReversed: isReversed)
                                  );
                                } else if (_selectedMode == 'Test') {
                                  route = MaterialPageRoute(
                                    builder: (context) => BubblePage(lessonId: selectedLesson.id, isReversed: isReversed)
                                  );
                                }

                                if (route != null) {
                                  await Navigator.push(context, route);
                                  
                                  // 🚨 3. RE-LOCK WHEN COMING BACK
                                  // Just in case the game unlocked it, we lock it again here.
                                  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                                  
                                  _fetchDashboardData();
                                }
                              },
                              child: const Text("START LESSON", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
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
    int total = lesson.learned + lesson.learning + lesson.unseen;
    double progressPct = total == 0 ? 0.0 : (lesson.learned / total);
    double learningPct = total == 0 ? 0.0 : ((lesson.learned + lesson.learning) / total);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 300, height: 400, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        decoration: BoxDecoration(
          gradient: isActive ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF2C2C2C), const Color(0xFF1E1E1E)]) : const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF1A1A1A)]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: isActive ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))] : [],
          border: Border.all(color: isActive ? AppColors.primary : Colors.grey.shade900, width: isActive ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(children: [Text("Chapter ${lesson.chapter_number}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 8), Text(lesson.title.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, letterSpacing: 1.3, fontWeight: FontWeight.bold, color: isActive ? AppColors.primary : Colors.grey))]),
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
      ),
    );
  }
  Widget _buildStatItem(int count, String label, Color color) { return Column(children: [Text("$count", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade400))]); }
  Widget _buildModeBtn(String label, IconData icon) { bool isSelected = _selectedMode == label; return Expanded(child: GestureDetector(onTap: () => setState(() => _selectedMode = label), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: isSelected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade800)), child: Column(children: [Icon(icon, color: isSelected ? Colors.black : Colors.grey), Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontWeight: FontWeight.bold))])))); }
}