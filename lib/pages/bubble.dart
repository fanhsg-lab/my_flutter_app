import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../local_db.dart'; 

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

class _BubblePageState extends State<BubblePage> with TickerProviderStateMixin, WidgetsBindingObserver { 
  List<Map<String, dynamic>> _queue = [];
  final List<Map<String, dynamic>> _pendingUpdates = [];

  bool _isLoading = true;
  double _userLearningRate = 2.5;
  
  final FlutterTts _flutterTts = FlutterTts();

  int _currentIndex = 0;
  int _sessionCorrect = 0;
  int _sessionWrong = 0;

  double _dragDistance = 0.0;
  final double _triggerThreshold = 150.0;
  bool _isDragging = false;

  late final AnimationController _popController;
  late final Animation<double> _scaleAnimation;
  
  late final AnimationController _sparkleController;
  bool _showSparkles = false;

  @override
  void initState() {
    super.initState();
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

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _flutterTts.setLanguage("es-ES");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveSessionToDB();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _popController.dispose();
    _sparkleController.dispose();   
    _flutterTts.stop();
    _saveSessionToDB();
    super.dispose();
  }

  Future<void> _saveSessionToDB() async {
    if (_pendingUpdates.isEmpty) return;

    try {
       int batchCorrect = _pendingUpdates.where((u) => u['isCorrect'] == true).length;
       double accuracy = _pendingUpdates.length > 0 ? batchCorrect / _pendingUpdates.length : 0.0;
       
       if (accuracy >= 0.8) _userLearningRate = (_userLearningRate + 0.05).clamp(1.5, 3.5);
       else if (accuracy <= 0.6) _userLearningRate = (_userLearningRate - 0.05).clamp(1.5, 3.5);

       Supabase.instance.client.from('profiles').upsert({
         'id': Supabase.instance.client.auth.currentUser?.id,
         'learning_rate': _userLearningRate
       });
    } catch (e) { }

    List<Map<String, dynamic>> batchToSave = List.from(_pendingUpdates);
    _pendingUpdates.clear();
    
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
    LocalDB.instance.notifyDataChanged();
  }

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
      final db = await LocalDB.instance.database;
      final wordsData = await db.query('words', where: 'lesson_id = ?', whereArgs: [widget.lessonId]);
      final progressData = await db.query('user_progress');
      Map<int, Map<String, dynamic>> progressMap = { for (var p in progressData) p['word_id'] as int: p };

      List<Map<String, dynamic>> reviewQueue = []; 
      List<Map<String, dynamic>> learningQueue = []; 
      List<Map<String, dynamic>> newQueue = []; 
      DateTime now = DateTime.now().toUtc();

      for (var word in wordsData) {
        int wordId = word['id'] as int;
        var progress = progressMap[wordId];
        String status = progress?['status'] as String? ?? 'new';
        DateTime? nextDue = progress?['next_due_at'] != null ? DateTime.parse(progress!['next_due_at'] as String).toUtc() : null;
        bool isTimeUp = nextDue == null || nextDue.isBefore(now);

        Map<String, dynamic> item = {
          'word_id': wordId,
          'front': widget.isReversed ? (word['en'] as String) : (word['es'] as String),
          'reveal': widget.isReversed ? (word['es'] as String) : (word['en'] as String),
          'status': status,
          'strength': (progress?['strength'] as num?)?.toDouble() ?? 0.0,
          'next_due': nextDue,
          'streak': progress?['consecutive_correct'] ?? 0,
          'total_attempts': progress?['total_attempts'] ?? 0,
          'total_correct': progress?['total_correct'] ?? 0,
        };

        if (status == 'learning') learningQueue.add(item);
        else if ((status == 'consolidating' || status == 'learned') && isTimeUp) reviewQueue.add(item);
        else if (status == 'new' || progress == null) newQueue.add(item);
      }

      List<Map<String, dynamic>> finalSelection = [];
      while (finalSelection.length < 8 && reviewQueue.isNotEmpty) finalSelection.add(reviewQueue.removeAt(0));
      while (finalSelection.length < 10 && learningQueue.isNotEmpty) finalSelection.add(learningQueue.removeAt(0));
      while (finalSelection.length < 10 && newQueue.isNotEmpty) finalSelection.add(newQueue.removeAt(0));
      while (finalSelection.length < 10 && reviewQueue.isNotEmpty) finalSelection.add(reviewQueue.removeAt(0));

      finalSelection.shuffle();

