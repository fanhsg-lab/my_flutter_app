import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
import 'dart:async';
import '../local_db.dart';
import '../theme.dart';
import '../responsive.dart';
import '../services/app_strings.dart';

class GameQuizPage extends StatefulWidget {
  final int lessonId;
  final bool isReversed;
  final String sourceLanguage;

  const GameQuizPage({super.key, required this.lessonId, required this.isReversed, this.sourceLanguage = 'es'});

  @override
  State<GameQuizPage> createState() => _GameQuizPageState();
}

class _GameQuizPageState extends State<GameQuizPage> with TickerProviderStateMixin {

  List<Map<String, String>> _vocabulary = [];
  List<Map<String, String>> _wordQueue = []; // Shuffled queue to prevent repetition
  int _totalWordsInLesson = 0; // Track total words for progress
  bool _isLoading = true;
  bool _isSessionComplete = false;

  late Ticker _ticker;
  Size? _screenSize;
  List<GameBall> _balls = [];
  Map<String, String>? _targetWordPair;
  int _score = 0;
  final int _totalBalls = 6;
  double _ballRadius = 65.0; // Will be set responsively
  final math.Random _random = math.Random();

  bool _showFeedback = false;
  String _feedbackText = "";
  Timer? _feedbackTimer;

  // Animation controllers for enhanced effects
  late AnimationController _scoreAnimController;
  late Animation<double> _scoreScale;

  late AnimationController _feedbackAnimController;
  late Animation<double> _feedbackScale;

  int _combo = 0;
  List<ParticleEffect> _particles = [];
  String? _ballBeingRemoved;
  bool _showCycleComplete = false;
  Timer? _cycleCompleteTimer;

