import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:heroicons/heroicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../local_db.dart';
import '../responsive.dart';
import '../services/app_strings.dart';

// 🔥 1. ADD RIVERPOD IMPORTS
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'stats_provider.dart'; 

// 🔥 2. CHANGE TO CONSUMER STATEFUL WIDGET
class BubblePage extends ConsumerStatefulWidget {
  final int lessonId;
  final bool isReversed;
  final String sourceLanguage;

  const BubblePage({
    super.key,
    required this.lessonId,
    required this.isReversed,
    this.sourceLanguage = 'es',
  });

  @override
  ConsumerState<BubblePage> createState() => _BubblePageState();
}

class _BubblePageState extends ConsumerState<BubblePage> with TickerProviderStateMixin, WidgetsBindingObserver {
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

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  late final AnimationController _progressController;

  late final AnimationController _scoreController;
  late final Animation<double> _scoreBounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSessionData();

    // Pop animation - enhanced with spring curve
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _popController,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInBack,
    );

    // Sparkle explosion animation
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Shake animation for wrong answers
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn)
    );

    // Progress indicator animation
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Score bounce animation
    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scoreBounce = CurvedAnimation(
      parent: _scoreController,
      curve: Curves.elasticOut,
    );

    _flutterTts.setLanguage(widget.sourceLanguage == 'en' ? "en-US" : "es-ES");
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
    _shakeController.dispose();
    _progressController.dispose();
    _scoreController.dispose();
    _flutterTts.stop();
    _saveSessionToDB();
    super.dispose();
  }

  // In bubble.dart -> _saveSessionToDB()

  Future<void> _saveSessionToDB() async {
    if (_pendingUpdates.isEmpty) return;

    // ... (Your Learning Rate logic) ...

    List<Map<String, dynamic>> batchToSave = List.from(_pendingUpdates);
    _pendingUpdates.clear();
    
    // 1. SAVE ALL WORDS LOCALLY (Instant)
    for (var update in batchToSave) {
      // 👇 REPLACE THIS BLOCK
      await LocalDB.instance.updateProgressLocal(
        wordId: update['wordId'], 
        status: update['status'], 
        strength: update['strength'], 
        nextDue: update['nextDue'], 
        streak: update['streak'], 
        totalAttempts: update['totalAttempts'], 
        totalCorrect: update['totalCorrect'],
        isCorrect: update['isCorrect'],
      );
    }
    
    // 2. 🔥 NOW SYNC ONCE (Background)
    // This runs AFTER all words are safely in the SQLite DB.
    // We don't use 'await' so the UI doesn't freeze.
    LocalDB.instance.syncProgress().then((_) {
       // Optional: Update charts again after cloud confirms
       if (mounted) ref.invalidate(statsProvider);
    });

    // 3. Update UI immediately
    ref.invalidate(statsProvider); 
    LocalDB.instance.notifyDataChanged();
  }

  void _restartSession() async {
    setState(() {
      _isLoading = true;
      _currentIndex = 0;
      _sessionCorrect = 0;
      _sessionWrong = 0;
      _queue.clear();
      _pendingUpdates.clear();
    });

    await _loadSessionData();

    // If no words loaded, go back to main menu
    if (mounted && _queue.isEmpty) {
      Navigator.pop(context);
    }
  }

  Future<void> _loadSessionData() async {
    try {
      final db = await LocalDB.instance.database;
      final wordsData = await db.rawQuery('''
        SELECT w.* FROM lesson_words lw
        JOIN words w ON w.id = lw.word_id
        WHERE lw.lesson_id = ?
        ORDER BY w.id ASC
      ''', [widget.lessonId]);
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
      // Correct answer - sparkle explosion
      _sparkleController.reset();
      _sparkleController.forward();
      setState(() => _showSparkles = true);
    } else {
      // Wrong answer - shake animation
      _shakeController.reset();
      _shakeController.forward();
      HapticFeedback.vibrate();
    }

    // Animate score counter
    _scoreController.reset();
    _scoreController.forward();

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
      return {'front': S.finished, 'reveal': S.goodJob, 'word_id': 0};
    return _queue[_currentIndex];
  }

  Future<void> _speak() async {
    String text = widget.isReversed ? currentItem['reveal'] : currentItem['front'];
    if (text.isNotEmpty && text != S.finished) await _flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));

    // --- FINISHED SCREEN ---
    if (_currentIndex >= _queue.length) {
      final accuracy = _sessionCorrect + _sessionWrong > 0
          ? (_sessionCorrect / (_sessionCorrect + _sessionWrong) * 100).round()
          : 0;

      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            const Positioned.fill(child: BubbleBathBackground()),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success icon with animation
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success.withOpacity(0.2),
                            border: Border.all(color: AppColors.success, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withOpacity(0.3),
                                blurRadius: 30,
                                spreadRadius: 10,
                              )
                            ],
                          ),
                          child: const HeroIcon(
                            HeroIcons.checkCircle,
                            color: AppColors.success,
                            size: 80,
                            style: HeroIconStyle.solid,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  Text(
                    S.sessionComplete,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatCard(S.correct, _sessionCorrect, AppColors.success),
                      const SizedBox(width: 20),
                      _buildStatCard(S.review, _sessionWrong, Colors.redAccent),
                      const SizedBox(width: 20),
                      _buildStatCard(S.accuracy, accuracy, AppColors.primary, suffix: "%"),
                    ],
                  ),

                  const SizedBox(height: 50),

                  // Continue button
                  SizedBox(
                    width: 220,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                        shadowColor: AppColors.primary.withOpacity(0.5),
                      ),
                      onPressed: _restartSession,
                      child: Text(
                        S.continueBtn,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const HeroIcon(HeroIcons.home, color: Colors.white70, style: HeroIconStyle.solid),
                    label: Text(
                      S.mainMenu,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                    _buildTarget(Alignment.topCenter, HeroIcons.checkCircle, AppColors.success, isUp ? progress : 0.0),
                    _buildTarget(Alignment.bottomCenter, HeroIcons.xCircle, Colors.redAccent, isDown ? progress : 0.0),
                    
                    // Sound Button (Top Left)
                    Builder(
                      builder: (context) {
                        final r = Responsive(context);
                        return Positioned(
                          top: r.spacing(20),
                          left: r.spacing(20),
                          child: FloatingActionButton.small(
                            heroTag: "speak",
                            backgroundColor: AppColors.primary,
                            elevation: 4,
                            onPressed: _speak,
                            child: HeroIcon(HeroIcons.speakerWave, color: Colors.black, size: r.iconSize(24), style: HeroIconStyle.solid),
                          ),
                        );
                      }
                    ),

                    // Close Button (Top Right)
                    Builder(
                      builder: (context) {
                        final r = Responsive(context);
                        return Positioned(
                          top: r.spacing(20),
                          right: r.spacing(20),
                          child: FloatingActionButton.small(
                            heroTag: "close",
                            backgroundColor: AppColors.cardColor,
                            elevation: 0,
                            onPressed: () => Navigator.pop(context),
                            child: HeroIcon(HeroIcons.xMark, color: Colors.white, size: r.iconSize(24), style: HeroIconStyle.outline)
                          )
                        );
                      }
                    ),

                    // ✅ SCORES AT BOTTOM
                    // Bottom Left: Correct Score
                    Builder(
                      builder: (context) {
                        final r = Responsive(context);
                        return Positioned(
                          bottom: r.spacing(40),
                          left: r.spacing(30),
                          child: _buildScore(S.correct, _sessionCorrect, AppColors.success)
                        );
                      }
                    ),

                    // Bottom Right: Review (Wrong) Score
                    Builder(
                      builder: (context) {
                        final r = Responsive(context);
                        return Positioned(
                          bottom: r.spacing(40),
                          right: r.spacing(30),
                          child: _buildScore(S.review, _sessionWrong, Colors.redAccent),
                        );
                      }
                    ),

                    // --- THE GLASS BUBBLE ---
                    // Shifted up ~40px for optical center (eye perceives true center as too low)
                    Positioned.fill(
                      child: Align(
                        alignment: const Alignment(0.0, -0.25),
                      child: AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          // Shake effect (sin wave for horizontal shake)
                          final shake = math.sin(_shakeAnimation.value * math.pi * 8) * 15 * (1 - _shakeAnimation.value);

                          return Transform.translate(
                            offset: Offset(shake, _dragDistance),
                            child: Transform.rotate(
                              angle: (_dragDistance * 0.001),
                              child: ScaleTransition(
                                scale: _scaleAnimation,
                                child: Transform.scale(
                                  scale: _isDragging ? 1.08 : 1.0,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Circular progress indicator
                                      if (_isDragging && progress > 0)
                                        Builder(
                                          builder: (context) {
                                            final r = Responsive(context);
                                            final progressSize = r.bubbleSize + r.scale(20);
                                            return SizedBox(
                                              width: progressSize,
                                              height: progressSize,
                                              child: CircularProgressIndicator(
                                                value: progress,
                                                strokeWidth: r.scale(6).clamp(4, 8),
                                                backgroundColor: Colors.white.withOpacity(0.1),
                                                valueColor: AlwaysStoppedAnimation<Color>(glowColor),
                                              ),
                                            );
                                          }
                                        ),

                                      // The bubble
                                      _buildGlassBubble(
                                        text: displayedText,
                                        glowColor: glowColor,
                                        borderColor: borderColor,
                                        progress: progress,
                                        isUp: isUp,
                                        isDown: isDown,
                                      ),

                                      // Streak badge outside the bubble (bottom)
                                      if ((currentItem['status'] ?? 'new') == 'learning'
                                          && (currentItem['streak'] ?? 0) > 0
                                          && !_isDragging)
                                        Builder(
                                          builder: (context) {
                                            final r = Responsive(context);
                                            return Positioned(
                                              bottom: -r.scale(16),
                                              child: Container(
                                                padding: r.padding(horizontal: 14, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: AppColors.cardColor,
                                                  borderRadius: BorderRadius.circular(r.radius(20)),
                                                  border: Border.all(
                                                    color: AppColors.primary,
                                                    width: 2,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.primary.withOpacity(0.4),
                                                      blurRadius: 12,
                                                      spreadRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    HeroIcon(
                                                      HeroIcons.fire,
                                                      color: Colors.orange,
                                                      size: r.iconSize(18),
                                                      style: HeroIconStyle.solid,
                                                    ),
                                                    r.gapW(4),
                                                    Text(
                                                      '${currentItem['streak']}/3',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: r.fontSize(14),
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),  // Align
                    ),  // Positioned.fill

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
    final r = Responsive(context);
    final bubbleSize = r.bubbleSize;

    return Container(
      width: bubbleSize,
      height: bubbleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          // Outer glow when dragging
          if (progress > 0.05)
            BoxShadow(
              color: glowColor.withOpacity(0.5 * progress),
              blurRadius: 40 + (30 * progress),
              spreadRadius: 10 + (15 * progress),
            ),
          // Main shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
          // Inner highlight
          BoxShadow(
            color: Colors.white.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(-5, -5),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: 1.2,
                colors: [
                  Colors.white.withOpacity(0.25),
                  AppColors.primary.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.6, 1.0],
              ),
              border: Border.all(
                color: borderColor,
                width: 2.5,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(left: r.scale(20), right: r.scale(20), bottom: r.scale(14)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bubbleSize * 0.75),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: r.fontSize(_isDragging ? 36 : 32),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                        if (progress > 0.3)
                          Shadow(
                            color: glowColor.withOpacity(0.5),
                            blurRadius: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTarget(Alignment align, HeroIcons icon, Color color, double opacity) {
    final r = Responsive(context);
    return Align(
      alignment: align,
      child: Padding(
        padding: r.padding(all: 80),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          opacity: opacity,
          child: Transform.scale(
            scale: 0.5 + (opacity * 0.8),
            child: Container(
              padding: r.padding(all: 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.1 * opacity),
                border: Border.all(
                  color: color.withOpacity(0.5 * opacity),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3 * opacity),
                    blurRadius: 30,
                    spreadRadius: 10,
                  )
                ],
              ),
              child: HeroIcon(
                icon,
                color: color,
                size: r.iconSize(60),
                style: HeroIconStyle.solid,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int value, Color color, {String suffix = ""}) {
    final r = Responsive(context);
    return Container(
      padding: r.padding(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(r.radius(16)),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: r.fontSize(11),
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade400,
              letterSpacing: 1.0,
            ),
          ),
          r.gapH(8),
          Text(
            "$value$suffix",
            style: TextStyle(
              fontSize: r.fontSize(28),
              fontWeight: FontWeight.w900,
              color: color,
              shadows: [
                Shadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 8,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScore(String label, int score, Color color) {
    final r = Responsive(context);
    return ScaleTransition(
      scale: _scoreBounce,
      child: Container(
        padding: r.padding(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(r.radius(12)),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: r.fontSize(10),
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade400,
                letterSpacing: 1.2,
              ),
            ),
            r.gapH(4),
            Text(
              "$score",
              style: TextStyle(
                fontSize: r.fontSize(36),
                fontWeight: FontWeight.w900,
                color: color,
                shadows: [
                  Shadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 8,
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BubbleBathBackground extends StatefulWidget {
  const BubbleBathBackground({super.key});

  @override
  State<BubbleBathBackground> createState() => _BubbleBathBackgroundState();
}

class _BubbleBathBackgroundState extends State<BubbleBathBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_FloatingBubble> _bubbles = [];
  final math.Random _rng = math.Random();
  int _spawnCounter = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_tick)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spawnBubble(Size size) {
    final bubbleRadius = 8.0 + _rng.nextDouble() * 28;
    _bubbles.add(_FloatingBubble(
      x: _rng.nextDouble() * size.width,
      y: size.height + bubbleRadius,
      radius: bubbleRadius,
      speed: 1.0 + _rng.nextDouble() * 1.5,
      wobbleSpeed: 0.5 + _rng.nextDouble() * 1.5,
      opacity: 0.15 + _rng.nextDouble() * 0.4,
      color: _rng.nextBool()
          ? AppColors.primary
          : Color.lerp(AppColors.primary, AppColors.accent, _rng.nextDouble())!,
      phase: _rng.nextDouble() * math.pi * 2,
      popAt: 0.1 + _rng.nextDouble() * 0.5,
      popped: false,
      popProgress: 0.0,
      birthTime: DateTime.now(),
    ));
  }

  void _tick() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final now = DateTime.now();

    // Spawn new bubbles periodically
    _spawnCounter++;
    if (_spawnCounter % 8 == 0 && _bubbles.length < 30) {
      _spawnBubble(size);
    }

    // Seed initial bubbles
    if (_bubbles.isEmpty) {
      for (int i = 0; i < 15; i++) {
        final b = _FloatingBubble(
          x: _rng.nextDouble() * size.width,
          y: _rng.nextDouble() * size.height,
          radius: 8.0 + _rng.nextDouble() * 28,
          speed: 1.0 + _rng.nextDouble() * 1.5,
          wobbleSpeed: 0.5 + _rng.nextDouble() * 1.5,
          opacity: 0.15 + _rng.nextDouble() * 0.4,
          color: _rng.nextBool()
              ? AppColors.primary
              : Color.lerp(AppColors.primary, AppColors.accent, _rng.nextDouble())!,
          phase: _rng.nextDouble() * math.pi * 2,
          popAt: 0.1 + _rng.nextDouble() * 0.5,
          popped: false,
          popProgress: 0.0,
          birthTime: now.subtract(Duration(milliseconds: _rng.nextInt(3000))),
        );
        _bubbles.add(b);
      }
    }

    setState(() {
      for (int i = _bubbles.length - 1; i >= 0; i--) {
        final b = _bubbles[i];
        final age = now.difference(b.birthTime).inMilliseconds / 1000.0;

        if (b.popped) {
          b.popProgress += 0.06;
          if (b.popProgress >= 1.0) {
            _bubbles.removeAt(i);
            continue;
          }
        } else {
          b.y -= b.speed;
          b.x += math.sin(age * b.wobbleSpeed + b.phase) * 0.8;

          if (b.y < size.height * b.popAt) {
            b.popped = true;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FloatingBubblePainter(_bubbles),
      size: Size.infinite,
    );
  }
}

class _FloatingBubble {
  double x, y, radius, speed, wobbleSpeed, opacity;
  double popAt, popProgress, phase;
  Color color;
  bool popped;
  DateTime birthTime;

  _FloatingBubble({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.wobbleSpeed,
    required this.opacity,
    required this.color,
    required this.phase,
    required this.popAt,
    required this.popped,
    required this.popProgress,
    required this.birthTime,
  });
}

class _FloatingBubblePainter extends CustomPainter {
  final List<_FloatingBubble> bubbles;
  _FloatingBubblePainter(this.bubbles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      if (b.popped) {
        _drawPop(canvas, b);
      } else {
        _drawBubble(canvas, b);
      }
    }
  }

  void _drawBubble(Canvas canvas, _FloatingBubble b) {
    final paint = Paint()
      ..color = b.color.withOpacity(b.opacity * 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(b.x, b.y), b.radius, paint);

    final ringPaint = Paint()
      ..color = b.color.withOpacity(b.opacity * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(b.x, b.y), b.radius, ringPaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(b.opacity * 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(b.x - b.radius * 0.3, b.y - b.radius * 0.3),
      b.radius * 0.2,
      highlightPaint,
    );
  }

  void _drawPop(Canvas canvas, _FloatingBubble b) {
    final t = b.popProgress;
    final expandRadius = b.radius * (1.0 + t * 1.5);
    final opacity = b.opacity * (1.0 - t);

    final ringPaint = Paint()
      ..color = b.color.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * (1.0 - t);
    canvas.drawCircle(Offset(b.x, b.y), expandRadius, ringPaint);

    final particlePaint = Paint()
      ..color = b.color.withOpacity(opacity * 0.8)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * math.pi * 2;
      final dist = b.radius * (0.5 + t * 2.0);
      final px = b.x + math.cos(angle) * dist;
      final py = b.y + math.sin(angle) * dist;
      final particleSize = (b.radius * 0.15) * (1.0 - t);
      canvas.drawCircle(Offset(px, py), particleSize, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
          children: [
            // Main sparkle particles
            ...List.generate(50, (index) {
              final random = math.Random(index);
              final double direction = random.nextDouble() * 2 * math.pi;

              // Easing curve for more natural movement
              final curvedValue = Curves.easeOut.transform(controller.value);
              final double distance = random.nextDouble() * 500 * curvedValue;
              final double size = (random.nextDouble() * 12 + 4) * (1 - controller.value);

              final colors = [
                AppColors.primary,
                Colors.white,
                Colors.amber,
                const Color(0xFFFFD700), // Gold
                const Color(0xFFFFA500), // Orange
              ];
              final Color color = colors[random.nextInt(colors.length)];

              return Positioned(
                left: MediaQuery.of(context).size.width / 2 + (math.cos(direction) * distance) - (size / 2),
                top: MediaQuery.of(context).size.height / 2 + (math.sin(direction) * distance) - (size / 2),
                child: Opacity(
                  opacity: (1 - controller.value * 0.8).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: controller.value * math.pi * 4,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            color,
                            color.withOpacity(0.5),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            // Bright flash at the center
            if (controller.value < 0.3)
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 200 * (1 - controller.value * 3),
                    height: 200 * (1 - controller.value * 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.4 * (1 - controller.value * 3)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}