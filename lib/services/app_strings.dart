import '../local_db.dart';
import 'package:flutter/material.dart';

/// Simple localization class. Access strings via `S.learn`, `S.profile`, etc.
/// Change language with `S.setLocale('el')` or `S.setLocale('en')`.
class S {
  static String _locale = 'en';
  static VoidCallback? _onLocaleChanged;

  static String get locale => _locale;

  /// Call once at app startup to load saved language.
  static Future<void> load() async {
    _locale = await LocalDB.instance.getLanguage() ?? 'en';
  }

  /// Register a callback to rebuild the app when locale changes.
  static void setOnLocaleChanged(VoidCallback callback) {
    _onLocaleChanged = callback;
  }

  /// Change locale, persist, and trigger app rebuild.
  static Future<void> setLocale(String locale) async {
    if (locale == _locale) return; // Already set
    _locale = locale;
    await LocalDB.instance.setLanguage(locale);
    _onLocaleChanged?.call();
  }

  // ========================
  // NAVIGATION
  // ========================
  static String get learn => _t('learn');
  static String get stats => _t('stats');
  static String get library => _t('library');
  static String get profile => _t('profile');
  static String get profileTitle => _t('profileTitle');

  // ========================
  // MAIN SCREEN
  // ========================
  static String get beginnerCourse => _t('beginnerCourse');
  static String get noLessonsFound => _t('noLessonsFound');
  static String get selectBook => _t('selectBook');
  static String get tapToSelectBook => _t('tapToSelectBook');
  static String get quickStats => _t('quickStats');
  static String get dayStreak => _t('dayStreak');
  static String get wordsLearned => _t('wordsLearned');
  static String get keepGoing => _t('keepGoing');
  static String get selectTeacherBook => _t('selectTeacherBook');
  static String get tapTeacherHint => _t('tapTeacherHint');
  static String get noTeachers => _t('noTeachers');
  static String get books => _t('books');
  static String get lessons => _t('lessons');
  static String get chapter => _t('chapter');
  static String get mastered => _t('mastered');
  static String get review => _t('review');
  static String get newWord => _t('newWord');
  static String get selectMode => _t('selectMode');
  static String get game => _t('game');
  static String get test => _t('test');
  static String get survival => _t('survival');
  static String get startLesson => _t('startLesson');
  static String get chooseMode => _t('chooseMode');
  static String get reviewMode => _t('reviewMode');
  static String get onlyDueWords => _t('onlyDueWords');
  static String get practiceMode => _t('practiceMode');
  static String get allWordsFromLesson => _t('allWordsFromLesson');
  static String get upcomingReviews => _t('upcomingReviews');

  // Forecast labels
  static String get late_ => _t('late');
  static String get tmrw => _t('tmrw');

  // ========================
  // PROFILE
  // ========================
  static String get loading => _t('loading');
  static String get noEmail => _t('noEmail');
  static String get beginnerStudent => _t('beginnerStudent');
  static String get settings => _t('settings');
  static String get notifications => _t('notifications');
  static String get language => _t('language');
  static String get repairApp => _t('repairApp');
  static String get appRepaired => _t('appRepaired');
  static String get logOut => _t('logOut');
  static String get notificationsOff => _t('notificationsOff');
  static String get enable => _t('enable');
  static String get errorSigningOut => _t('errorSigningOut');
  static String get displayName => _t('displayName');
  static String get enterName => _t('enterName');
  static String get save => _t('save');
  static String get cancel => _t('cancel');
  static String get account => _t('account');
  static String get student => _t('student');
  static String get helpCenter => _t('helpCenter');
  static String get contactDeveloper => _t('contactDeveloper');
  static String get contactMessage => _t('contactMessage');
  static String get howItWorks => _t('howItWorks');
  static String get howItWorksSubtitle => _t('howItWorksSubtitle');
  static String get sendEmail => _t('sendEmail');
  static String get couldNotOpenEmail => _t('couldNotOpenEmail');
  static String get feedbackHint => _t('feedbackHint');
  static String get feedbackSent => _t('feedbackSent');
  static String get send => _t('send');

