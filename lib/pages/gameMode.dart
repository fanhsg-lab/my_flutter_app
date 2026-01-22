import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class GameQuizPage extends StatefulWidget {
  final int lessonId;
  final bool isReversed; // true = Gr->Esp, false = Esp->Gr

  const GameQuizPage({super.key, required this.lessonId, required this.isReversed});

  @override
  State<GameQuizPage> createState() => _GameQuizPageState();
}

class _GameQuizPageState extends State<GameQuizPage> with TickerProviderStateMixin {
  
  List<Map<String, String>> _vocabulary = [];
  bool _isLoading = true;

  late Ticker _ticker;
  Size? _screenSize;
  List<GameBall> _balls = [];
  Map<String, String>? _targetWordPair;
  int _score = 0;
  final int _totalBalls = 6;
  final double _ballRadius = 65.0; 
  final math.Random _random = math.Random();
  
  bool _showFeedback = false;
  String _feedbackText = ""; 
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    _fetchLessonWords(); 

    _ticker = createTicker((elapsed) {
      if (_screenSize != null && !_isLoading && _vocabulary.isNotEmpty) {
        _updatePhysics();
      }
    });
    _ticker.start();
  }

 Future<void> _fetchLessonWords() async {
    try {
      final supabase = Supabase.instance.client;
      // Get all columns
      final rawResponse = await supabase
          .from('words')
          .select() 
          .eq('lesson_id', widget.lessonId);

      List<Map<String, String>> loadedWords = [];
      
      for (var row in rawResponse) {
        String id = row['id'].toString(); 
        String es_val = ""; // Value from Spanish column
        String gr_val = ""; // Value from English/Greek column

        // 1. Get Spanish Value
        if (row.containsKey('es')) es_val = row['es'].toString();
        else if (row.containsKey('spanish')) es_val = row['spanish'].toString();

        // 2. Get Greek/English Value
        if (row.containsKey('en')) gr_val = row['en'].toString();
        else if (row.containsKey('english')) gr_val = row['english'].toString();
        else if (row.containsKey('gr')) gr_val = row['gr'].toString(); // Just in case you add 'gr' col later

        if (es_val.isNotEmpty && gr_val.isNotEmpty) {
          // --- FLIPPING LOGIC ---
          // 'question': The word on the balls
          // 'answer': The target word at the top
          
          if (widget.isReversed) {
            // Gr -> Esp (Balls have Greek, Target is Spanish)
            loadedWords.add({'id': id, 'question': gr_val, 'answer': es_val});
          } else {
            // Esp -> Gr (Balls have Spanish, Target is Greek)
            loadedWords.add({'id': id, 'question': es_val, 'answer': gr_val});
          }
        }
      }

      if (mounted) {
        setState(() {
          _vocabulary = loadedWords;
          _isLoading = false;
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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _initializeGame() {
    if (_balls.isNotEmpty || _vocabulary.isEmpty) return;
    _pickNewTarget();
    for (int i = 0; i < _totalBalls; i++) {
      _addNewBall(forceCorrectAnswer: i == 0);
    }
  }

  void _pickNewTarget() {
     setState(() {
       _targetWordPair = _vocabulary[_random.nextInt(_vocabulary.length)];
     });
  }

  void _addNewBall({bool forceCorrectAnswer = false}) {
    if (_screenSize == null || _targetWordPair == null) return;

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
    String correctAnswer = _targetWordPair!['question']!; // The correct ball text
    String wordId = _targetWordPair!['id']!;

    setState(() {
      if (isCorrect) {
        _score += 10;
        _showFeedback = false; 
      } else {
        _triggerWrongFeedback(correctAnswer);
      }
      _pickNewTarget();
      _balls.removeWhere((ball) => ball.id == tappedBall.id);
      _respawnWithAntiCheat();
    });
  }

  void _triggerWrongFeedback(String correctBallText) {
    _feedbackTimer?.cancel();
    // Target (Top) : Answer (Ball)
    String topWord = _targetWordPair!['answer']!;

    setState(() {
      _showFeedback = true;
      _feedbackText = "$topWord :\n$correctBallText";
    });
    
    _feedbackTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _showFeedback = false);
    });
  }

  void _respawnWithAntiCheat() {
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
    return Scaffold(
      backgroundColor: AppColors.background, 
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _vocabulary.isEmpty 
           ? Center(child: Text("No words in this lesson!", style: TextStyle(color: Colors.white)))
           : LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < constraints.maxHeight) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }
              Size newSize = Size(constraints.maxWidth, constraints.maxHeight);
              _screenSize = newSize;

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
                    ..._balls.map((ball) {
                      return Positioned(
                        left: ball.position.dx - _ballRadius,
                        top: ball.position.dy - _ballRadius,
                        child: GestureDetector(
                          onTap: () => _handleBallTap(ball),
                          child: Container(
                            width: _ballRadius * 2,
                            height: _ballRadius * 2,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ball.color,
                              boxShadow: [BoxShadow(color: ball.color.withOpacity(0.5), blurRadius: 15)],
                              border: Border.all(color: Colors.white.withOpacity(0.8), width: 3)
                            ),
                            alignment: Alignment.center,
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(ball.wordPair['question']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black)),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: Container(
                        height: 80, 
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.black.withOpacity(0.9), Colors.transparent], 
                            begin: Alignment.topCenter, 
                            end: Alignment.bottomCenter
                          )
                        ),
                        child: Stack(
                          children: [
                            Align(alignment: Alignment.centerLeft, child: Text("Score: $_score", style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.bold))),
                            
                            Align(
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                                decoration: BoxDecoration(color: AppColors.cardColor, borderRadius: BorderRadius.circular(30), border: Border.all(color: AppColors.primary, width: 2)),
                                child: Text(_targetWordPair != null ? _targetWordPair!['answer']!.toUpperCase() : "...", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                              ),
                            ),
                            
                            Align(alignment: Alignment.centerRight, child: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white, size: 36))),
                          ],
                        ),
                      ),
                    ),

                    IgnorePointer(
                      ignoring: true,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _showFeedback ? 1.0 : 0.0,
                          child: Container(
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.9), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.error, width: 3)),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cancel, color: AppColors.error, size: 80),
                                const SizedBox(height: 15),
                                Text(_feedbackText, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error, fontSize: 32, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
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
  final Map<String, String> wordPair; // keys: 'id', 'question', 'answer'
  GameBall({required this.id, required this.position, required this.velocity, required this.color, required this.wordPair});
}