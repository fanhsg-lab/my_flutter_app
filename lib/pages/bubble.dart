import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../local_db.dart'; // Required for Offline DB

class BubblePage extends StatefulWidget {
  final int lessonId;
  final bool isReversed;

  const BubblePage({
    super.key,
    required this.lessonId,
    required this.isReversed,
  });

  @override
  State<BubblePage> createState() => _BubblePageState();
}

// ✅ MIXIN ADDED: WidgetsBindingObserver (To detect app minimize/kill)
class _BubblePageState extends State<BubblePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> _queue = [];
  final List<Map<String, dynamic>> _pendingUpdates = [];

  bool _isLoading = true;
  double _userLearningRate = 2.5;
  double _userPenaltyRate = 0.5;

  final FlutterTts _flutterTts = FlutterTts();

  int _currentIndex = 0;
  int _sessionCorrect = 0;
  int _sessionWrong = 0;

  double _dragDistance = 0.0;
  final double _triggerThreshold = 150.0;
  bool _isDragging = false;

  late final AnimationController _popController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // ✅ REGISTER OBSERVER: Watch for app minimization
    WidgetsBinding.instance.addObserver(this);

    _loadSessionData();

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _popController,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeIn,
    );
    _flutterTts.setLanguage("es-ES");
  }

  // ✅ NEW: Detect if user minimizes the app (Home button / Switch apps)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      //debugPrint("⏸️ App paused/minimized. Saving progress...");
      _saveSessionToDB(); // Force Save
    }
  }

  // ✅ UPDATED DISPOSE: Save when user presses "Back"
  @override
  void dispose() {
    // Unregister observer
    WidgetsBinding.instance.removeObserver(this);

    _popController.dispose();
    _flutterTts.stop();

    // 💾 SAFETY SAVE: If they leave the screen, save whatever they did so far
    _saveSessionToDB();

    super.dispose();
  }

  // --- SAVE BATCH FUNCTION (Safe to call multiple times) ---
  Future<void> _saveSessionToDB() async {
    // If nothing to save, stop.
    if (_pendingUpdates.isEmpty) return;

    // 1. Report Card Logic (Optional: Adjusts difficulty)
    int batchCorrect = _pendingUpdates.where((u) => u['isCorrect'] == true).length;
    double accuracy = _pendingUpdates.length > 0 ? batchCorrect / _pendingUpdates.length : 0.0;
    
    if (accuracy >= 0.8) _userLearningRate = (_userLearningRate + 0.05).clamp(1.5, 3.5);
    else if (accuracy <= 0.6) _userLearningRate = (_userLearningRate - 0.05).clamp(1.5, 3.5);
    
    // Fire and forget profile update (Cloud only)
    try {
       Supabase.instance.client.from('profiles').upsert({
         'id': Supabase.instance.client.auth.currentUser?.id,
         'learning_rate': _userLearningRate
       });
    } catch (e) { /* ignore offline */ }

    // 2. SAVE USING YOUR LOCAL HELPER
    // Your 'updateProgressLocal' uses ConflictAlgorithm.replace, 
    // which automatically fixes the "New Lesson" bug.
    List<Map<String, dynamic>> batchToSave = List.from(_pendingUpdates);
    _pendingUpdates.clear();

    debugPrint("💾 Saving batch of ${batchToSave.length} updates...");
    
    for (var update in batchToSave) {
      await LocalDB.instance.updateProgressLocal(
        wordId: update['wordId'], 
        status: update['status'], 
        strength: update['strength'], 
        nextDue: update['nextDue'], 
        streak: update['streak'], 
        totalAttempts: update['totalAttempts'], 
        totalCorrect: update['totalCorrect'],
        isCorrect: update['isCorrect']
      );
    }
    debugPrint("🔔 Ringing the bell: Data changed!");
    LocalDB.instance.notifyDataChanged(); // <--- RINGS THE BELL

    debugPrint("✅ Batch save complete!");
  }

  // ... (Rest of your logic remains exactly the same) ...

  void _restartSession() {
    setState(() {
      _isLoading = true;
      _currentIndex = 0;
      _sessionCorrect = 0;
      _sessionWrong = 0;
      _queue.clear();
      _pendingUpdates.clear();
    });
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    try {
      //debugPrint("\n🔵 --- STARTING SESSION LOAD ---");
      final db = await LocalDB.instance.database;

      // 1. QUERY WORDS (Strict ID Sort for Stability)
      // This ensures we always process words in the same order (1, 2, 3...)
      final wordsData = await db.query(
        'words',
        where: 'lesson_id = ?',
        whereArgs: [widget.lessonId],
        orderBy: 'id ASC',
      );

      final progressData = await db.query('user_progress');
      Map<int, Map<String, dynamic>> progressMap = {
        for (var p in progressData) p['word_id'] as int: p,
      };

      // 2. CREATE SORTED BUCKETS
      List<Map<String, dynamic>> reviewQueue = []; // Ready Reviews
      List<Map<String, dynamic>> learningQueue = []; // Failed Words
      List<Map<String, dynamic>> newQueue = []; // Unseen Words

      DateTime now = DateTime.now().toUtc();

      for (var word in wordsData) {
        int wordId = word['id'] as int;
        var progress = progressMap[wordId];
        String status = progress?['status'] as String? ?? 'new';

        DateTime? nextDue = progress?['next_due_at'] != null
            ? DateTime.parse(progress!['next_due_at'] as String).toUtc()
            : null;
        bool isTimeUp = nextDue == null || nextDue.isBefore(now);

        Map<String, dynamic> item = {
          'word_id': wordId,
          'front': widget.isReversed
              ? (word['en'] as String)
              : (word['es'] as String),
          'reveal': widget.isReversed
              ? (word['es'] as String)
              : (word['en'] as String),
          'status': status,
          'strength': (progress?['strength'] as num?)?.toDouble() ?? 0.0,
          'next_due': nextDue,
          'streak': progress?['consecutive_correct'] ?? 0,
          'total_attempts': progress?['total_attempts'] ?? 0,
          'total_correct': progress?['total_correct'] ?? 0,
        };

        // Strict Sorting into Groups
        if (status == 'learning') {
          learningQueue.add(item);
        } else if ((status == 'consolidating' || status == 'learned') &&
            isTimeUp) {
          reviewQueue.add(item);
        } else if (status == 'new' || progress == null) {
          newQueue.add(item);
        }
      }

      // 3. BUILD THE QUIZ (The "Recipe")
      List<Map<String, dynamic>> finalSelection = [];

      // STEP A: Take Consolidating (Max 8)
      // We take them in ID order (or Date order if you preferred, but ID is stable)
      while (finalSelection.length < 8 && reviewQueue.isNotEmpty) {
        finalSelection.add(reviewQueue.removeAt(0));
      }

      // STEP B: Take Learning (Fill up to 10)
      // If we took 8 Reviews, this adds 2 Learning.
      // If we took 0 Reviews, this adds 10 Learning.
      while (finalSelection.length < 10 && learningQueue.isNotEmpty) {
        finalSelection.add(learningQueue.removeAt(0));
      }

      // STEP C: Take New (Fill up to 10)
      // Only happens if we ran out of both Reviews and Learning words.
      while (finalSelection.length < 10 && newQueue.isNotEmpty) {
        finalSelection.add(newQueue.removeAt(0));
      }

      // STEP D: Safety Backfill
      // If we are STILL short (e.g. 0 Learning, 0 New, but 20 Reviews available),
      // go back and grab more reviews to ensure a full quiz.
      while (finalSelection.length < 10 && reviewQueue.isNotEmpty) {
        finalSelection.add(reviewQueue.removeAt(0));
      }

      debugPrint("🏁 QUIZ GENERATED: ${finalSelection.length} words");
      debugPrint("   IDs: ${finalSelection.map((e) => e['word_id']).toList()}");

      // 4. SHUFFLE FINAL
      // Just shuffle the cards before dealing them to the user.
      finalSelection.shuffle();

      if (mounted)
        setState(() {
          _queue = finalSelection;
          _isLoading = false;
        });
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _calculatePValue(DateTime lastReview, double strength) {
    if (strength <= 0) return 1.0;
    final gapDays = DateTime.now().difference(lastReview).inMinutes / 1440.0;
    return 1.0 - exp(-(gapDays / strength));
  }

  void _processResult(bool isCorrect) {
    final currentItem = _queue[_currentIndex];
    int totalAttempts = (currentItem['total_attempts'] ?? 0) + 1;
    int totalCorrect =
        (currentItem['total_correct'] ?? 0) + (isCorrect ? 1 : 0);
    String status = currentItem['status'];
    double strength = (currentItem['strength'] as num).toDouble();
    int streak = currentItem['streak'];
    DateTime now = DateTime.now().toUtc();
    DateTime nextDueAt = now;

    if (status == 'new') {
      status = 'learning';
      strength = 0.0;
    }

    if (isCorrect) {
      if (status == 'learning') {
        streak++;
        if (streak >= 3) {
          status = 'consolidating';
          double efficiency = sqrt(3 / totalAttempts);
          double rewardFloat = 10.0 + (20.0 * efficiency);
          nextDueAt = now.add(Duration(minutes: rewardFloat.round()));
          strength = rewardFloat.round() / 1440.0;
        } else {
          nextDueAt = now;
        }
      } else {
        streak = 0;
        strength = strength * _userLearningRate;
        if (strength < 0.003) strength = 0.003;
        if (strength > 5.0 && status == 'consolidating') status = 'learned';
        nextDueAt = now.add(Duration(minutes: (strength * 1440).round()));
      }
    } else {
      if (status == 'learning') {
        streak = 0;
        nextDueAt = now;
      } else {
        strength = strength * 0.5;
        if (strength < 0.005) {
          status = 'learning';
          streak = 0;
          strength = 0.0;
          nextDueAt = now;
        } else {
          status = 'consolidating';
          nextDueAt = now.add(const Duration(minutes: 10));
        }
      }
    }

    setState(() {
      if (isCorrect)
        _sessionCorrect++;
      else
        _sessionWrong++;
      currentItem['streak'] = streak;
      currentItem['status'] = status;
      currentItem['strength'] = strength;
      currentItem['total_attempts'] = totalAttempts;
      currentItem['total_correct'] = totalCorrect;
    });

    _pendingUpdates.add({
      'wordId': currentItem['word_id'],
      'status': status,
      'strength': strength,
      'nextDue': nextDueAt,
      'streak': streak,
      'totalAttempts': totalAttempts,
      'totalCorrect': totalCorrect,
      'isCorrect': isCorrect,
    });
  }

  void _handleAction({required bool isUp}) async {
    HapticFeedback.heavyImpact();
    _processResult(isUp);
    await _popController.reverse();
    if (mounted) {
      setState(() {
        _currentIndex++;
        _dragDistance = 0.0;
        _isDragging = false;
      });
      _popController.forward();
      if (_currentIndex >= _queue.length) _saveSessionToDB();
    }
  }

  Map<String, dynamic> get currentItem {
    if (_queue.isEmpty || _currentIndex >= _queue.length)
      return {'front': 'Finished!', 'reveal': 'Good Job', 'word_id': 0};
    return _queue[_currentIndex];
  }

  Future<void> _speak() async {
    String text = widget.isReversed
        ? currentItem['reveal']
        : currentItem['front'];
    if (text.isNotEmpty && text != 'Finished!') await _flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );

    if (_currentIndex >= _queue.length) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.success,
                size: 80,
              ),
              const SizedBox(height: 20),
              const Text(
                "Session Complete!",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Correct: $_sessionCorrect  |  Review: $_sessionWrong",
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 50),
              SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _restartSession,
                  child: const Text(
                    "CONTINUE",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.home, color: Colors.white70),
                label: const Text(
                  "Main Menu",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      );
    }

    double progress = (_dragDistance.abs() / _triggerThreshold).clamp(0.0, 1.0);
    bool isUp = _dragDistance < 0;
    bool isDown = _dragDistance > 0;
    String displayedText = _isDragging
        ? currentItem['reveal']
        : currentItem['front'];
    Color bubbleColor = Color.lerp(
      AppColors.cardColor,
      isUp
          ? Colors.green.shade900
          : (isDown ? Colors.red.shade900 : AppColors.cardColor),
      progress,
    )!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            HapticFeedback.selectionClick();
            setState(() => _isDragging = true);
          },
          onPanUpdate: (details) {
            setState(() => _dragDistance += details.delta.dy);
          },
          onPanEnd: (_) {
            if (_dragDistance <= -_triggerThreshold)
              _handleAction(isUp: true);
            else if (_dragDistance >= _triggerThreshold)
              _handleAction(isUp: false);
            else
              setState(() {
                _dragDistance = 0.0;
                _isDragging = false;
              });
          },
          child: Stack(
            children: [
              _buildTarget(
                Alignment.topCenter,
                Icons.check_circle,
                AppColors.success,
                isUp ? progress : 0.0,
              ),
              _buildTarget(
                Alignment.bottomCenter,
                Icons.cancel,
                Colors.redAccent,
                isDown ? progress : 0.0,
              ),
              Positioned(
                top: 20,
                right: 30,
                child: _buildScore(
                  "Correct",
                  _sessionCorrect,
                  AppColors.success,
                ),
              ),
              Positioned(
                bottom: 20,
                right: 30,
                child: _buildScore("Review", _sessionWrong, Colors.redAccent),
              ),
              Positioned(
                top: 20,
                left: 20,
                child: FloatingActionButton.small(
                  heroTag: "close",
                  backgroundColor: AppColors.cardColor,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),

              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 50),
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          height: 240,
                          width: 240,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  (isUp
                                          ? AppColors.success
                                          : (isDown
                                                ? Colors.red
                                                : Colors.blueGrey))
                                      .withOpacity(0.5),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayedText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      FloatingActionButton(
                        heroTag: "speak",
                        backgroundColor: AppColors.cardColor,
                        elevation: 4,
                        onPressed: _speak,
                        child: const Icon(
                          Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTarget(
    Alignment align,
    IconData icon,
    Color color,
    double opacity,
  ) {
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(80),
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: 0.5 + opacity,
            child: Icon(icon, color: color, size: 80),
          ),
        ),
      ),
    );
  }

  Widget _buildScore(String label, int score, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        Text(
          "$score",
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}