  // ========================
  // STATISTICS
  // ========================
  static String get statistics => _t('statistics');
  static String get error => _t('error');
  static String get thisBook => _t('thisBook');
  static String get thisTeacher => _t('thisTeacher');
  static String get all => _t('all');
  static String get words => _t('words');
  static String get retention => _t('retention');
  static String get days => _t('days');
  static String get progress => _t('progress');
  static String get thisWeek => _t('thisWeek');
  static String get velocity => _t('velocity');
  static String get last_ => _t('last');
  static String get forecast => _t('forecast');
  static String get memoryStrength => _t('memoryStrength');
  static String get activity => _t('activity');
  static String get selectedDate => _t('selectedDate');
  static String get learning => _t('learning');
  static String get total => _t('total');
  static String get avgDay => _t('avgDay');
  static String get today => _t('today');
  static String get recentWk => _t('recentWk');
  static String get slippingMo => _t('slippingMo');
  static String get lostMo => _t('lostMo');
  static String get notEnoughData => _t('notEnoughData');
  static String get infoProgress => _t('infoProgress');
  static String get infoThisWeek => _t('infoThisWeek');
  static String get infoVelocity => _t('infoVelocity');
  static String get infoForecast => _t('infoForecast');
  static String get infoMemoryStrength => _t('infoMemoryStrength');
  static String get infoActivity => _t('infoActivity');
  static String get masteredUpper => _t('masteredUpper');
  static String get learningUpper => _t('learningUpper');
  static String get newUpper => _t('newUpper');
  static String get totalUpper => _t('totalUpper');

  // Day names (short)
  static List<String> get dayNames => _locale == 'el'
      ? ['Δευ', 'Τρι', 'Τετ', 'Πεμ', 'Παρ', 'Σαβ', 'Κυρ']
      : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Forecast labels for statistics
  static List<String> get forecastLabels => _locale == 'el'
      ? ['Καθυστ.', 'Αύριο', '+2μ', '+3μ', '+4μ', '+5μ', '+6μ']
      : ['Late', 'Tmro', '+2d', '+3d', '+4d', '+5d', '+6d'];

  // Forecast labels for main screen card
  static List<String> get forecastLabelsCard => _locale == 'el'
      ? ['Καθυστ.', 'Αύριο', '+2μ', '+3μ', '+4μ', '+5μ', '+6μ']
      : ['Late', 'Tmrw', '+2d', '+3d', '+4d', '+5d', '+6d'];

  // ========================
  // BUBBLE (TEST MODE)
  // ========================
  static String get sessionComplete => _t('sessionComplete');
  static String get correct => _t('correct');
  static String get accuracy => _t('accuracy');
  static String get continueBtn => _t('continueBtn');
  static String get mainMenu => _t('mainMenu');
  static String get finished => _t('finished');
  static String get goodJob => _t('goodJob');

  // ========================
  // SURVIVAL MODE
  // ========================
  static String get ok => _t('ok');
  static String get pleaseLogIn => _t('pleaseLogIn');
  static String get noWordsInLesson => _t('noWordsInLesson');
  static String get noWordsDueReview => _t('noWordsDueReview');
  static String get noValidWords => _t('noValidWords');
  static String get translate => _t('translate');
  static String get practice => _t('practice');
  static String get space => _t('space');
  static String get hintCost => _t('hintCost');
  static String get survived => _t('survived');
  static String get gameOver => _t('gameOver');
  static String get finalScore => _t('finalScore');
  static String get exit => _t('exit');
  static String get initializing => _t('initializing');

  // ========================
  // LIBRARY
  // ========================
  static String get libraryTitle => _t('libraryTitle');
  static String get noLessonsInBook => _t('noLessonsInBook');
  static String get spanish => _t('spanish');
  static String get english => _t('english');
  static String get greek => _t('greek');
  static String nWords(int n) => '$n ${_t('wordsLower')}';

  /// Returns the display name for a source language code ('es' -> 'Spanish', 'en' -> 'English')
  static String sourceLanguageName(String code) {
    switch (code) {
      case 'en': return english;
      case 'es': return spanish;
      default: return spanish;
    }
  }

  /// Returns a short label for source language code ('es' -> 'Esp', 'en' -> 'Eng')
  static String sourceLanguageShort(String code) {
    switch (code) {
      case 'en': return 'Eng';
      case 'es': return 'Esp';
      default: return 'Esp';
    }
  }

