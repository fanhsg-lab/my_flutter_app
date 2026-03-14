import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heroicons/heroicons.dart';
import 'dart:math' as math;
import '../local_db.dart';
import '../theme.dart';
import '../responsive.dart';
import '../services/app_strings.dart';
import '../utils/word_distractor.dart';

class GameQuizPage extends StatefulWidget {
  final int lessonId;
  final bool isReversed;
  final String sourceLanguage;

  const GameQuizPage({super.key, required this.lessonId, required this.isReversed, this.sourceLanguage = 'es'});

  @override
  State<GameQuizPage> createState() => _GameQuizPageState();
}

class _GameQuizPageState extends State<GameQuizPage> with TickerProviderStateMixin {

  // ── Vocabulary ────────────────────────────────────────────────────────────
  List<Map<String, String>> _vocabulary = [];
  List<Map<String, String>> _wordQueue = [];
  int _totalWordsInLesson = 0;
  bool _isLoading = true;
  final math.Random _random = math.Random();
  Map<String, String>? _currentWord;
  List<String> _options = [];
  int _correctIndex = -1;
  int _score = 0;
  int _combo = 0;
  bool _showCycleComplete = false;

  // ── Quiz state ────────────────────────────────────────────────────────────
  bool _answered = false;
  int _selectedIndex = -1;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _scoreCtrl;
  late Animation<double>   _scoreScale;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _scoreCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scoreScale = CurvedAnimation(parent: _scoreCtrl, curve: Curves.elasticOut);

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    _fetchLessonWords();
  }

  @override
  void dispose() {
    _scoreCtrl.dispose();
    _fadeCtrl.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────
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
        String en_val = (row['en'] ?? '').toString();
        if (es_val.isNotEmpty && en_val.isNotEmpty) {
          // question = the correct option to pick from choices
          // answer   = the clue shown in the big card
          // isReversed=true  → clue=en col (Greek for es-books, English for en-books), options=es col
          // isReversed=false → clue=es col (Spanish for es-books, Greek for en-books), options=en col
          String questionVal = widget.isReversed ? es_val : en_val;
          String answerVal   = widget.isReversed ? en_val : es_val;
          loadedWords.add({'id': id, 'question': questionVal, 'answer': answerVal});
        }
      }

      if (mounted) {
        setState(() {
          _vocabulary = loadedWords;
          _totalWordsInLesson = loadedWords.length;
          _wordQueue = List.from(_vocabulary)..shuffle(_random);
          _isLoading = false;
        });
        if (_vocabulary.isNotEmpty) _setupQuestion();
      }
    } catch (e) {
      debugPrint("Game Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupQuestion() {
    if (_wordQueue.isEmpty) {
      setState(() => _showCycleComplete = true);
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _wordQueue = List.from(_vocabulary)..shuffle(_random);
          setState(() => _showCycleComplete = false);
          _setupQuestion();
        }
      });
      return;
    }

    final nextWord = _wordQueue.removeAt(0);
    final correctSpelling = nextWord['question']!;
    final distractors = WordDistractorGenerator.generate(correctSpelling, widget.sourceLanguage, count: 3);
    final allOptions = [correctSpelling, ...distractors]..shuffle(_random);
    final correctIdx = allOptions.indexOf(correctSpelling);

    _fadeCtrl.reset();
    setState(() {
      _currentWord = nextWord;
      _options = allOptions;
      _correctIndex = correctIdx;
      _answered = false;
      _selectedIndex = -1;
    });
    _fadeCtrl.forward();
  }

  // ── Quiz logic ────────────────────────────────────────────────────────────
  void _handleOptionTap(int index) {
    if (_answered) return;
    HapticFeedback.mediumImpact();
    final isCorrect = index == _correctIndex;
    if (isCorrect) {
      _score += 10 + (_combo * 5);
      _combo++;
      _scoreCtrl.reset();
      _scoreCtrl.forward();
    } else {
      _combo = 0;
      HapticFeedback.vibrate();
    }
    setState(() {
      _selectedIndex = index;
      _answered = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _setupQuestion();
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _vocabulary.isEmpty
                ? Center(child: Text(S.noWordsInLessonGame,
                    style: TextStyle(color: Colors.white, fontSize: r.fontSize(16))))
                : Column(children: [
                    _buildTopBar(r),
                    Expanded(child: _buildQuizContent(r)),
                  ]),
      ),
    );
  }

  Widget _buildTopBar(Responsive r) {
    final done = _totalWordsInLesson - _wordQueue.length;
    final progress = _totalWordsInLesson > 0 ? done / _totalWordsInLesson : 0.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(12)),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: HeroIcon(HeroIcons.xMark, color: Colors.white54,
              size: r.iconSize(24), style: HeroIconStyle.outline),
        ),
        SizedBox(width: r.spacing(14)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(r.radius(6)),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: r.scale(7),
            ),
          ),
        ),
        SizedBox(width: r.spacing(14)),
        ScaleTransition(
          scale: _scoreScale,
          child: Text('$_score',
              style: TextStyle(color: AppColors.primary,
                  fontSize: r.fontSize(18), fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  Widget _buildQuizContent(Responsive r) {
    if (_showCycleComplete) return _buildCycleComplete(r);
    if (_currentWord == null) return const SizedBox();
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(r.spacing(20), r.spacing(20), r.spacing(20), r.spacing(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: EdgeInsets.symmetric(vertical: r.spacing(44), horizontal: r.spacing(24)),
            margin: EdgeInsets.only(bottom: r.spacing(36)),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(r.radius(20)),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Text(_currentWord!['answer']!, textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: r.fontSize(30),
                fontWeight: FontWeight.w800)),
          ),
          ...List.generate(_options.length, (i) => _buildOptionButton(r, i)),
        ]),
      ),
    );
  }

  Widget _buildOptionButton(Responsive r, int index) {
    Color bgColor = AppColors.cardColor;
    Color borderColor = Colors.white.withOpacity(0.1);
    Color textColor = Colors.white;
    Widget? trailingIcon;

    if (_answered) {
      if (index == _correctIndex) {
        bgColor = const Color(0xFF1A3A1A);
        borderColor = AppColors.success;
        trailingIcon = HeroIcon(HeroIcons.check, color: AppColors.success,
            size: r.iconSize(20), style: HeroIconStyle.solid);
      } else if (index == _selectedIndex) {
        bgColor = const Color(0xFF3A1A1A);
        borderColor = AppColors.error;
        textColor = Colors.white60;
        trailingIcon = HeroIcon(HeroIcons.xMark, color: AppColors.error,
            size: r.iconSize(20), style: HeroIconStyle.solid);
      } else {
        textColor = Colors.white38;
      }
    }

    return GestureDetector(
      onTap: () => _handleOptionTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: r.spacing(12)),
        padding: EdgeInsets.symmetric(vertical: r.spacing(18), horizontal: r.spacing(20)),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(r.radius(14)),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Text(_options[index], textAlign: TextAlign.center,
            style: TextStyle(color: textColor, fontSize: r.fontSize(18),
              fontWeight: FontWeight.w600)),
          if (trailingIcon != null) Positioned(right: 0, child: trailingIcon),
        ]),
      ),
    );
  }

  Widget _buildCycleComplete(Responsive r) {
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: r.spacing(40), vertical: r.spacing(32)),
        margin: EdgeInsets.all(r.spacing(24)),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
          borderRadius: BorderRadius.circular(r.radius(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          HeroIcon(HeroIcons.trophy, color: Colors.white,
              size: r.iconSize(60), style: HeroIconStyle.solid),
          SizedBox(height: r.spacing(16)),
          Text(S.cycleComplete,
              style: TextStyle(color: Colors.white, fontSize: r.fontSize(26),
                  fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          SizedBox(height: r.spacing(8)),
          Text(S.allWordsReviewed,
              style: TextStyle(color: Colors.white.withOpacity(0.85),
                  fontSize: r.fontSize(15), fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