      if (mounted) setState(() { _queue = finalSelection; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processResult(bool isCorrect) {
    final currentItem = _queue[_currentIndex];
    int totalAttempts = (currentItem['total_attempts'] ?? 0) + 1;
    int totalCorrect = (currentItem['total_correct'] ?? 0) + (isCorrect ? 1 : 0);
    String status = currentItem['status'];
    double strength = (currentItem['strength'] as num).toDouble();
    int streak = currentItem['streak'];
    DateTime now = DateTime.now().toUtc();
    DateTime nextDueAt = now;

    if (status == 'new') { status = 'learning'; strength = 0.0; }

    if (isCorrect) {
      if (status == 'learning') {
        streak++;
        if (streak >= 3) {
          status = 'consolidating';
          double efficiency = math.sqrt(3 / totalAttempts);
          double rewardFloat = 10.0 + (20.0 * efficiency);
          nextDueAt = now.add(Duration(minutes: rewardFloat.round()));
          strength = rewardFloat.round() / 1440.0;
        } 
      } else {
        streak = 0;
        strength = strength * _userLearningRate;
        if (strength < 0.003) strength = 0.003;
        if (strength > 5.0 && status == 'consolidating') status = 'learned';
        nextDueAt = now.add(Duration(minutes: (strength * 1440).round()));
      }
    } else {
      if (status == 'learning') { streak = 0; } 
      else {
        strength = strength * 0.5;
        if (strength < 0.005) { status = 'learning'; streak = 0; strength = 0.0; } 
        else { status = 'consolidating'; nextDueAt = now.add(const Duration(minutes: 10)); }
      }
    }

    setState(() {
      if (isCorrect) _sessionCorrect++; else _sessionWrong++;
      currentItem['streak'] = streak;
      currentItem['status'] = status;
      currentItem['strength'] = strength;
      currentItem['total_attempts'] = totalAttempts;
      currentItem['total_correct'] = totalCorrect;
    });

    _pendingUpdates.add({
      'wordId': currentItem['word_id'], 'status': status, 'strength': strength,
      'nextDue': nextDueAt, 'streak': streak, 'totalAttempts': totalAttempts,
      'totalCorrect': totalCorrect, 'isCorrect': isCorrect,
    });
  }

  void _handleAction({required bool isUp}) async {
    HapticFeedback.heavyImpact();
    if (isUp) {
       _sparkleController.reset();
       _sparkleController.forward();
       setState(() => _showSparkles = true);
    }

    _processResult(isUp);
    await _popController.reverse();
    if (mounted) {
      setState(() {
        _currentIndex++;
        _dragDistance = 0.0;
        _isDragging = false;
        _showSparkles = false;
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
    String text = widget.isReversed ? currentItem['reveal'] : currentItem['front'];
    if (text.isNotEmpty && text != 'Finished!') await _flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));

    // --- FINISHED SCREEN ---
    if (_currentIndex >= _queue.length) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 80),
              const SizedBox(height: 20),
              const Text("Session Complete!", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              Text("Correct: $_sessionCorrect  |  Review: $_sessionWrong", style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 50),
              SizedBox(
                width: 200, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _restartSession,
                  child: const Text("CONTINUE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.home, color: Colors.white70), label: const Text("Main Menu", style: TextStyle(color: Colors.white70))),
            ],
          ),
        ),
      );
    }

    // --- MAIN GAME ---
    double progress = (_dragDistance.abs() / _triggerThreshold).clamp(0.0, 1.0);
    bool isUp = _dragDistance < 0;
    bool isDown = _dragDistance > 0;
    String displayedText = _isDragging ? currentItem['reveal'] : currentItem['front'];
    
    Color glowColor = isUp 
      ? AppColors.success 
      : (isDown ? Colors.redAccent : Colors.transparent);
      
    Color borderColor = Color.lerp(
      Colors.white.withOpacity(0.3), 
      glowColor.withOpacity(0.8), 
      progress
    )!;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Full Screen Gesture Detector
      body: GestureDetector(
        behavior: HitTestBehavior.translucent, 
        onPanStart: (_) {
          HapticFeedback.selectionClick();
          setState(() => _isDragging = true);
        },
        onPanUpdate: (details) {
          setState(() => _dragDistance += details.delta.dy);
        },
        onPanEnd: (_) {
          if (_dragDistance <= -_triggerThreshold) _handleAction(isUp: true);
          else if (_dragDistance >= _triggerThreshold) _handleAction(isUp: false);
          else setState(() { _dragDistance = 0.0; _isDragging = false; });
        },
        child: Stack(
          children: [
             const Positioned.fill(child: BubbleBathBackground()),

             SafeArea(
               child: Stack(
                 children: [
                    // Targets
                    _buildTarget(Alignment.topCenter, Icons.check_circle, AppColors.success, isUp ? progress : 0.0),
                    _buildTarget(Alignment.bottomCenter, Icons.cancel, Colors.redAccent, isDown ? progress : 0.0),
                    
                    // Sound Button (Top Left)
                    Positioned(
                      top: 20, 
                      left: 20,
                      child: FloatingActionButton.small(
                        heroTag: "speak",
                        backgroundColor: AppColors.primary,
                        elevation: 4,
                        onPressed: _speak,
                        child: const Icon(Icons.volume_up_rounded, color: Colors.black),
                      ),
                    ),

                    // Close Button (Top Right)
                    Positioned(
                      top: 20, 
                      right: 20, 
                      child: FloatingActionButton.small(
                        heroTag: "close", 
                        backgroundColor: AppColors.cardColor, 
                        elevation: 0,
                        onPressed: () => Navigator.pop(context), 
                        child: const Icon(Icons.close, color: Colors.white)
                      )
                    ),

                    // ✅ SCORES AT BOTTOM
                    // Bottom Left: Correct Score
                    Positioned(
                      bottom: 40, 
                      left: 30, 
                      child: _buildScore("CORRECT", _sessionCorrect, AppColors.success)
                    ),

                    // Bottom Right: Review (Wrong) Score (Replaces "Remaining")
                    Positioned(
                      bottom: 40,
                      right: 30,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("REVIEW", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text("$_sessionWrong", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.redAccent)),
                        ],
                      ),
                    ),

                    // --- THE GLASS BUBBLE ---
                    Center(
                      child: Transform.translate(
                        offset: Offset(0, _dragDistance), 
                        child: Transform.rotate(
                          angle: (_dragDistance * 0.001), 
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Transform.scale(
                              scale: _isDragging ? 1.05 : 1.0, 
                              child: _buildGlassBubble(
                                text: displayedText, 
                                glowColor: glowColor, 
                                borderColor: borderColor, 
                                progress: progress,
                                isUp: isUp,
                                isDown: isDown
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Sparkles (Overlay)
                    if (_showSparkles)
                      Positioned.fill(child: SparkleExplosion(controller: _sparkleController)),
                 ],
               ),
             ),
          ],
        ),
      ),
    );
  }

  // Premium Frosted Glass Orb
  Widget _buildGlassBubble({
    required String text, 
    required Color glowColor, 
    required Color borderColor, 
    required double progress,
    required bool isUp, 
    required bool isDown
  }) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (progress > 0.05)
            BoxShadow(
              color: glowColor.withOpacity(0.4 * progress),
              blurRadius: 30 + (20 * progress),
              spreadRadius: 5 + (10 * progress),
            ),
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.2), 
                  Colors.white.withOpacity(0.05),
                ],
              ),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32, 
                      fontWeight: FontWeight.w700,
                      color: Colors.white, 
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))
                      ]
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: progress > 0.1 ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                   
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTarget(Alignment align, IconData icon, Color color, double opacity) {
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(80),
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(scale: 0.5 + opacity, child: Icon(icon, color: color, size: 80)),
        ),
      ),
    );
  }

  Widget _buildScore(String label, int score, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        Text("$score", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }
}

