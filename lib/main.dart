import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/app_strings.dart';

// --- YOUR PAGE IMPORTS ---
// (Ensure these paths match exactly where your files are)
import 'package:my_first_flutter_app/pages/bubble.dart';
import 'package:my_first_flutter_app/pages/statistics.dart';
import 'package:my_first_flutter_app/pages/gameMode.dart';
import 'package:my_first_flutter_app/pages/MainScreen.dart';
import 'package:my_first_flutter_app/pages/LoginPage.dart';
import 'package:my_first_flutter_app/pages/RegisterPage.dart';
import 'package:my_first_flutter_app/pages/splash_screen.dart';
// Note: Check if notification_service.dart is in 'lib/' or 'lib/pages/'
import 'package:my_first_flutter_app/pages/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    // Credentials loaded from .env file (not exposed in source code)
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // ✅ INIT NOTIFICATIONS
  await NotificationService().init();
  // ✅ LOAD SAVED LANGUAGE
  await S.load();
  runApp(const ProviderScope(child: MyApp()));
}

// 🔥 CHANGED TO STATEFUL WIDGET TO LISTEN TO APP LIFECYCLE
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    // 1. Start watching the app state
    WidgetsBinding.instance.addObserver(this);
    // 2. Register locale change callback to rebuild entire app
    S.setOnLocaleChanged(() {
      if (mounted) setState(() {});
    });
    // 3. User opened the app — cancel old notifications, schedule new ones
    NotificationService().onAppOpened();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // User minimized — schedule come-back reminder for 5h later
      NotificationService().onAppMinimized();
    } else if (state == AppLifecycleState.resumed) {
      // User came back — cancel everything and reschedule
      NotificationService().onAppOpened();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: ValueKey(S.locale),
      debugShowCheckedModeBanner: false,
      title: 'Palabra',

      // APPLY THE THEME HERE
      theme: appTheme,

      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/home': (context) => const MainScreen(),
        // ... other routes
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _splashDone = false;
  bool _splashAnimDone = false;
  bool _mainScreenReady = false;
  bool _showingMainScreen = false;
  bool _allowBuildContent = false; // defer heavy widget tree
  final _splashKey = GlobalKey<SplashScreenState>();

  @override
  void initState() {
    super.initState();
    // Let bubbles animate for 3s before building MainScreen widget tree
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) setState(() => _allowBuildContent = true);
    });
  }

  void _tryFadeOut() {
    if (_splashDone || !mounted) return;
    if (_splashAnimDone && (_mainScreenReady || !_showingMainScreen)) {
      _splashKey.currentState?.fadeOut().then((_) {
        if (mounted) setState(() => _splashDone = true);
      });
    }
  }

  void _onMainScreenReady() {
    _mainScreenReady = true;
    _tryFadeOut();
  }

  void _onSplashAnimDone() {
    _splashAnimDone = true;
    _tryFadeOut();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Defer building heavy content until bubbles have had smooth time
        if (_allowBuildContent)
          StreamBuilder<AuthState>(
            stream: Supabase.instance.client.auth.onAuthStateChange,
            builder: (context, snapshot) {
              final session = snapshot.data?.session ??
                  Supabase.instance.client.auth.currentSession;
              if (session != null) {
                _showingMainScreen = true;
                return MainScreen(onReady: _onMainScreenReady);
              }
              if (snapshot.hasData) {
                _showingMainScreen = false;
                WidgetsBinding.instance.addPostFrameCallback((_) => _tryFadeOut());
                return const LoginPage();
              }
              if (Supabase.instance.client.auth.currentSession != null) {
                _showingMainScreen = true;
                return MainScreen(onReady: _onMainScreenReady);
              }
              _showingMainScreen = false;
              WidgetsBinding.instance.addPostFrameCallback((_) => _tryFadeOut());
              return const LoginPage();
            },
          )
        else
          const SizedBox.expand(), // lightweight placeholder

        // Splash on top — fades out to reveal ready content
        if (!_splashDone)
          SplashScreen(
            key: _splashKey,
            onFinished: _onSplashAnimDone,
          ),
      ],
    );
  }
}