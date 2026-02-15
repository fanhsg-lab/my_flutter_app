import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:heroicons/heroicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../local_db.dart';
import '../theme.dart';
import '../responsive.dart';
import '../services/app_strings.dart';
import 'package:my_first_flutter_app/pages/notification_service.dart'; 

class SurvivalPage extends StatefulWidget {
  final int lessonId;
  final bool isReversed;
  final bool isPracticeMode; // true = all words, false = expired words only
  final String sourceLanguage;

  const SurvivalPage({
    super.key,
    required this.lessonId,
    required this.isReversed,
    this.isPracticeMode = false, // Default to Review Mode
    this.sourceLanguage = 'es',
  });

  @override
  State<SurvivalPage> createState() => _SurvivalPageState();
}

class _SurvivalPageState extends State<SurvivalPage> {
  // State
  bool _isLoading = true;
  String _debugStatus = "";
  
  List<GameItem> _cleanQueue = []; 
  int _currentIndex = 0;

  // Stats
  int _lives = 3;
  int _score = 0;

  // Round State
  String _targetWord = "";      
  String _audioTargetWord = ""; 
  String _promptWord = ""; 
  String _currentInput = "";
  bool _showHint = false;

  // Visual Feedback
  int? _errorIndex; // Tracks which slot should flash red

  Timer? _timer;
  int _timeLeft = 30;
  double _progress = 1.0;
  List<Color>? _slotColors; 

