import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../local_db.dart';
import '../theme.dart';
import 'package:my_first_flutter_app/pages/notification_service.dart'; 

class SurvivalPage extends StatefulWidget {
  final int lessonId;
  final bool isReversed;

  const SurvivalPage({
    super.key,
    required this.lessonId,
    required this.isReversed,
  });

  @override
  State<SurvivalPage> createState() => _SurvivalPageState();
}

class _SurvivalPageState extends State<SurvivalPage> {
  // State
  bool _isLoading = true;
  String _debugStatus = "Initializing...";
  
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
    setState(() => _debugStatus = "Loading...");
    try {
      final db = await LocalDB.instance.database;
      final rawData = await db.query('words', where: 'lesson_id = ?', whereArgs: [widget.lessonId]);
      
      if (rawData.isEmpty) {
        _showError("Database empty for this lesson.");
        return;
      }

      List<GameItem> validItems = [];
      for (var row in rawData) {
         GameItem? item = _sanitizeItem(row);
         if (item != null) validItems.add(item);
      }

      if (validItems.isEmpty) {
        _showError("No valid words found.");
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
      _showError("Error: $e");
    }
  }

  void _showError(String msg) {
    if(!mounted) return;
    setState(() => _isLoading = false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
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
      cleanBase = cleanBase.replaceAll("EL/LA", "").replaceAll("UN/UNA", "");
      cleanBase = cleanBase.split(',')[0].split('/')[0].split('(')[0];

      final articleRegex = RegExp(r'^(EL|LA|LOS|LAS|UN|UNA)\s+', caseSensitive: false);
      cleanBase = cleanBase.replaceAll(articleRegex, '').trim();
      cleanBase = cleanBase.replaceAll(RegExp(r'[.!?¡¿]'), '');

      if (cleanBase.isEmpty) return null;

      String audioVersion = cleanBase; 
      String gameVersion = _removeSpanishAccents(cleanBase); 
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
    
    _flutterTts.setLanguage("es-ES");

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

  // 🔥 CORE LOGIC: BLOCK WRONG INPUT
  void _handleInput(String value) {
    if (_slotColors != null) return; // Locked on win/loss animation

    String cleanValue = _removeSpanishAccents(value.toUpperCase());
    
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

      // COMPARE with Target
      if (charTyped == _targetWord[indexToCheck]) {
        // ✅ CORRECT: Accept it
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
    NotificationService().scheduleSmartReminder();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardColor,
        title: Icon(win ? Icons.emoji_events : Icons.heart_broken, size: 50, color: win ? Colors.amber : Colors.red),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(win ? "SURVIVED!" : "GAME OVER", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Final Score: $_score", style: const TextStyle(color: Colors.grey, fontSize: 18)),
        ]),
        actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("EXIT", style: TextStyle(color: Colors.white)))],
      ),
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
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background, 
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(_debugStatus, style: const TextStyle(color: Colors.white70))
        ]))
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.favorite, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text("$_lives", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(width: 20),
            const Icon(Icons.star, color: Colors.amber),
            const SizedBox(width: 8),
            Text("$_score", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        ]),
        actions: [
          IconButton(
            icon: Icon(_showHint ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
            onPressed: _useHint, 
          )
        ],
      ),
      body: Column(children: [
          LinearProgressIndicator(value: _progress, backgroundColor: Colors.grey.shade900, valueColor: AlwaysStoppedAnimation(_progress > 0.5 ? Colors.green : (_progress > 0.2 ? Colors.amber : Colors.red)), minHeight: 6),
          const Spacer(),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
                Text(_promptWord, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
                if (_showHint) ...[const SizedBox(height: 10), Text(_audioTargetWord, style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2))] 
                else ...[const SizedBox(height: 10), const Text("Type the translation", style: TextStyle(color: Colors.grey, fontSize: 14))]
          ])),
          const Spacer(),
          
          // 🔠 VISUAL SLOTS
          Container(padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center, child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 10, children: List.generate(_targetWord.length, (index) {
                String char = index < _currentInput.length ? _currentInput[index] : "";
                bool isSpace = _targetWord[index] == ' ';
                bool isFilled = char.isNotEmpty;
                
                // --- COLOR LOGIC ---
                Color boxColor = Colors.white.withOpacity(0.05);
                Color borderColor = Colors.white.withOpacity(0.2);

                if (_slotColors != null) { 
                    // Final Result (All Green or All Red)
                    boxColor = _slotColors![index]; 
                    borderColor = Colors.transparent; 
                } 
                else if (_errorIndex == index) {
                    // 🚨 CURRENT ERROR FLASH (Red)
                    boxColor = Colors.redAccent;
                    borderColor = Colors.redAccent;
                }
                else if (isFilled) { 
                    // Standard Typed Letter (Primary)
                    boxColor = AppColors.primary; 
                    borderColor = Colors.transparent; 
                } 
                else if (isSpace) { 
                    boxColor = Colors.transparent; 
                    borderColor = Colors.transparent; 
                }

                if (isSpace) return Container(width: 20, height: 50, alignment: Alignment.bottomCenter, child: Container(height: 2, width: 12, color: Colors.white24));
                
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100), 
                  width: 40, height: 50, 
                  alignment: Alignment.center, 
                  decoration: BoxDecoration(
                    color: boxColor, 
                    borderRadius: BorderRadius.circular(8), 
                    border: Border.all(color: borderColor, width: 1.5), 
                    boxShadow: (isFilled || _slotColors != null || _errorIndex == index) 
                        ? [BoxShadow(color: boxColor.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))] 
                        : []
                  ), 
                  child: Text(char, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black))
                );
          }))),
          
          const Spacer(flex: 2),
          Opacity(opacity: 0.0, child: TextField(controller: _textController, focusNode: _focusNode, autocorrect: false, enableSuggestions: false, keyboardType: TextInputType.visiblePassword, textInputAction: TextInputAction.done, onChanged: _handleInput, style: const TextStyle(color: Colors.transparent), cursorColor: Colors.transparent)),
      ]),
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