  // ========================
  // SUBSCRIPTION
  // ========================
  static String get subscription => _t('subscription');
  static String get palabraPremium => _t('palabraPremium');
  static String get freeTrialDaysLeft => _t('freeTrialDaysLeft');
  static String get daysLeft => _t('daysLeft');
  static String get trialExpired => _t('trialExpired');
  static String get unlockLearning => _t('unlockLearning');
  static String get monthly => _t('monthly');
  static String get yearly => _t('yearly');
  static String get perMonth => _t('perMonth');
  static String get perYear => _t('perYear');
  static String get save33 => _t('save33');
  static String get subscribe => _t('subscribe');
  static String get restorePurchases => _t('restorePurchases');
  static String get manageSub => _t('manageSub');
  static String get renewsOn => _t('renewsOn');
  static String get expiresOn => _t('expiresOn');
  static String get active => _t('active');
  static String get startFreeTrial => _t('startFreeTrial');
  static String get expired => _t('expired');
  static String trialDaysN(int n) => '$n ${_t('daysLeft')}';

  // ========================
  // GAME MODE
  // ========================
  static String get left => _t('left');
  static String get pts => _t('pts');
  static String get noWordsInLessonGame => _t('noWordsInLessonGame');
  static String get cycleComplete => _t('cycleComplete');
  static String get allWordsReviewed => _t('allWordsReviewed');

  // ========================
  // DYNAMIC STRINGS
  // ========================
  static String chapterN(int n) => '${_t('chapter')} $n';
  static String nBooks(int n) => '$n ${_t('books')}';
  static String nLessons(int n) => '$n ${_t('lessons')}';
  static String lastNDays(int n) => '${_t('last')} $n ${_t('days')}';
  static String daysOf7(int n) => '$n/7';
  static String finalScoreN(int n) => '${_t('finalScore')} $n';

  // ========================
  // INTERNAL
  // ========================
  static String _t(String key) => (_locale == 'el' ? _el : _en)[key] ?? key;

