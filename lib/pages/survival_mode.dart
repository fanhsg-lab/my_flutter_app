import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final int wordRangeStart;
  final int wordRangeEnd;
  final String sourceLanguage;
  final bool isHardcore;

  const SurvivalPage({
    super.key,
    required this.lessonId,
    required this.isReversed,
    this.wordRangeStart = 0,
    this.wordRangeEnd = 20,
    this.sourceLanguage = 'es',
    this.isHardcore = false,
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

  // Round State
  String _targetWord = "";      
  String _audioTargetWord = ""; 
  String _promptWord = ""; 
  String _currentInput = "";
  bool _showHint = false;

  // Visual Feedback
  int? _errorIndex; // Tracks which slot should flash red
  List<Color>? _slotColors;

  // Hardcore mode mistakes
  final List<Map<String, String>> _mistakes = [];
  bool _hintUsedThisRound = false;
  bool _gameFinished = false;

  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAndProcessData();
  }

  @override
  void dispose() {
    _gameFinished = true;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
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

      // Load all lesson words ordered by id, then slice the selected range
      final allWords = await db.rawQuery('''
        SELECT w.* FROM lesson_words lw
        JOIN words w ON w.id = lw.word_id
        WHERE lw.lesson_id = ?
        ORDER BY w.id ASC
      ''', [widget.lessonId]);

      final start = widget.wordRangeStart.clamp(0, allWords.length);
      final end = widget.wordRangeEnd.clamp(start, allWords.length);
      final rawData = allWords.sublist(start, end);

      if (rawData.isEmpty) {
        _showError(S.noWordsInLesson);
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
      // isReversed=true  → target=es col (Spanish or Greek for en-books), prompt=en col
      // isReversed=false → target=en col (Greek or English for en-books), prompt=es col
      String rawTarget = widget.isReversed ? (row['es'] as String? ?? "") : (row['en'] as String? ?? "");
      String rawPrompt = widget.isReversed ? (row['en'] as String? ?? "") : (row['es'] as String? ?? "");
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

  String _removeGreekAccents(String str) {
    return str
      .replaceAll('Ά', 'Α')
      .replaceAll('Έ', 'Ε')
      .replaceAll('Ή', 'Η')
      .replaceAll('Ί', 'Ι')
      .replaceAll('Ϊ', 'Ι')
      .replaceAll('Ό', 'Ο')
      .replaceAll('Ύ', 'Υ')
      .replaceAll('Ϋ', 'Υ')
      .replaceAll('Ώ', 'Ω');
  }

  void _startRound() {
    if (_currentIndex >= _cleanQueue.length) {
      _finishGame();
      return;
    }
    final item = _cleanQueue[_currentIndex];
    
    setState(() {
      _targetWord = item.targetForTyping;
      _audioTargetWord = item.targetForAudio;
      _promptWord = item.prompt;
      _currentInput = "";
      _showHint = false;
      _textController.clear();
      _textController.value = TextEditingValue.empty;
      _slotColors = null;
      _errorIndex = null;
    });
    _hintUsedThisRound = false;
  }

  // 🔥 CORE LOGIC
  void _handleInput(String value) {
    if (_slotColors != null) return;

    String cleanValue = value.toUpperCase();
    if (widget.sourceLanguage == 'es') cleanValue = _removeSpanishAccents(cleanValue);

    if (widget.isHardcore) {
      _handleHardcoreInput(cleanValue);
    } else {
      _handleNormalInput(cleanValue);
    }
  }

  void _handleHardcoreInput(String cleanValue) {
    // Each keypress fills exactly one slot (including space slots)
    // so _currentInput.length always equals cleanValue.length
    if (cleanValue.length < _currentInput.length) {
      // Backspace: remove last slot
      setState(() => _currentInput = _currentInput.substring(0, _currentInput.length - 1));
      return;
    }
    if (cleanValue.length > _currentInput.length) {
      if (_currentInput.length >= _targetWord.length) return;
      HapticFeedback.lightImpact();
      final expectedChar = _targetWord[_currentInput.length];
      // At a space slot: accept any key but fill a space
      final charToFill = expectedChar == ' ' ? ' ' : cleanValue[cleanValue.length - 1];
      setState(() => _currentInput = _currentInput + charToFill);
      if (_currentInput.length == _targetWord.length) {
        if (_removeGreekAccents(_currentInput) == _removeGreekAccents(_targetWord)) {
          _handleWin();
        } else {
          if (_hintUsedThisRound) {
            final idx = _mistakes.lastIndexWhere((m) => m['isHint'] == 'true' && m['prompt'] == _promptWord);
            if (idx != -1) _mistakes[idx] = {'prompt': _promptWord, 'typed': _currentInput, 'correct': _audioTargetWord};
          } else {
            _mistakes.add({
              'prompt': _promptWord,
              'typed': _currentInput,
              'correct': _audioTargetWord,
            });
          }
          HapticFeedback.heavyImpact();
          setState(() => _slotColors = List.filled(_targetWord.length, Colors.redAccent));
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (!mounted) return;
            _currentIndex++;
            _startRound();
          });
        }
      }
    }
  }

  // Auto-fill any spaces in the target word so user never has to press space
  String _skipSpaces(String input) {
    var result = input;
    while (result.length < _targetWord.length && _targetWord[result.length] == ' ') {
      result += ' ';
    }
    return result;
  }

  void _handleNormalInput(String cleanValue) {
    // Each keypress fills exactly one slot (including space slots)
    // so _currentInput.length always equals cleanValue.length
    if (cleanValue.length < _currentInput.length) {
      // Backspace: remove last slot
      setState(() => _currentInput = _currentInput.substring(0, _currentInput.length - 1));
      return;
    }
    if (cleanValue.length > _currentInput.length) {
      final int indexToCheck = _currentInput.length;
      if (indexToCheck >= _targetWord.length) return;
      final String expectedChar = _targetWord[indexToCheck];

      if (expectedChar == ' ') {
        // Space slot: accept any key, fill a space, turn orange
        HapticFeedback.lightImpact();
        setState(() { _currentInput = _currentInput + ' '; _errorIndex = null; });
        if (_currentInput.length == _targetWord.length) _handleWin();
      } else {
        final String charTyped = cleanValue[cleanValue.length - 1];
        if (_removeGreekAccents(charTyped) == _removeGreekAccents(expectedChar)) {
          HapticFeedback.lightImpact();
          setState(() { _currentInput = _currentInput + charTyped; _errorIndex = null; });
          if (_currentInput.length == _targetWord.length) _handleWin();
        } else {
          HapticFeedback.heavyImpact();
          // Reset controller to current valid state so lengths stay in sync
          _textController.value = TextEditingValue(
            text: _currentInput,
            selection: TextSelection.fromPosition(TextPosition(offset: _currentInput.length)),
          );
          setState(() { _errorIndex = indexToCheck; });
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) setState(() => _errorIndex = null);
          });
        }
      }
    }
  }

  void _handleWin() {
    HapticFeedback.heavyImpact();
    setState(() => _slotColors = List.filled(_targetWord.length, Colors.green));
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      _currentIndex++;
      _startRound();
    });
  }

  void _finishGame() {
    _gameFinished = true;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    NotificationService().onAppOpened();
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final dr = Responsive(dialogContext);
        final hasErrors = _mistakes.isNotEmpty;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(dr.spacing(20)),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(dialogContext).size.height * 0.8),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(dr.radius(24)),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: dr.spacing(28), horizontal: dr.spacing(24)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasErrors
                          ? [Colors.redAccent.withOpacity(0.15), Colors.transparent]
                          : [Colors.amber.withOpacity(0.15), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(dr.radius(24))),
                  ),
                  child: Column(
                    children: [
                      HeroIcon(
                        hasErrors ? HeroIcons.exclamationCircle : HeroIcons.trophy,
                        size: dr.iconSize(56),
                        color: hasErrors ? Colors.redAccent : Colors.amber,
                        style: HeroIconStyle.solid,
                      ),
                      SizedBox(height: dr.spacing(12)),
                      Text(
                        hasErrors
                            ? "${_mistakes.length} mistake${_mistakes.length == 1 ? '' : 's'}"
                            : S.survived,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dr.fontSize(24),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (hasErrors)
                        Padding(
                          padding: EdgeInsets.only(top: dr.spacing(4)),
                          child: Text(
                            "Review your mistakes below",
                            style: TextStyle(color: Colors.white38, fontSize: dr.fontSize(12)),
                          ),
                        ),
                    ],
                  ),
                ),

                // Mistakes list
                if (hasErrors)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(horizontal: dr.spacing(20), vertical: dr.spacing(8)),
                      itemCount: _mistakes.length,
                      itemBuilder: (ctx, i) {
                        final m = _mistakes[i];
                        final isHint = m['isHint'] == 'true';
                        return Container(
                          margin: EdgeInsets.only(bottom: dr.spacing(8)),
                          padding: EdgeInsets.symmetric(horizontal: dr.spacing(14), vertical: dr.spacing(10)),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(dr.radius(12)),
                            border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m['prompt']!,
                                style: TextStyle(color: Colors.white60, fontSize: dr.fontSize(11), letterSpacing: 0.5),
                              ),
                              SizedBox(height: dr.spacing(6)),
                              // Correct answer (always visible, full width)
                              Text(
                                m['correct']!,
                                style: TextStyle(color: AppColors.success, fontSize: dr.fontSize(15), fontWeight: FontWeight.bold),
                                softWrap: true,
                              ),
                              if (!isHint) ...[
                                SizedBox(height: dr.spacing(2)),
                                Row(
                                  children: [
                                    Text("✗  ", style: TextStyle(color: Colors.redAccent, fontSize: dr.fontSize(12))),
                                    Flexible(
                                      child: Text(
                                        m['typed']!,
                                        style: TextStyle(color: Colors.redAccent.withOpacity(0.7), fontSize: dr.fontSize(12), decoration: TextDecoration.lineThrough, decorationColor: Colors.redAccent),
                                        softWrap: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                SizedBox(height: dr.spacing(2)),
                                Text("💡 hint used", style: TextStyle(color: Colors.amber.withOpacity(0.7), fontSize: dr.fontSize(11), fontStyle: FontStyle.italic)),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                // Exit button
                Padding(
                  padding: EdgeInsets.all(dr.spacing(20)),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(vertical: dr.spacing(14)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(dr.radius(14))),
                        elevation: 0,
                      ),
                      onPressed: () { Navigator.pop(dialogContext); Navigator.pop(context); },
                      child: Text(S.exit, style: TextStyle(fontSize: dr.fontSize(15), fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _useHint() {
    setState(() => _showHint = !_showHint);
    if (_showHint) {
      HapticFeedback.lightImpact();
      // In hardcore mode, using hint counts as a mistake
      if (widget.isHardcore && !_hintUsedThisRound) {
        _hintUsedThisRound = true;
        _mistakes.add({
          'prompt': _promptWord,
          'typed': '(hint used)',
          'correct': _audioTargetWord,
          'isHint': 'true',
        });
      }
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showHint = false);
      });
    }
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
            ),
          )
        ],
      ),
      body: SingleChildScrollView(child: Column(children: [
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
          GestureDetector(
            onTap: () {
              FocusScope.of(context).requestFocus(_focusNode);
              SystemChannels.textInput.invokeMethod('TextInput.show');
            },
            child: Container(padding: EdgeInsets.symmetric(horizontal: r.spacing(16)), alignment: Alignment.center, child: Wrap(alignment: WrapAlignment.center, spacing: r.spacing(6), runSpacing: r.spacing(8), children: List.generate(_targetWord.length, (index) {
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

                // SPACE INDICATOR - turns orange when user presses any key at this slot
                if (isSpace) {
                  final Color spaceColor;
                  if (_slotColors != null) {
                    spaceColor = _slotColors![index];
                  } else if (isFilled) {
                    spaceColor = AppColors.primary;
                  } else {
                    spaceColor = Colors.white.withOpacity(0.4);
                  }
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
                            color: spaceColor,
                            borderRadius: BorderRadius.circular(r.radius(2)),
                            boxShadow: isFilled && _slotColors == null ? [
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
                            color: spaceColor,
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
          })))),

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