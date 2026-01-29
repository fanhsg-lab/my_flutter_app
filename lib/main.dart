import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

// --- YOUR PAGE IMPORTS ---
// (Ensure these paths match exactly where your files are)
import 'package:my_first_flutter_app/pages/bubble.dart';
import 'package:my_first_flutter_app/pages/statistics.dart';
import 'package:my_first_flutter_app/pages/gameMode.dart';
import 'package:my_first_flutter_app/pages/MainScreen.dart'; 
import 'package:my_first_flutter_app/pages/LoginPage.dart';
import 'package:my_first_flutter_app/pages/RegisterPage.dart';
// Note: Check if notification_service.dart is in 'lib/' or 'lib/pages/'
import 'package:my_first_flutter_app/pages/notification_service.dart'; 
import 'local_db.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    // 1. PASTE YOUR PROJECT URL HERE
    url: 'https://uhvwszwiasuemevjwslk.supabase.co', 
    
    // 2. YOUR ANKEY
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVodndzendpYXN1ZW1ldmp3c2xrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc0NTgxMzYsImV4cCI6MjA4MzAzNDEzNn0.CjStw779lQWRLWzu1euFN45kVqf4xRAFcEyld9mgYQY',
  );

  // ✅ INIT NOTIFICATIONS
  await NotificationService().init();

  runApp(const MyApp());
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
  }

  @override
  void dispose() {
    // 2. Stop watching when app is killed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 3. THIS FUNCTION RUNS WHEN APP IS MINIMIZED/CLOSED
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      print("📱 App going to background... Scheduling Smart Reminder.");
      // ✅ Calculate due words & Schedule Notification
      NotificationService().scheduleSmartReminder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Language App',
      
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final session = snapshot.data?.session;
        if (session != null) {
          return const MainScreen();
        } else {
          return const LoginPage();
        }
      },
    );
  }
}