  static const Map<String, String> _en = {
    // Navigation
    'learn': 'Learn',
    'stats': 'Stats',
    'library': 'Library',
    'profile': 'Profile',
    'profileTitle': 'PROFILE',

    // Main Screen
    'beginnerCourse': 'Beginner Course',
    'noLessonsFound': 'No Lessons Found',
    'selectBook': 'Select a Book',
    'tapToSelectBook': 'Tap to choose your book',
    'quickStats': '🔥 Quick Stats',
    'dayStreak': 'Day Streak',
    'wordsLearned': 'Words Learned',
    'keepGoing': 'Keep going! Consistency is key.',
    'selectTeacherBook': 'Select Teacher & Book',
    'tapTeacherHint': 'Tap a teacher to expand/collapse',
    'noTeachers': 'No teachers available yet. Sync your data first.',
    'books': 'books',
    'lessons': 'lessons',
    'chapter': 'Chapter',
    'mastered': 'Mastered',
    'review': 'Review',
    'newWord': 'New',
    'selectMode': 'SELECT MODE',
    'game': 'Game',
    'test': 'Test',
    'survival': 'Survival',
    'startLesson': 'START LESSON',
    'chooseMode': 'Choose Mode',
    'reviewMode': 'Review Mode',
    'onlyDueWords': 'Only words due for review',
    'practiceMode': 'Practice Mode',
    'allWordsFromLesson': 'All words from lesson',
    'upcomingReviews': 'Upcoming Reviews',
    'late': 'Late',
    'tmrw': 'Tmrw',

    // Profile
    'loading': 'Loading...',
    'noEmail': 'No Email',
    'beginnerStudent': 'Beginner Student',
    'settings': 'Settings',
    'notifications': 'Notifications',
    'language': 'Language',
    'repairApp': 'REPAIR APP (Kill Duplicates)',
    'appRepaired': 'App Repaired! Please restart the app completely.',
    'logOut': 'LOG OUT',
    'notificationsOff': 'Notifications are off! You might lose your streak.',
    'enable': 'ENABLE',
    'errorSigningOut': 'Error signing out:',
    'displayName': 'Display Name',
    'enterName': 'Enter your name',
    'save': 'SAVE',
    'cancel': 'CANCEL',
    'account': 'Account',
    'student': 'Student',
    'helpCenter': 'Help Center',
    'contactDeveloper': 'Contact Developer',
    'contactMessage': 'Have a question or found a bug? Send us an email!',
    'howItWorks': 'How It Works',
    'howItWorksSubtitle': 'Colors, stats, test mode & more',
    'sendEmail': 'SEND EMAIL',
    'couldNotOpenEmail': 'Could not open email client',
    'feedbackHint': 'Write your feedback here...',
    'feedbackSent': 'Thank you for your feedback!',
    'send': 'SEND',

    // Statistics
    'statistics': 'STATISTICS',
    'error': 'Error',
    'thisBook': 'This Book',
    'thisTeacher': 'This Teacher',
    'all': 'All',
    'words': 'WORDS',
    'retention': 'RETENTION',
    'days': 'DAYS',
    'progress': 'PROGRESS',
    'thisWeek': 'THIS WEEK',
    'velocity': 'VELOCITY',
    'last': 'LAST',
    'forecast': 'FORECAST',
    'memoryStrength': 'MEMORY STRENGTH',
    'activity': 'ACTIVITY',
    'selectedDate': 'SELECTED DATE',
    'learning': 'Learning',
    'total': 'TOTAL',
    'avgDay': 'AVG/DAY',
    'today': 'Today',
    'recentWk': 'THIS WEEK\n< 7 days',
    'slippingMo': 'THIS MONTH\n< 30 days',
    'lostMo': 'MONTH+\n> 30 days',
    'notEnoughData': 'Not enough data yet.',
    'infoProgress': 'Shows how your words are split between Mastered, Learning, and New. Tap any section of the donut to see the exact count for that category.',
    'infoThisWeek': 'Words you practiced over the last 7 days. Today\'s bar is highlighted in orange. Below you\'ll see your weekly total, active days, and daily average.',
    'infoVelocity': 'Orange line → total words mastered over time\nDark orange line → words currently in learning\n\nA rising orange line means your vocabulary is growing. If both lines are flat, try studying more consistently to see progress.',
    'infoForecast': 'Shows how many words are due for review each day over the next 7 days.\n\nLate (red bar) → overdue words — do these first!\n\nSmaller upcoming bars mean a lighter load. Staying consistent keeps this graph balanced.',
    'infoMemoryStrength': 'Groups your studied words by how recently they were last reviewed:\n\nRed → reviewed this week (freshest)\nDark orange → reviewed this month\nOrange → last reviewed over a month ago\n\nWords on the right are the most deeply memorized. Keep reviewing to build long-term memory.',
    'infoActivity': 'Your daily study activity over the last 2 months. Darker orange means more words practiced that day. Tap any day to see the exact count.',
    'masteredUpper': 'MASTERED',
    'learningUpper': 'LEARNING',
    'newUpper': 'NEW',
    'totalUpper': 'TOTAL',

    // Bubble
    'sessionComplete': 'Session Complete!',
    'correct': 'CORRECT',
    'accuracy': 'ACCURACY',
    'continueBtn': 'CONTINUE',
    'mainMenu': 'Main Menu',
    'finished': 'Finished!',
    'goodJob': 'Good Job',

    // Survival
    'ok': 'OK',
    'pleaseLogIn': 'Please log in to play.',
    'noWordsInLesson': 'No words found in this lesson.',
    'noWordsDueReview': 'No words due for review. Come back later!',
    'noValidWords': 'No valid words found.',
    'translate': 'TRANSLATE',
    'practice': 'PRACTICE',
    'space': 'SPACE',
    'hintCost': 'Hint (costs 1 life)',
    'survived': 'SURVIVED!',
    'gameOver': 'GAME OVER',
    'finalScore': 'Final Score:',
    'exit': 'EXIT',
    'initializing': 'Initializing...',

    // Library
    'libraryTitle': 'VOCABULARY',
    'noLessonsInBook': 'No lessons found in this book.',
    'spanish': 'Spanish',
    'english': 'English',
    'greek': 'Greek',
    'wordsLower': 'words',

    // Subscription
    'subscription': 'Subscription',
    'palabraPremium': 'Palabra Premium',
    'freeTrialDaysLeft': 'Free trial',
    'daysLeft': 'days left',
    'trialExpired': 'Your free trial has ended',
    'unlockLearning': 'Subscribe to continue learning',
    'monthly': 'Monthly',
    'yearly': 'Yearly',
    'perMonth': '/month',
    'perYear': '/year',
    'save33': 'Save 33%',
    'subscribe': 'SUBSCRIBE',
    'restorePurchases': 'Restore Purchases',
    'manageSub': 'Manage Subscription',
    'renewsOn': 'Renews on',
    'expiresOn': 'Expires on',
    'active': 'Active',
    'startFreeTrial': 'Start with a 2-month free trial!',
    'expired': 'Expired',

    // Game Mode
    'left': 'LEFT',
    'pts': 'PTS',
    'noWordsInLessonGame': 'No words in this lesson!',
    'cycleComplete': 'CYCLE COMPLETE!',
    'allWordsReviewed': 'All words reviewed!',
  };