class BubbleBathBackground extends StatefulWidget {
  const BubbleBathBackground({super.key});

  @override
  State<BubbleBathBackground> createState() => _BubbleBathBackgroundState();
}

class _BubbleBathBackgroundState extends State<BubbleBathBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_BackgroundBubble> _bubbles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
    for (int i = 0; i < 25; i++) {
      _bubbles.add(_BackgroundBubble(_random));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
             final height = constraints.maxHeight;
             final width = constraints.maxWidth;
             return Stack(
               children: _bubbles.map((bubble) {
                 double movement = _controller.value * bubble.speed * height * 4; 
                 double y = (bubble.startY - movement) % (height + 200); 
                 if (y < -100) y = height + 100;

                 return Positioned(
                   left: bubble.xRatio * width,
                   top: y - 100,
                   child: Opacity(
                     opacity: bubble.opacity,
                     child: Container(
                       width: bubble.size,
                       height: bubble.size,
                       decoration: BoxDecoration(
                         shape: BoxShape.circle,
                         gradient: LinearGradient(
                           begin: Alignment.bottomLeft, end: Alignment.topRight,
                           colors: [Colors.white.withOpacity(0.05), AppColors.primary.withOpacity(0.1)]
                         ),
                         border: Border.all(color: Colors.white.withOpacity(0.05), width: 1)
                       ),
                     ),
                   ),
                 );
               }).toList(),
             );
          }
        );
      },
    );
  }
}

class _BackgroundBubble {
  late double xRatio;
  late double startY;
  late double size;
  late double speed;
  late double opacity;

  _BackgroundBubble(math.Random random) {
    xRatio = random.nextDouble(); 
    startY = random.nextDouble() * 2000; 
    size = random.nextDouble() * 40 + 10; 
    speed = random.nextDouble() * 0.5 + 0.2; 
    opacity = random.nextDouble() * 0.3 + 0.1;
  }
}

class SparkleExplosion extends StatelessWidget {
  final AnimationController controller;
  const SparkleExplosion({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Stack(
          children: List.generate(30, (index) { 
            final random = math.Random(index);
            final double direction = random.nextDouble() * 2 * math.pi; 
            final double distance = random.nextDouble() * 400 * controller.value; 
            final double size = random.nextDouble() * 10 * (1 - controller.value);
            final Color color = [AppColors.primary, Colors.white, Colors.amber][random.nextInt(3)];
            
            return Positioned(
              left: MediaQuery.of(context).size.width / 2 + (math.cos(direction) * distance) - (size/2),
              top: MediaQuery.of(context).size.height / 2 + (math.sin(direction) * distance) - (size/2), 
              child: Opacity(
                opacity: (1 - controller.value).clamp(0.0, 1.0),
                child: Container(
                  width: size, height: size,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.8), blurRadius: 5)]),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}