  final FlutterTts _flutterTts = FlutterTts();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAndProcessData();
    // Keyboard Guard
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _lives > 0 && !_isLoading && mounted) {
         FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flutterTts.stop();
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadAndProcessData() async {
    setState(() => _debugStatus = S.loading);
    try {
      final db = await LocalDB.instance.database;
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        _showError(S.pleaseLogIn);
        return;
      }

      // Load words based on mode
      final List<Map<String, dynamic>> rawData;
      if (widget.isPracticeMode) {
        // Practice Mode: Load ALL words from lesson
        rawData = await db.rawQuery('''
          SELECT w.* FROM lesson_words lw
          JOIN words w ON w.id = lw.word_id
          WHERE lw.lesson_id = ?
          ORDER BY w.id ASC
        ''', [widget.lessonId]);
      } else {
        // Review Mode: Load ONLY expired words (words due for review)
        // Load words with progress and filter by datetime in Dart for timezone accuracy
        final allWords = await db.rawQuery('''
          SELECT w.id, w.lesson_id, w.es, w.en, up.next_due_at
          FROM lesson_words lw
          JOIN words w ON w.id = lw.word_id
          INNER JOIN user_progress up ON w.id = up.word_id AND up.user_id = ?
          WHERE lw.lesson_id = ?
            AND up.next_due_at IS NOT NULL
        ''', [userId, widget.lessonId]);

        // Filter words where next_due_at has passed (including time)
        final now = DateTime.now().toUtc();
        rawData = allWords.where((word) {
          try {
            final nextDueStr = word['next_due_at'] as String?;
            if (nextDueStr == null) return false;
            final dueDate = DateTime.parse(nextDueStr).toUtc();
            return dueDate.isBefore(now) || dueDate.isAtSameMomentAs(now);
          } catch (e) {
            return false;
          }
        }).toList();
      }

      if (rawData.isEmpty) {
        _showError(widget.isPracticeMode
          ? S.noWordsInLesson
          : S.noWordsDueReview);
        return;
      }

      List<GameItem> validItems = [];
      for (var row in rawData) {
         GameItem? item = _sanitizeItem(row);
         if (item != null) validItems.add(item);
      }

      if (validItems.isEmpty) {
        _showError(S.noValidWords);
        return;
      }

      validItems.shuffle();
      _cleanQueue = validItems;
      _currentIndex = 0;
      
      _startRound(); 

      if (mounted) {
        setState(() => _isLoading = false);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _focusNode.requestFocus();
        });
      }
    } catch (e) {
      _showError("${S.error}: $e");
    }
  }

  void _showError(String msg) {
    if(!mounted) return;
    setState(() => _isLoading = false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.error),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to main screen
            },
            child: Text(S.ok)
          )
        ],
      ),
    );
  }

  // 🛠️ SANITIZER
  GameItem? _sanitizeItem(Map<String, dynamic> row) {
    try {
      String rawTarget = (row['es'] as String? ?? "");
      String rawPrompt = (row['en'] as String? ?? "");
      if (rawTarget.isEmpty) return null;

      String cleanBase = rawTarget.toUpperCase();

      if (widget.sourceLanguage == 'es') {
        // Spanish-specific: remove articles and punctuation
        cleanBase = cleanBase.replaceAll("EL/LA", "").replaceAll("UN/UNA", "");
        cleanBase = cleanBase.split(',')[0].split('/')[0].split('(')[0];
        final articleRegex = RegExp(r'^(EL|LA|LOS|LAS|UN|UNA)\s+', caseSensitive: false);
        cleanBase = cleanBase.replaceAll(articleRegex, '').trim();
        cleanBase = cleanBase.replaceAll(RegExp(r'[.!?¡¿]'), '');
      } else {
        // English/other: remove articles and basic punctuation
        cleanBase = cleanBase.split(',')[0].split('(')[0];
        final articleRegex = RegExp(r'^(THE|A|AN)\s+', caseSensitive: false);
        cleanBase = cleanBase.replaceAll(articleRegex, '').trim();
        cleanBase = cleanBase.replaceAll(RegExp(r'[.!?]'), '');
        // Handle inline alternatives like "sb/sth" → pick first variant per word
        cleanBase = cleanBase.split(' ').map((w) {
          if (w.contains('/')) return w.split('/')[0];
          return w;
        }).join(' ');
        // Replace hyphens with spaces: "in-store" → "IN STORE"
        cleanBase = cleanBase.replaceAll('-', ' ');
        // Remove apostrophes: "month's" → "MONTHS"
        cleanBase = cleanBase.replaceAll("'", '').replaceAll('\u2019', '');
      }

      if (cleanBase.isEmpty) return null;

      String audioVersion = cleanBase;
      String gameVersion = widget.sourceLanguage == 'es'
          ? _removeSpanishAccents(cleanBase)
          : cleanBase;
      gameVersion = gameVersion.replaceAll(RegExp(r'\s+'), ' ');

      if (gameVersion.isNotEmpty) {
        return GameItem(
          targetForTyping: gameVersion,
          targetForAudio: audioVersion,
          prompt: rawPrompt
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _removeSpanishAccents(String str) {
    return str
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ü', 'U')
      .replaceAll('Ñ', 'N');
  }

  void _startRound() {
    if (_currentIndex >= _cleanQueue.length) {
      _finishGame(win: true);
      return;
    }
    final item = _cleanQueue[_currentIndex];
    
    _flutterTts.setLanguage(widget.sourceLanguage == 'en' ? "en-US" : "es-ES");

    setState(() {
      _targetWord = item.targetForTyping;
      _audioTargetWord = item.targetForAudio;
      _promptWord = item.prompt;
      _currentInput = "";
      _showHint = false;
      _textController.clear();
      _textController.value = TextEditingValue.empty;
      _timeLeft = 30;
      _progress = 1.0;
      _slotColors = null;
      _errorIndex = null;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
          _progress = _timeLeft / 30;
        } else {
          _handleTimeOut();
        }
      });
    });
  }

  // 🔥 CORE LOGIC: BLOCK WRONG INPUT + SPACE DETECTION
  void _handleInput(String value) {
    if (_slotColors != null) return; // Locked on win/loss animation

    String cleanValue = value.toUpperCase();
    if (widget.sourceLanguage == 'es') cleanValue = _removeSpanishAccents(cleanValue);

    // 1. If Backspace (value is shorter), just allow it
    if (cleanValue.length < _currentInput.length) {
      setState(() => _currentInput = cleanValue);
      return;
    }

    // 2. If new character typed
    if (cleanValue.length > _currentInput.length) {
      // Get the character they just typed (the last one)
      String charTyped = cleanValue[cleanValue.length - 1];
      int indexToCheck = _currentInput.length;

      // Ensure we haven't exceeded word length
      if (indexToCheck >= _targetWord.length) return;

      // Get expected character from target
      String expectedChar = _targetWord[indexToCheck];

      // COMPARE with Target (handles both regular chars and spaces)
      if (charTyped == expectedChar) {
        // ✅ CORRECT: Accept it
        HapticFeedback.lightImpact(); // Light feedback for correct input

        setState(() {
          _currentInput = cleanValue;
          _errorIndex = null; // Clear any previous error flag
        });

        // Check for Win
        if (_currentInput.length == _targetWord.length) {
          _handleWin();
        }

      } else {
        // ❌ WRONG: Block it
        HapticFeedback.heavyImpact(); // Strong vibration

        // Reset Controller to previous valid input (refuse the new char)
        _textController.value = TextEditingValue(
          text: _currentInput,
          selection: TextSelection.fromPosition(TextPosition(offset: _currentInput.length)),
        );

        // Flash Red on the slot they tried to fill
        setState(() {
           _errorIndex = indexToCheck;
        });

        // Clear the red flash after 200ms
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _errorIndex = null);
        });
      }
    }
  }

  void _handleWin() {
    _timer?.cancel();
    _flutterTts.speak(_audioTargetWord); 
    HapticFeedback.heavyImpact();

    setState(() {
      _slotColors = List.filled(_targetWord.length, Colors.green);
      _score += 10 + _timeLeft;
    });
    
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      _currentIndex++;
      _startRound();
    });
  }

  void _handleTimeOut() {
    _timer?.cancel();
    HapticFeedback.vibrate();
    
    setState(() {
      _lives--;
      _slotColors = List.filled(_targetWord.length, Colors.redAccent); 
    });

    if (_lives <= 0) {
      Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) _finishGame(win: false); });
    } else {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() {
          _currentInput = "";
          _textController.clear();
          _slotColors = null;
          _timeLeft = 30;
          _progress = 1.0;
        });
        _focusNode.requestFocus();
        _startTimer();
      });
    }
  }

  void _finishGame({required bool win}) {
    FocusScope.of(context).unfocus();
    NotificationService().onAppOpened();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final dr = Responsive(dialogContext);
        return AlertDialog(
          backgroundColor: AppColors.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(dr.radius(16))),
          title: HeroIcon(win ? HeroIcons.trophy : HeroIcons.faceFrown, size: dr.iconSize(50), color: win ? Colors.amber : Colors.red, style: HeroIconStyle.solid),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(win ? S.survived : S.gameOver, style: TextStyle(color: Colors.white, fontSize: dr.fontSize(24), fontWeight: FontWeight.bold)),
              SizedBox(height: dr.spacing(10)),
              Text("${S.finalScore} $_score", style: TextStyle(color: Colors.grey, fontSize: dr.fontSize(18))),
          ]),
          actions: [TextButton(onPressed: () { Navigator.pop(dialogContext); Navigator.pop(context); }, child: Text(S.exit, style: TextStyle(color: Colors.white, fontSize: dr.fontSize(14))))],
        );
      },
    );
  }

  // 👁️ HINT LOGIC
  void _useHint() {
    setState(() {
      _showHint = !_showHint;
      if (_showHint) {
        _lives--; // COST: 1 LIFE
        HapticFeedback.lightImpact();
        
        if (_lives <= 0) {
           _timer?.cancel();
           _finishGame(win: false);
        } else {
           Future.delayed(const Duration(seconds: 2), () {
             if (mounted) setState(() => _showHint = false);
           });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(),
          SizedBox(height: r.spacing(20)),
          Text(_debugStatus, style: TextStyle(color: Colors.white70, fontSize: r.fontSize(14)))
        ]))
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: HeroIcon(HeroIcons.xMark, color: Colors.white70, size: r.iconSize(28), style: HeroIconStyle.outline),
          onPressed: () => Navigator.pop(context)
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lives
            Container(
              padding: EdgeInsets.symmetric(horizontal: r.spacing(12), vertical: r.spacing(6)),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(r.radius(12)),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeroIcon(HeroIcons.heart, color: Colors.redAccent, size: r.iconSize(20), style: HeroIconStyle.solid),
                  SizedBox(width: r.spacing(6)),
                  Text(
                    "$_lives",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: r.fontSize(18),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: r.spacing(16)),
            // Score
            Container(
              padding: EdgeInsets.symmetric(horizontal: r.spacing(12), vertical: r.spacing(6)),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(r.radius(12)),
                border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeroIcon(HeroIcons.star, color: Colors.amber, size: r.iconSize(20), style: HeroIconStyle.solid),
                  SizedBox(width: r.spacing(6)),
                  Text(
                    "$_score",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: r.fontSize(18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: r.spacing(8)),
            child: IconButton(
              icon: HeroIcon(
                _showHint ? HeroIcons.eyeSlash : HeroIcons.lightBulb,
                color: _showHint ? AppColors.primary : Colors.white54,
                size: r.iconSize(26),
                style: HeroIconStyle.outline,
              ),
              onPressed: _useHint,
              tooltip: S.hintCost,
            ),
          )
        ],
      ),
      body: SingleChildScrollView(child: Column(children: [
          // Enhanced Progress Bar with Timer
          Container(
            padding: EdgeInsets.symmetric(vertical: r.spacing(6)),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey.shade900,
                  valueColor: AlwaysStoppedAnimation(
                    _progress > 0.5 ? AppColors.success : (_progress > 0.2 ? Colors.amber : Colors.redAccent)
                  ),
                  minHeight: r.scale(6),
                ),
                SizedBox(height: r.spacing(6)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HeroIcon(
                      HeroIcons.clock,
                      color: _progress > 0.2 ? Colors.white70 : Colors.redAccent,
                      size: r.iconSize(18),
                      style: HeroIconStyle.outline,
                    ),
                    SizedBox(width: r.spacing(4)),
                    Text(
                      "$_timeLeft s",
                      style: TextStyle(
                        color: _progress > 0.2 ? Colors.white : Colors.redAccent,
                        fontSize: r.fontSize(16),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: r.spacing(12)),

          // Enhanced Prompt Area
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.spacing(20)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: r.spacing(14), vertical: r.spacing(8)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(r.radius(16)),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
              ),
              child: Column(
                children: [
                  // Mode Indicator Badge
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: r.spacing(8), vertical: r.spacing(3)),
                    decoration: BoxDecoration(
                      color: widget.isPracticeMode
                        ? Colors.blue.withOpacity(0.2)
                        : AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(r.radius(8)),
                      border: Border.all(
                        color: widget.isPracticeMode
                          ? Colors.blue.withOpacity(0.5)
                          : AppColors.primary.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HeroIcon(
                          widget.isPracticeMode ? HeroIcons.puzzlePiece : HeroIcons.academicCap,
                          color: widget.isPracticeMode ? Colors.blue : AppColors.primary,
                          size: r.iconSize(12),
                          style: HeroIconStyle.outline,
                        ),
                        SizedBox(width: r.spacing(4)),
                        Text(
                          widget.isPracticeMode ? S.practice : S.review,
                          style: TextStyle(
                            color: widget.isPracticeMode ? Colors.blue : AppColors.primary,
                            fontSize: r.fontSize(9),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: r.spacing(6)),
                  Text(
                    S.translate,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: r.fontSize(10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: r.spacing(8)),
                  Text(
                    _promptWord,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: r.fontSize(24),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                  if (_showHint) ...[
                    SizedBox(height: r.spacing(6)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: r.spacing(10), vertical: r.spacing(4)),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(r.radius(8)),
                        border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HeroIcon(HeroIcons.lightBulb, color: AppColors.primary, size: r.iconSize(12), style: HeroIconStyle.solid),
                          SizedBox(width: r.spacing(4)),
                          Text(
                            _audioTargetWord,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: r.fontSize(14),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  ]
                ],
              ),
            ),
          ),
          SizedBox(height: r.spacing(12)),

          // 🔠 VISUAL SLOTS - Enhanced Design
          Container(padding: EdgeInsets.symmetric(horizontal: r.spacing(16)), alignment: Alignment.center, child: Wrap(alignment: WrapAlignment.center, spacing: r.spacing(6), runSpacing: r.spacing(8), children: List.generate(_targetWord.length, (index) {
                String char = index < _currentInput.length ? _currentInput[index] : "";
                bool isSpace = _targetWord[index] == ' ';
                bool isFilled = char.isNotEmpty;

                final slotSize = r.survivalSlotSize;

                // --- ENHANCED COLOR LOGIC ---
                Color boxColor = AppColors.cardColor;
                Color borderColor = Colors.white.withOpacity(0.3);
                Color textColor = Colors.white;

                if (_slotColors != null) {
                    // Final Result (All Green or All Red)
                    boxColor = _slotColors![index];
                    borderColor = Colors.transparent;
                    textColor = Colors.white;
                }
                else if (_errorIndex == index) {
                    // 🚨 CURRENT ERROR FLASH (Red)
                    boxColor = Colors.redAccent;
                    borderColor = Colors.redAccent;
                    textColor = Colors.white;
                }
                else if (isFilled) {
                    // Standard Typed Letter (Primary with glow)
                    boxColor = AppColors.primary;
                    borderColor = AppColors.primary;
                    textColor = Colors.black;
                }
                else if (isSpace) {
                    boxColor = Colors.transparent;
                    borderColor = Colors.transparent;
                }

                // SPACE INDICATOR - More obvious design
                if (isSpace) {
                  return Container(
                    width: slotSize.width * 0.6,
                    height: slotSize.height,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: r.scale(3),
                          width: slotSize.width * 0.45,
                          decoration: BoxDecoration(
                            color: isFilled ? AppColors.primary : Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(r.radius(2)),
                            boxShadow: isFilled ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.5),
                                blurRadius: r.scale(8),
                                spreadRadius: r.scale(2),
                              )
                            ] : [],
                          ),
                        ),
                        SizedBox(height: r.spacing(3)),
                        Text(
                          S.space,
                          style: TextStyle(
                            fontSize: r.fontSize(7),
                            fontWeight: FontWeight.bold,
                            color: isFilled ? AppColors.primary : Colors.white.withOpacity(0.3),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: slotSize.width,
                  height: slotSize.height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: boxColor,
                    borderRadius: BorderRadius.circular(r.radius(12)),
                    border: Border.all(color: borderColor, width: 2),
                    boxShadow: (isFilled || _slotColors != null || _errorIndex == index)
                        ? [
                            BoxShadow(
                              color: boxColor.withOpacity(0.5),
                              blurRadius: r.scale(12),
                              spreadRadius: r.scale(2),
                              offset: Offset(0, r.scale(3))
                            )
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: r.scale(4),
                              offset: Offset(0, r.scale(2))
                            )
                          ]
                  ),
                  child: Text(
                    char,
                    style: TextStyle(
                      fontSize: r.fontSize(22),
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: 0.5,
                    )
                  )
                );
          }))),

          SizedBox(height: r.spacing(8)),
          Opacity(opacity: 0.0, child: TextField(controller: _textController, focusNode: _focusNode, autocorrect: false, enableSuggestions: false, keyboardType: TextInputType.visiblePassword, textInputAction: TextInputAction.done, onChanged: _handleInput, style: const TextStyle(color: Colors.transparent), cursorColor: Colors.transparent)),
      ])),
    );
  }
}

class GameItem {
  final String targetForTyping; 
  final String targetForAudio;  
  final String prompt;
  
  GameItem({
    required this.targetForTyping, 
    required this.targetForAudio, 
    required this.prompt
  });
}