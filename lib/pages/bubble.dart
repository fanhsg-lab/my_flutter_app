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

// Greek syllable-aware soft hyphenation.
// Inserts \u00AD at valid break points so Flutter wraps words correctly.
String greekHyphenate(String input) {
  // Process each word separately, preserve spaces
  return input.split(' ').map(_hyphenateWord).join(' ');
}

String _hyphenateWord(String word) {
  if (word.length <= 3) return word;

  // Greek diphthongs — treated as single vowel units, never split
  const diphthongs = ['αι', 'ει', 'οι', 'ου', 'αυ', 'ευ', 'ηυ',
                       'Αι', 'Ει', 'Οι', 'Ου', 'Αυ', 'Ευ', 'Ηυ',
                       'ΑΙ', 'ΕΙ', 'ΟΙ', 'ΟΥ', 'ΑΥ', 'ΕΥ', 'ΗΥ'];
  const vowels = 'αεηιουωάέήίόύώΑΕΗΙΟΥΩΆΈΉΊΌΎΏϊϋΐΰ';

  // Consonant clusters that can start a Greek word (kept together)
  const validOnsets = {
    'μπ', 'ντ', 'γκ', 'τσ', 'τζ',
    'βλ', 'γλ', 'κλ', 'πλ', 'φλ', 'χλ',
    'βρ', 'γρ', 'δρ', 'κρ', 'πρ', 'τρ', 'φρ', 'χρ', 'θρ',
    'σπ', 'στ', 'σκ', 'σμ', 'σν', 'σφ', 'σχ', 'σθ', 'σβ',
    'πν', 'μν', 'κν', 'γν', 'θν',
    'κτ', 'φτ', 'χτ', 'πτ',
    'σπρ', 'στρ', 'σκρ', 'σπλ', 'σκλ',
  };

  bool isVowel(String ch) => vowels.contains(ch);

  // Parse word into tokens: each token is either a diphthong or a single char
  // tagged as vowel (V) or consonant (C)
  List<String> tokens = [];
  List<bool> isV = [];
  int i = 0;
  while (i < word.length) {
    // Check for diphthong (2-char)
    if (i + 1 < word.length) {
      final pair = word.substring(i, i + 2);
      if (diphthongs.contains(pair)) {
        tokens.add(pair);
        isV.add(true);
        i += 2;
        continue;
      }
    }
    final ch = word[i];
    tokens.add(ch);
    isV.add(isVowel(ch));
    i++;
  }

  // Find syllable boundaries between tokens
  // A break point goes between token[j] and token[j+1]
  Set<int> breaks = {};

  // Walk through and find V-C...C-V patterns
  for (int j = 0; j < tokens.length; j++) {
    if (!isV[j]) continue; // find a vowel

    // Collect consonants after this vowel
    int cStart = j + 1;
    int cEnd = cStart;
    while (cEnd < tokens.length && !isV[cEnd]) {
      cEnd++;
    }
    if (cEnd >= tokens.length) break; // no vowel after consonants
    int numC = cEnd - cStart;
    if (numC == 0) {
      // Two vowels adjacent (not a diphthong) — break between them
      breaks.add(cStart);
    } else if (numC == 1) {
      // V-C-V → break before C (C goes with next vowel)
      breaks.add(cStart);
    } else {
      // Multiple consonants — find the split point
      // Try giving as many consonants as possible to the next syllable
      // by checking if they form a valid onset
      int splitAt = cStart + 1; // default: first C goes left
      for (int k = cStart; k < cEnd; k++) {
        final cluster = tokens.sublist(k, cEnd).join().toLowerCase();
        if (validOnsets.contains(cluster)) {
          splitAt = k;
          break;
        }
      }
      // Don't split double consonants together — split between them
      if (numC == 2 && tokens[cStart].toLowerCase() == tokens[cStart + 1].toLowerCase()) {
        splitAt = cStart + 1;
      }
      if (splitAt > cStart && splitAt < cEnd) {
        breaks.add(splitAt);
      } else {
        breaks.add(cStart); // fallback
      }
    }
  }

  // Don't leave a single character alone at start or end
  breaks.remove(1); // don't break after first token if it's a single char
  if (tokens.length > 1) {
    breaks.remove(tokens.length - 1); // don't break before last token
  }

  // Build result with soft hyphens at break points
  final buf = StringBuffer();
  for (int j = 0; j < tokens.length; j++) {
    if (breaks.contains(j)) buf.write('\u00AD');
    buf.write(tokens[j]);
  }
  return buf.toString();
}

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
  double _userLearningRate = 2.6;

  final FlutterTts _flutterTts = FlutterTts();

  int _currentIndex = 0;
  int _sessionCorrect = 0;
  int _sessionWrong = 0;
  int _totalWordsInLesson = 0;
  int _wordsUnseen = 0;
  int _wordsDue = 0;
  int _wordsLearning = 0;
  int _wordsMastered = 0;

  double _dragDistance = 0.0;
  final double _triggerThreshold = 150.0;
  bool _isDragging = false;
  bool _soundEnabled = true;

  late final AnimationController _popController;
  late final Animation<double> _scaleAnimation;

  late final AnimationController _sparkleController;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  late final AnimationController _progressController;

  late final AnimationController _scoreController;
  late final Animation<double> _scoreBounce;

  // Drag hint animation
  late final AnimationController _hintController;
  bool _showHint = false;
  bool _hasTouched = false;   // user touched screen at all
  bool _hasAnswered = false;  // user completed a drag answer
  bool _hintGoingUp = true;   // alternates: up first, then down

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSessionData();

    // Pop animation - smooth scale transition
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
      value: 1.0,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _popController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );

    // Sparkle explosion animation
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Shake animation for wrong answers
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeOut)
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

    // Drag hint — loops a finger-swipe-up animation
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _hintController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _showHint && !_hasAnswered) {
        // Alternate direction: up → down → up → down → ...
        _hintGoingUp = !_hintGoingUp;
        _hintController.forward(from: 0.0);
      }
    });

    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage(widget.sourceLanguage == 'en' ? "en-US" : "es-ES");
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      _flutterTts.setErrorHandler((msg) {
        debugPrint("TTS error: $msg");
      });
    } catch (e) {
      debugPrint("TTS init error: $e");
    }
  }

  void _scheduleHint() {
    if (_hasAnswered) return;
    // 2s if never touched, 5s if touched but hasn't answered yet
    final delay = _hasTouched ? 5 : 2;
    Future.delayed(Duration(seconds: delay), () {
      if (mounted && !_hasAnswered && !_isDragging && _currentIndex < _queue.length) {
        _hintGoingUp = true; // always start with swipe-up
        setState(() => _showHint = true);
        _hintController.forward(from: 0.0);
      }
    });
  }

  void _cancelHint() {
    if (_showHint) {
      _hintController.stop();
      setState(() => _showHint = false);
    }
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
    _hintController.dispose();
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

    // 4. Refresh lesson state stats so finished screen shows post-session counts
    await _refreshFinishedStats();
  }

  Future<void> _refreshFinishedStats() async {
    try {
      final db = await LocalDB.instance.database;
      final userId = Supabase.instance.client.auth.currentUser?.id ?? 'unknown';
      final wordsData = await db.rawQuery('''
        SELECT w.id FROM lesson_words lw
        JOIN words w ON w.id = lw.word_id
        WHERE lw.lesson_id = ?
      ''', [widget.lessonId]);
      final progressData = await db.query('user_progress', where: 'user_id = ?', whereArgs: [userId]);
      final progressMap = { for (var p in progressData) p['word_id'] as int: p };

      int unseen = 0, due = 0, learning = 0;
      final now = DateTime.now().toUtc();

      for (var word in wordsData) {
        final wordId = word['id'] as int;
        final progress = progressMap[wordId];
        final status = progress?['status'] as String? ?? 'new';
        final nextDueRaw = progress?['next_due_at'];
        final nextDue = nextDueRaw != null ? DateTime.parse(nextDueRaw as String).toUtc() : null;
        final isTimeUp = nextDue == null || nextDue.isBefore(now);

        if (status == 'learning') learning++;
        else if ((status == 'consolidating' || status == 'learned') && isTimeUp) due++;
        else if (status == 'new' || progress == null) unseen++;
      }

      final mastered = wordsData.length - unseen - due - learning;
      if (mounted) {
        setState(() {
          _wordsUnseen = unseen;
          _wordsDue = due;
          _wordsLearning = learning;
          _wordsMastered = mastered;
        });
      }
    } catch (_) {}
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
      final userId = Supabase.instance.client.auth.currentUser?.id ?? 'unknown';
      final wordsData = await db.rawQuery('''
        SELECT w.* FROM lesson_words lw
        JOIN words w ON w.id = lw.word_id
        WHERE lw.lesson_id = ?
        ORDER BY w.id ASC
      ''', [widget.lessonId]);
      final progressData = await db.query('user_progress', where: 'user_id = ?', whereArgs: [userId]);
      Map<int, Map<String, dynamic>> progressMap = { for (var p in progressData) p['word_id'] as int: p };

      List<Map<String, dynamic>> reviewQueue = []; 
      List<Map<String, dynamic>> learningQueue = []; 
      List<Map<String, dynamic>> newQueue = []; 
      DateTime now = DateTime.now().toUtc();

      debugPrint('🃏 Bubble load — lessonId=${widget.lessonId}, total words=${wordsData.length}');
      for (var word in wordsData) {
        int wordId = word['id'] as int;
        var progress = progressMap[wordId];
        String status = progress?['status'] as String? ?? 'new';
        DateTime? nextDue = progress?['next_due_at'] != null ? DateTime.parse(progress!['next_due_at'] as String).toUtc() : null;
        bool isTimeUp = nextDue == null || nextDue.isBefore(now);

        String bucket;
        if (status == 'learning') bucket = 'learningQueue';
        else if ((status == 'consolidating' || status == 'learned') && isTimeUp) bucket = 'reviewQueue';
        else if (status == 'new' || progress == null) bucket = 'newQueue';
        else bucket = 'SKIPPED (mastered, not due until ${nextDue?.toLocal()})';

        debugPrint('   word $wordId [${word['es']}/${word['en']}] status=$status isTimeUp=$isTimeUp → $bucket');

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
        // else: consolidating/learned but not yet due — skipped
      }

      // Snapshot lesson state before selection consumes the queues
      final int snapshotUnseen = newQueue.length;
      final int snapshotDue = reviewQueue.length;
      final int snapshotLearning = learningQueue.length;
      // mastered = total − the three above (consolidating/learned but not yet due)
      final int snapshotMastered = wordsData.length - snapshotUnseen - snapshotDue - snapshotLearning;

      List<Map<String, dynamic>> finalSelection = [];
      while (finalSelection.length < 8 && reviewQueue.isNotEmpty) finalSelection.add(reviewQueue.removeAt(0));
      while (finalSelection.length < 10 && learningQueue.isNotEmpty) finalSelection.add(learningQueue.removeAt(0));
      while (finalSelection.length < 10 && newQueue.isNotEmpty) finalSelection.add(newQueue.removeAt(0));
      while (finalSelection.length < 10 && reviewQueue.isNotEmpty) finalSelection.add(reviewQueue.removeAt(0));

      finalSelection.shuffle();

      debugPrint('🎯 Final selection (${finalSelection.length} words):');
      for (var item in finalSelection) {
        debugPrint('   → word ${item['word_id']} [${item['front']}/${item['reveal']}] status=${item['status']}');
      }

      if (mounted) {
        setState(() {
          _queue = finalSelection;
          _totalWordsInLesson = wordsData.length;
          _wordsUnseen = snapshotUnseen;
          _wordsDue = snapshotDue;
          _wordsLearning = snapshotLearning;
          _wordsMastered = snapshotMastered;
          _isLoading = false;
        });
        _scheduleHint();
      }
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
    _hasAnswered = true;
    _cancelHint();

    if (isUp) {
      // Correct answer
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

  String _stripArticle(String text) {
    const articles = ['el ', 'la ', 'los ', 'las ', 'un ', 'una ', 'unos ', 'unas '];
    final lower = text.toLowerCase();
    for (final article in articles) {
      if (lower.startsWith(article)) return text.substring(article.length).trim();
    }
    return text;
  }

  Future<void> _speak() async {
    // Always speak the source-language word (not Greek).
    // English books have swapped columns, so the speak logic is inverted.
    final bool speakReveal = widget.sourceLanguage == 'en' ? !widget.isReversed : widget.isReversed;
    String text = speakReveal ? currentItem['reveal'] : currentItem['front'];
    text = _stripArticle(text);
    if (text.isNotEmpty && text != S.finished) {
      try { await _flutterTts.speak(text); } catch (e) { debugPrint("TTS speak error: $e"); }
    }
  }

  Future<void> _autoSpeak(Map<String, dynamic> item) async {
    if (!_soundEnabled) return;
    final bool speakReveal = widget.sourceLanguage == 'en' ? !widget.isReversed : widget.isReversed;
    String text = speakReveal ? item['reveal'] : item['front'];
    text = _stripArticle(text);
    if (text.isNotEmpty && text != S.finished) {
      try { await _flutterTts.speak(text); } catch (e) { debugPrint("TTS speak error: $e"); }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));

    // --- FINISHED SCREEN ---
    if (_currentIndex >= _queue.length) {
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

                  // Lesson state stats
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 80, child: Center(child: _buildStatCard(S.newUpper, _wordsUnseen, AppColors.primary))),
                        const SizedBox(width: 20),
                        SizedBox(width: 80, child: Center(child: _buildStatCard(S.review, _wordsDue + _wordsLearning, Colors.redAccent))),
                        const SizedBox(width: 20),
                        SizedBox(width: 80, child: Center(child: _buildStatCard(S.masteredUpper, _wordsMastered, AppColors.success))),
                      ],
                    ),
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
    String rawText = _isDragging ? currentItem['reveal'] : currentItem['front'];
    String displayedText = greekHyphenate(rawText);

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
          _hasTouched = true;
          _cancelHint();
          setState(() => _isDragging = true);
          _autoSpeak(currentItem);
        },
        onPanUpdate: (details) {
          setState(() => _dragDistance += details.delta.dy);
        },
        onPanEnd: (_) {
          if (_dragDistance <= -_triggerThreshold) _handleAction(isUp: true);
          else if (_dragDistance >= _triggerThreshold) _handleAction(isUp: false);
          else {
            setState(() { _dragDistance = 0.0; _isDragging = false; });
            // Touched but didn't answer — reschedule hint with 5s delay
            if (!_hasAnswered) _scheduleHint();
          }
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
                    
                    // Sound Toggle Button (Top Left)
                    Builder(
                      builder: (context) {
                        final r = Responsive(context);
                        return Positioned(
                          top: r.spacing(20),
                          left: r.spacing(20),
                          child: FloatingActionButton.small(
                            heroTag: "speak",
                            backgroundColor: _soundEnabled ? AppColors.primary : Colors.white24,
                            elevation: 4,
                            onPressed: () => setState(() => _soundEnabled = !_soundEnabled),
                            child: HeroIcon(
                              _soundEnabled ? HeroIcons.speakerWave : HeroIcons.speakerXMark,
                              color: _soundEnabled ? Colors.black : Colors.white54,
                              size: r.iconSize(24),
                              style: HeroIconStyle.solid,
                            ),
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

                    // (Sparkles removed)

                    // Drag hint animation
                    if (_showHint)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _hintController,
                            builder: (context, _) {
                              final t = _hintController.value;
                              final goingUp = _hintGoingUp;
                              // Movement: finger slides from center outward
                              final yOffset = goingUp
                                  ? 60.0 - (120.0 * t)   // upward
                                  : -60.0 + (120.0 * t);  // downward
                              // Fade in 0..0.2, visible 0.2..0.7, fade out 0.7..1.0
                              double opacity;
                              if (t < 0.2) {
                                opacity = t / 0.2;
                              } else if (t < 0.7) {
                                opacity = 1.0;
                              } else {
                                opacity = 1.0 - ((t - 0.7) / 0.3);
                              }
                              final clampedOpacity = opacity.clamp(0.0, 1.0);
                              // Target icon that appears at the destination
                              final targetColor = goingUp ? AppColors.success : Colors.redAccent;
                              final targetIcon = goingUp ? Icons.check_circle : Icons.cancel;
                              final targetAlign = goingUp
                                  ? const Alignment(0.0, -0.65)
                                  : const Alignment(0.0, 0.55);
                              return Stack(
                                children: [
                                  // Target icon (check/x) at top/bottom
                                  Align(
                                    alignment: targetAlign,
                                    child: Opacity(
                                      opacity: clampedOpacity * 0.5,
                                      child: Icon(
                                        targetIcon,
                                        color: targetColor,
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                  // Finger swipe icon
                                  Align(
                                    alignment: const Alignment(0.0, 0.05),
                                    child: Transform.translate(
                                      offset: Offset(0, yOffset),
                                      child: Opacity(
                                        opacity: clampedOpacity * 0.7,
                                        child: Icon(
                                          goingUp ? Icons.swipe_up_rounded : Icons.swipe_down_rounded,
                                          color: Colors.white,
                                          size: 64,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
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
                      fontSize: r.fontSize(32),
                      fontWeight: FontWeight.w700,
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
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (context, animVal, _) {
            return Text(
              '${animVal.round()}$suffix',
              style: TextStyle(
                fontSize: r.fontSize(28),
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: r.fontSize(11),
            fontWeight: FontWeight.w500,
            color: Colors.white54,
            letterSpacing: 0.8,
          ),
        ),
      ],
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
          crossAxisAlignment: CrossAxisAlignment.center,
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
  DateTime? _lastTick;

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
    final elapsed = _lastTick != null ? now.difference(_lastTick!).inMilliseconds : 16;
    final dt = (elapsed / 16.0).clamp(0.5, 3.0);
    _lastTick = now;

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
          b.popProgress += 0.06 * dt;
          if (b.popProgress >= 1.0) {
            _bubbles.removeAt(i);
            continue;
          }
        } else {
          b.y -= b.speed * dt;
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