  @override
  void initState() {
    super.initState();
    // Force landscape and fullscreen immersive mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Initialize animation controllers
    _scoreAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scoreScale = CurvedAnimation(
      parent: _scoreAnimController,
      curve: Curves.elasticOut,
    );

    _feedbackAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _feedbackScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _feedbackAnimController, curve: Curves.easeOut),
    );

    _fetchLessonWords();

    _ticker = createTicker((elapsed) {
      if (_screenSize != null && !_isLoading && !_isSessionComplete && _vocabulary.isNotEmpty) {
        _updatePhysics();
        _updateParticles();
      }
    });
    _ticker.start();
  }

  // 1. FETCH WORDS FOR SPECIFIC LESSON
  Future<void> _fetchLessonWords() async {
    try {
      final db = await LocalDB.instance.database;
      final rawResponse = await db.rawQuery('''
        SELECT w.* FROM lesson_words lw
        JOIN words w ON w.id = lw.word_id
        WHERE lw.lesson_id = ?
        ORDER BY w.id ASC
      ''', [widget.lessonId]);

      List<Map<String, String>> loadedWords = [];

      for (var row in rawResponse) {
        String id = row['id'].toString();
        String es_val = (row['es'] ?? '').toString();
        String gr_val = (row['en'] ?? '').toString();

        if (es_val.isNotEmpty && gr_val.isNotEmpty) {
          if (widget.isReversed) {
            loadedWords.add({'id': id, 'question': gr_val, 'answer': es_val});
          } else {
            loadedWords.add({'id': id, 'question': es_val, 'answer': gr_val});
          }
        }
      }

      if (mounted) {
        setState(() {
          _vocabulary = loadedWords;
          _totalWordsInLesson = loadedWords.length;
          _shuffleWordQueue(); // Initialize shuffled queue
          _isLoading = false;
          if (_vocabulary.isEmpty) _isSessionComplete = true; // Handle empty lesson
        });
      }
    } catch (e) {
      debugPrint("Game Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _feedbackTimer?.cancel();
    _cycleCompleteTimer?.cancel();
    _scoreAnimController.dispose();
    _feedbackAnimController.dispose();
    // Restore portrait orientation and show system UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _initializeGame() {
    if (_balls.isNotEmpty || _vocabulary.isEmpty) return;
    _pickNewTarget();
    for (int i = 0; i < _totalBalls; i++) {
      _addNewBall(forceCorrectAnswer: i == 0);
    }
  }

  void _shuffleWordQueue() {
    // Create a shuffled copy of all vocabulary words
    _wordQueue = List.from(_vocabulary)..shuffle(_random);
  }

  void _pickNewTarget() {
    if (_vocabulary.isEmpty) return;

    // If queue is empty, reshuffle to start a new cycle
    if (_wordQueue.isEmpty) {
      _showCycleCompleteMessage();
      _shuffleWordQueue();
    }

    // Pick the next word from the queue
    setState(() {
      _targetWordPair = _wordQueue.removeAt(0);
    });
  }

  void _showCycleCompleteMessage() {
    _cycleCompleteTimer?.cancel();
    setState(() => _showCycleComplete = true);

    // Create celebration particles
    if (_screenSize != null) {
      for (int i = 0; i < 50; i++) {
        double angle = (i / 50) * 2 * math.pi;
        double speed = 4 + _random.nextDouble() * 6;
        _particles.add(ParticleEffect(
          position: Offset(_screenSize!.width / 2, _screenSize!.height / 2),
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: AppColors.primary,
          life: 1.5,
        ));
      }
    }

    _cycleCompleteTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _showCycleComplete = false);
    });
  }

  void _addNewBall({bool forceCorrectAnswer = false}) {
    if (_screenSize == null || _targetWordPair == null) return;
    if (_vocabulary.isEmpty) return;

    Set<String> activeWords = _balls.map((b) => b.wordPair['question']!).toSet();
    Map<String, String> wordForBall;

    if (forceCorrectAnswer) {
      wordForBall = _targetWordPair!;
    } else {
      List<Map<String, String>> candidates = _vocabulary.where((word) {
        bool isNotTarget = word['question'] != _targetWordPair!['question'];
        bool isNotDuplicate = !activeWords.contains(word['question']);
        return isNotTarget && isNotDuplicate;
      }).toList();

      if (candidates.isEmpty) {
        wordForBall = _vocabulary[_random.nextInt(_vocabulary.length)];
      } else {
        wordForBall = candidates[_random.nextInt(candidates.length)];
      }
    }

    Offset spawnPos = Offset.zero;
    bool validPosition = false;
    int attempts = 0;
    while (!validPosition && attempts < 20) {
      attempts++;
      double padding = _ballRadius * 2 + 10;
      double startX = _random.nextDouble() * (_screenSize!.width - padding) + _ballRadius;
      double startY = _random.nextDouble() * (_screenSize!.height - padding - 80) + (_ballRadius + 80);
      spawnPos = Offset(startX, startY);
      bool overlaps = false;
      for (var ball in _balls) {
        if ((ball.position - spawnPos).distance < _ballRadius * 2.2) {
          overlaps = true; break;
        }
      }
      if (!overlaps) validPosition = true;
    }

    double dx = (_random.nextDouble() * 5) - 2.5;
    double dy = (_random.nextDouble() * 5) - 2.5;
    if (dx.abs() < 1) dx = dx < 0 ? -1.5 : 1.5;
    if (dy.abs() < 1) dy = dy < 0 ? -1.5 : 1.5;

    Color ballColor = Color.lerp(AppColors.primary, AppColors.accent, _random.nextDouble())!;

    _balls.add(GameBall(
      id: DateTime.now().millisecondsSinceEpoch.toString() + _random.nextInt(1000).toString(),
      position: spawnPos,
      velocity: Offset(dx, dy),
      wordPair: wordForBall,
      color: ballColor,
    ));
  }

  void _handleBallTap(GameBall tappedBall) {
    bool isCorrect = tappedBall.wordPair['question'] == _targetWordPair!['question'];
    String correctAnswer = _targetWordPair!['question']!;
    String wordId = _targetWordPair!['id']!;

    // Haptic feedback
    HapticFeedback.mediumImpact();

    if (isCorrect) {
      // ✅ LOGIC: Correct Answer
      setState(() {
        _score += 10 + (_combo * 5); // Combo bonus
        _combo++;
        _showFeedback = false;
        _ballBeingRemoved = tappedBall.id;

        // Trigger score animation
        _scoreAnimController.reset();
        _scoreAnimController.forward();

        // Create particle explosion
        _createParticleExplosion(tappedBall.position, AppColors.success);

        // 1. Remove the clicked ball
        _balls.removeWhere((ball) => ball.id == tappedBall.id);

        // 2. Remove word from both vocabulary AND queue
        _vocabulary.removeWhere((w) => w['id'] == wordId);
        _wordQueue.removeWhere((w) => w['id'] == wordId);
      });

      // Reset ball removal flag
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _ballBeingRemoved = null);
      });

      // 3. CHECK IF ALL WORDS COMPLETED - Reload and reshuffle
      if (_vocabulary.isEmpty) {
        _fetchLessonWords(); // Reload all words and reshuffle
        return;
      }

      // 4. Continue Game - pick next word from queue
      _pickNewTarget();
      _respawnWithAntiCheat();

    } else {
      // ❌ LOGIC: Wrong Answer
      HapticFeedback.vibrate();
      _combo = 0; // Reset combo on wrong answer

      _createParticleExplosion(tappedBall.position, AppColors.error);

      _triggerWrongFeedback(correctAnswer);
      setState(() {
        _ballBeingRemoved = tappedBall.id;
        _pickNewTarget();
        _balls.removeWhere((ball) => ball.id == tappedBall.id);
        _respawnWithAntiCheat();
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _ballBeingRemoved = null);
      });
    }
  }

  void _createParticleExplosion(Offset position, Color color) {
    for (int i = 0; i < 20; i++) {
      double angle = (i / 20) * 2 * math.pi;
      double speed = 3 + _random.nextDouble() * 4;
      _particles.add(ParticleEffect(
        position: position,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        color: color,
        life: 1.0,
      ));
    }
  }

  void _updateParticles() {
    _particles.removeWhere((particle) => particle.life <= 0);
    for (var particle in _particles) {
      particle.update();
    }
  }

  void _triggerWrongFeedback(String correctBallText) {
    _feedbackTimer?.cancel();
    String topWord = _targetWordPair!['answer']!;

    setState(() {
      _showFeedback = true;
      _feedbackText = "$topWord :\n$correctBallText";
    });

    _feedbackAnimController.reset();
    _feedbackAnimController.forward();

    _feedbackTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        _feedbackAnimController.reverse().then((_) {
          if (mounted) setState(() => _showFeedback = false);
        });
      }
    });
  }

  void _respawnWithAntiCheat() {
    if (_vocabulary.isEmpty) return; // Safety

    bool targetAlreadyExists = _balls.any((b) => b.wordPair['question'] == _targetWordPair!['question']);
    if (targetAlreadyExists) {
      _addNewBall(forceCorrectAnswer: false);
    } else {
      bool useMorphTrick = _random.nextBool() && _balls.isNotEmpty;
      if (useMorphTrick) {
        int indexToMorph = _random.nextInt(_balls.length);
        GameBall oldBall = _balls[indexToMorph];
        _balls[indexToMorph] = GameBall(
          id: oldBall.id,
          position: oldBall.position,
          velocity: oldBall.velocity,
          color: oldBall.color,
          wordPair: _targetWordPair!,
        );
        _addNewBall(forceCorrectAnswer: false);
      } else {
        _addNewBall(forceCorrectAnswer: true);
      }
    }
  }

  void _updatePhysics() {
    if (_screenSize == null) return;
    for (var ball in _balls) {
      ball.position += ball.velocity;
      if (ball.position.dx < _ballRadius) {
        ball.position = Offset(_ballRadius, ball.position.dy);
        ball.velocity = Offset(-ball.velocity.dx, ball.velocity.dy);
      } else if (ball.position.dx > _screenSize!.width - _ballRadius) {
        ball.position = Offset(_screenSize!.width - _ballRadius, ball.position.dy);
        ball.velocity = Offset(-ball.velocity.dx, ball.velocity.dy);
      }
      if (ball.position.dy < _ballRadius + 80) { 
        ball.position = Offset(ball.position.dx, _ballRadius + 80);
        ball.velocity = Offset(ball.velocity.dx, -ball.velocity.dy);
      } else if (ball.position.dy > _screenSize!.height - _ballRadius) {
        ball.position = Offset(ball.position.dx, _screenSize!.height - _ballRadius);
        ball.velocity = Offset(ball.velocity.dx, -ball.velocity.dy);
      }
    }
    for (int i = 0; i < _balls.length; i++) {
      for (int j = i + 1; j < _balls.length; j++) {
        GameBall ball1 = _balls[i];
        GameBall ball2 = _balls[j];
        double dx = ball1.position.dx - ball2.position.dx;
        double dy = ball1.position.dy - ball2.position.dy;
        double distance = math.sqrt(dx * dx + dy * dy);
        if (distance < _ballRadius * 2) {
          if (distance <= 0) { distance = 0.01; dx = 0.01; }
          Offset tempVel = ball1.velocity;
          ball1.velocity = ball2.velocity;
          ball2.velocity = tempVel;
          double overlap = (_ballRadius * 2) - distance;
          Offset separation = Offset(dx, dy) / distance * (overlap / 2);
          ball1.position += separation;
          ball2.position -= separation;
        }
      }
    }
    for (var ball in _balls) {
       if (ball.position.dx > _screenSize!.width || ball.position.dy > _screenSize!.height) {
         ball.position = Offset(_screenSize!.width/2, _screenSize!.height/2);
       }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
        ? Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _vocabulary.isEmpty
           ? Center(child: Text(S.noWordsInLessonGame, style: TextStyle(color: Colors.white, fontSize: r.fontSize(16))))
           : LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < constraints.maxHeight) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }
              Size newSize = Size(constraints.maxWidth, constraints.maxHeight);
              _screenSize = newSize;

              // Set responsive ball radius based on screen size
              _ballRadius = r.gameBallRadius;

              if (_balls.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _initializeGame();
                });
              }

              return Container(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                color: AppColors.background,
                child: Stack(
                  children: [
                    // Render balls with enhanced visuals
                    ..._balls.map((ball) {
                      bool isBeingRemoved = _ballBeingRemoved == ball.id;

                      return Positioned(
                        left: ball.position.dx - _ballRadius,
                        top: ball.position.dy - _ballRadius,
                        child: AnimatedScale(
                          scale: isBeingRemoved ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInBack,
                          child: GestureDetector(
                            onTap: () => _handleBallTap(ball),
                            child: Container(
                              width: _ballRadius * 2,
                              height: _ballRadius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    ball.color.withOpacity(0.95),
                                    ball.color,
                                    ball.color.withOpacity(0.7),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                  center: const Alignment(-0.3, -0.3),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: ball.color.withOpacity(0.7),
                                    blurRadius: r.scale(25),
                                    spreadRadius: r.scale(5),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: r.scale(10),
                                    offset: Offset(0, r.scale(4)),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.8),
                                  width: r.scale(3),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Padding(
                                padding: EdgeInsets.all(r.spacing(8)),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: _ballRadius * 1.6,
                                    child: Text(
                                      ball.wordPair['question']!,
                                      textAlign: TextAlign.center,
                                      maxLines: 3,
                                      overflow: TextOverflow.visible,
                                      style: TextStyle(
                                        fontSize: r.fontSize(16),
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        height: 1.1,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: r.scale(6),
                                            offset: Offset(0, r.scale(2)),
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
                    }),

                    // Render particles with enhanced glow
                    ..._particles.map((particle) {
                      double particleSize = r.scale(8) + (particle.life * r.scale(4));
                      return Positioned(
                        left: particle.position.dx - particleSize / 2,
                        top: particle.position.dy - particleSize / 2,
                        child: Opacity(
                          opacity: (particle.life * 0.8).clamp(0.0, 1.0),
                          child: Container(
                            width: particleSize,
                            height: particleSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: particle.color,
                              boxShadow: [
                                BoxShadow(
                                  color: particle.color.withOpacity(0.9),
                                  blurRadius: r.scale(12),
                                  spreadRadius: r.scale(2),
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    // TOP MIDDLE - Target word
                    Positioned(
                      top: r.spacing(15),
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: r.spacing(24), vertical: r.spacing(12)),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(r.radius(20)),
                            border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.2),
                                blurRadius: r.scale(20),
                                spreadRadius: r.scale(3),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: r.scale(15),
                                offset: Offset(0, r.scale(3)),
                              )
                            ],
                          ),
                          child: Text(
                            _targetWordPair != null ? _targetWordPair!['answer']!.toUpperCase() : "...",
                            style: TextStyle(
                              fontSize: r.fontSize(22),
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                  color: Colors.white24,
                                  blurRadius: r.scale(8),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // TOP BAR
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: r.spacing(20), vertical: r.spacing(8)),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withOpacity(0.9), Colors.transparent],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left side - Words remaining with progress
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    "${_wordQueue.length}",
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: r.fontSize(28),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(width: r.spacing(4)),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        S.left,
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: r.fontSize(10),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        "/ $_totalWordsInLesson",
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.4),
                                          fontSize: r.fontSize(12),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const Spacer(),

                              // Right side - Score and combo
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ScaleTransition(
                                    scale: _scoreScale,
                                    child: Text(
                                      "$_score",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: r.fontSize(28),
                                        fontWeight: FontWeight.w900,
                                        shadows: [
                                          Shadow(
                                            color: Colors.white38,
                                            blurRadius: r.scale(10),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: r.spacing(4)),
                                  Text(
                                    S.pts,
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: r.fontSize(10),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_combo > 1)
                                    Container(
                                      margin: EdgeInsets.only(left: r.spacing(8)),
                                      padding: EdgeInsets.symmetric(horizontal: r.spacing(6), vertical: r.spacing(3)),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [AppColors.primary, AppColors.accent],
                                        ),
                                        borderRadius: BorderRadius.circular(r.radius(8)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withOpacity(0.5),
                                            blurRadius: r.scale(8),
                                            spreadRadius: r.scale(1),
                                          )
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.bolt_rounded,
                                            color: Colors.white,
                                            size: r.iconSize(14),
                                          ),
                                          Text(
                                            "x$_combo",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: r.fontSize(12),
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  SizedBox(width: r.spacing(8)),
                                ],
                              ),

                              // Close button
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(Icons.close_rounded, color: Colors.white, size: r.iconSize(28)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // FEEDBACK - Wrong answer
                    if (_showFeedback)
                      IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: ScaleTransition(
                            scale: _feedbackScale,
                            child: Container(
                              padding: EdgeInsets.all(r.spacing(40)),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(r.radius(24)),
                                border: Border.all(color: AppColors.error, width: r.scale(4)),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.error.withOpacity(0.5),
                                    blurRadius: r.scale(30),
                                    spreadRadius: r.scale(10),
                                  )
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(r.spacing(16)),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.error.withOpacity(0.2),
                                      border: Border.all(color: AppColors.error, width: r.scale(3)),
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: AppColors.error,
                                      size: r.iconSize(60),
                                    ),
                                  ),
                                  SizedBox(height: r.spacing(20)),
                                  Text(
                                    _feedbackText,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: r.fontSize(36),
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // CYCLE COMPLETE - Celebration message
                    if (_showCycleComplete)
                      IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: r.spacing(50), vertical: r.spacing(30)),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withOpacity(0.95),
                                  AppColors.accent.withOpacity(0.95),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(r.radius(24)),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.6),
                                  blurRadius: r.scale(40),
                                  spreadRadius: r.scale(15),
                                )
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.emoji_events_rounded,
                                  color: Colors.white,
                                  size: r.iconSize(70),
                                ),
                                SizedBox(height: r.spacing(16)),
                                Text(
                                  S.cycleComplete,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: r.fontSize(32),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                SizedBox(height: r.spacing(8)),
                                Text(
                                  S.allWordsReviewed,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: r.fontSize(18),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }
          ),
    );
  }
}

class GameBall {
  final String id;
  Offset position;
  Offset velocity;
  final Color color;
  final Map<String, String> wordPair;
  GameBall({required this.id, required this.position, required this.velocity, required this.color, required this.wordPair});
}

class ParticleEffect {
  Offset position;
  Offset velocity;
  Color color;
  double life;

  ParticleEffect({
    required this.position,
    required this.velocity,
    required this.color,
    required this.life,
  });

  void update() {
    position += velocity;
    velocity *= 0.96; // Friction - slower decay for more visible particles
    life -= 0.015; // Slower fade for longer-lasting effect
  }
}