  static const Map<String, String> _el = {
    // Navigation
    'learn': 'Μάθηση',
    'stats': 'Στατιστικά',
    'library': 'Βιβλιοθήκη',
    'profile': 'Προφίλ',
    'profileTitle': 'ΠΡΟΦΙΛ',

    // Main Screen
    'beginnerCourse': 'Μάθημα Αρχαρίων',
    'noLessonsFound': 'Δεν Βρέθηκαν Μαθήματα',
    'selectBook': 'Επιλέξτε Βιβλίο',
    'tapToSelectBook': 'Πατήστε για να επιλέξετε βιβλίο',
    'quickStats': '🔥 Στατιστικά',
    'dayStreak': 'Ημερήσιο Σερί',
    'wordsLearned': 'Λέξεις',
    'keepGoing': 'Συνέχισε! Η συνέπεια είναι το κλειδί.',
    'selectTeacherBook': 'Επιλογή Δασκάλου & Βιβλίου',
    'tapTeacherHint': 'Πάτα σε δάσκαλο για επέκταση/σύμπτυξη',
    'noTeachers': 'Δεν υπάρχουν δάσκαλοι. Συγχρόνισε τα δεδομένα σου.',
    'books': 'βιβλία',
    'lessons': 'μαθήματα',
    'chapter': 'Κεφάλαιο',
    'mastered': 'Κατακτημένες',
    'review': 'Επανάληψη',
    'newWord': 'Νέες',
    'selectMode': 'ΕΠΙΛΟΓΗ ΛΕΙΤΟΥΡΓΙΑΣ',
    'game': 'Παιχνίδι',
    'test': 'Τεστ',
    'survival': 'Επιβίωση',
    'startLesson': 'ΕΝΑΡΞΗ ΜΑΘΗΜΑΤΟΣ',
    'chooseMode': 'Επιλογή Λειτουργίας',
    'reviewMode': 'Επανάληψη',
    'onlyDueWords': 'Μόνο λέξεις για επανάληψη',
    'practiceMode': 'Εξάσκηση',
    'allWordsFromLesson': 'Όλες οι λέξεις του μαθήματος',
    'upcomingReviews': 'Επερχόμενες Επαναλήψεις',
    'late': 'Καθυστ.',
    'tmrw': 'Αύριο',

    // Profile
    'loading': 'Φόρτωση...',
    'noEmail': 'Χωρίς Email',
    'beginnerStudent': 'Αρχάριος Μαθητής',
    'settings': 'Ρυθμίσεις',
    'notifications': 'Ειδοποιήσεις',
    'language': 'Γλώσσα',
    'repairApp': 'ΕΠΙΔΙΟΡΘΩΣΗ (Διαγραφή Διπλοτύπων)',
    'appRepaired': 'Επιδιορθώθηκε! Κάνε πλήρη επανεκκίνηση.',
    'logOut': 'ΑΠΟΣΥΝΔΕΣΗ',
    'notificationsOff': 'Οι ειδοποιήσεις είναι κλειστές! Μπορεί να χάσεις το σερί σου.',
    'enable': 'ΕΝΕΡΓΟΠΟΙΗΣΗ',
    'errorSigningOut': 'Σφάλμα αποσύνδεσης:',
    'displayName': 'Όνομα',
    'enterName': 'Εισάγετε το όνομά σας',
    'save': 'ΑΠΟΘΗΚΕΥΣΗ',
    'cancel': 'ΑΚΥΡΩΣΗ',
    'account': 'Λογαριασμός',
    'student': 'Μαθητής',
    'helpCenter': 'Κέντρο Βοήθειας',
    'contactDeveloper': 'Επικοινωνία με τον Δημιουργό',
    'contactMessage': 'Έχεις ερώτηση ή βρήκες πρόβλημα; Στείλε μας email!',
    'howItWorks': 'Πώς Λειτουργεί',
    'howItWorksSubtitle': 'Χρώματα, στατιστικά, λειτουργία τεστ & άλλα',
    'sendEmail': 'ΑΠΟΣΤΟΛΗ EMAIL',
    'couldNotOpenEmail': 'Δεν ήταν δυνατό το άνοιγμα email',
    'feedbackHint': 'Γράψε το σχόλιό σου εδώ...',
    'feedbackSent': 'Ευχαριστούμε για το σχόλιό σου!',
    'send': 'ΑΠΟΣΤΟΛΗ',

    // Statistics
    'statistics': 'ΣΤΑΤΙΣΤΙΚΑ',
    'error': 'Σφάλμα',
    'thisBook': 'Αυτό το Βιβλίο',
    'thisTeacher': 'Ο Δάσκαλος',
    'all': 'Όλα',
    'words': 'ΛΕΞΕΙΣ',
    'retention': 'ΔΙΑΤΗΡΗΣΗ',
    'days': 'ΗΜΕΡΕΣ',
    'progress': 'ΠΡΟΟΔΟΣ',
    'thisWeek': 'ΑΥΤΗ ΤΗ ΒΔΟΜΑΔΑ',
    'velocity': 'ΤΑΧΥΤΗΤΑ',
    'last': 'ΤΕΛΕΥΤΑΙΕΣ',
    'forecast': 'ΠΡΟΒΛΕΨΗ',
    'memoryStrength': 'ΙΣΧΥΣ ΜΝΗΜΗΣ',
    'activity': 'ΔΡΑΣΤΗΡΙΟΤΗΤΑ',
    'selectedDate': 'ΕΠΙΛΕΓΜΕΝΗ ΗΜΕΡΑ',
    'learning': 'Εκμάθηση',
    'total': 'ΣΥΝΟΛΟ',
    'avgDay': 'ΜΕΣ/ΗΜΕΡΑ',
    'today': 'Σήμερα',
    'recentWk': 'ΕΒΔΟΜΑΔΑ\n< 7 μέρες',
    'slippingMo': 'ΜΗΝΑΣ\n< 30 μέρες',
    'lostMo': 'ΜΗΝΑΣ+\n> 30 μέρες',
    'notEnoughData': 'Δεν υπάρχουν αρκετά δεδομένα.',
    'infoProgress': 'Δείχνει πώς κατανέμονται οι λέξεις σου σε Κατακτημένες, Εκμάθηση και Νέες. Πάτα σε τμήμα του γραφήματος για να δεις τον ακριβή αριθμό.',
    'infoThisWeek': 'Λέξεις που εξάσκησες τις τελευταίες 7 μέρες. Η σημερινή μπάρα είναι πορτοκαλί. Παρακάτω βλέπεις σύνολο, ενεργές μέρες και ημερήσιο μέσο όρο.',
    'infoVelocity': 'Πορτοκαλί γραμμή → λέξεις που κατέκτησες συνολικά\nΣκούρο πορτοκαλί → λέξεις που μαθαίνεις τώρα\n\nΑνερχόμενη πορτοκαλί γραμμή σημαίνει ότι το λεξιλόγιό σου μεγαλώνει. Αν είναι επίπεδη, εξάσκησε πιο συχνά.',
    'infoForecast': 'Δείχνει πόσες λέξεις είναι προγραμματισμένες για επανάληψη τις επόμενες 7 μέρες.\n\nΚαθυστ. (κόκκινο) → καθυστερημένες — κάνε τις πρώτα!\n\nΜικρότερες μπάρες μπροστά = ελαφρύτερο φορτίο. Η συνέπεια κρατά τον πίνακα ισορροπημένο.',
    'infoMemoryStrength': 'Ομαδοποιεί τις λέξεις βάσει πότε τις επανέλαβες τελευταία:\n\nΚόκκινο → αυτή την εβδομάδα (φρέσκια μνήμη)\nΣκούρο πορτοκαλί → αυτό τον μήνα\nΠορτοκαλί → πάνω από ένα μήνα\n\nΟι λέξεις στα δεξιά είναι οι πιο βαθιά αποθηκευμένες. Συνέχισε τις επαναλήψεις!',
    'infoActivity': 'Η ημερήσια σου δραστηριότητα τους τελευταίους 2 μήνες. Πιο σκούρο πορτοκαλί = περισσότερες λέξεις εκείνη τη μέρα. Πάτα μια μέρα για λεπτομέρειες.',
    'masteredUpper': 'ΚΑΤΑΚΤΗΜΕΝΕΣ',
    'learningUpper': 'ΕΚΜΑΘΗΣΗ',
    'newUpper': 'ΝΕΕΣ',
    'totalUpper': 'ΣΥΝΟΛΟ',

    // Bubble
    'sessionComplete': 'Ολοκλήρωση!',
    'correct': 'ΣΩΣΤΑ',
    'accuracy': 'ΑΚΡΙΒΕΙΑ',
    'continueBtn': 'ΣΥΝΕΧΕΙΑ',
    'mainMenu': 'Αρχική',
    'finished': 'Τέλος!',
    'goodJob': 'Μπράβο',

    // Survival
    'ok': 'OK',
    'pleaseLogIn': 'Συνδέσου για να παίξεις.',
    'noWordsInLesson': 'Δεν βρέθηκαν λέξεις σε αυτό το μάθημα.',
    'noWordsDueReview': 'Δεν υπάρχουν λέξεις για επανάληψη. Επέστρεψε αργότερα!',
    'noValidWords': 'Δεν βρέθηκαν έγκυρες λέξεις.',
    'translate': 'ΜΕΤΑΦΡΑΣΕ',
    'practice': 'ΕΞΑΣΚΗΣΗ',
    'space': 'ΚΕΝΟ',
    'hintCost': 'Βοήθεια (κοστίζει 1 ζωή)',
    'survived': 'ΕΠΙΒΙΩΣΕΣ!',
    'gameOver': 'ΤΕΛΟΣ ΠΑΙΧΝΙΔΙΟΥ',
    'finalScore': 'Τελικό Σκορ:',
    'exit': 'ΕΞΟΔΟΣ',
    'initializing': 'Αρχικοποίηση...',

    // Library
    'libraryTitle': 'ΛΕΞΙΛΟΓΙΟ',
    'noLessonsInBook': 'Δεν βρέθηκαν μαθήματα σε αυτό το βιβλίο.',
    'spanish': 'Ισπανικά',
    'english': 'Αγγλικά',
    'greek': 'Ελληνικά',
    'wordsLower': 'λέξεις',

    // Subscription
    'subscription': 'Συνδρομή',
    'palabraPremium': 'Palabra Premium',
    'freeTrialDaysLeft': 'Δωρεάν δοκιμή',
    'daysLeft': 'μέρες απομένουν',
    'trialExpired': 'Η δωρεάν δοκιμή έληξε',
    'unlockLearning': 'Εγγραφείτε για να συνεχίσετε',
    'monthly': 'Μηνιαία',
    'yearly': 'Ετήσια',
    'perMonth': '/μήνα',
    'perYear': '/έτος',
    'save33': 'Εξοικονόμηση 33%',
    'subscribe': 'ΕΓΓΡΑΦΗ',
    'restorePurchases': 'Επαναφορά Αγορών',
    'manageSub': 'Διαχείριση Συνδρομής',
    'renewsOn': 'Ανανεώνεται στις',
    'expiresOn': 'Λήγει στις',
    'active': 'Ενεργή',
    'startFreeTrial': 'Ξεκίνα με 2 μήνες δωρεάν!',
    'expired': 'Έληξε',

    // Game Mode
    'left': 'ΑΠΟΜΕΝΟΥΝ',
    'pts': 'ΠΟΝ',
    'noWordsInLessonGame': 'Δεν υπάρχουν λέξεις σε αυτό το μάθημα!',
    'cycleComplete': 'ΚΥΚΛΟΣ ΟΛΟΚΛΗΡΩΘΗΚΕ!',
    'allWordsReviewed': 'Όλες οι λέξεις εξετάστηκαν!',
  };
}
