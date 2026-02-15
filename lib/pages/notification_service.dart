import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';
import '../local_db.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final _random = Random();

  // Notification IDs
  static const int _morningDay1 = 10;
  static const int _morningDay2 = 11;
  static const int _comeback = 20;
  static const int _streakDay1 = 30;
  static const int _streakDay2 = 31;
  static const int _inactivityDay3 = 40;
  static const int _inactivityDay7 = 41;

  static const _allIds = [10, 11, 20, 30, 31, 40, 41];

  // --- Morning messages (#1) ---
  static const List<Map<String, String>> _morningMessages = [
    {
      'title': 'Buenos dias! ☀️',
      'body': 'How about a quick Spanish session with your coffee?',
    },
    {
      'title': 'Got a minute? 🇪🇸',
      'body': "Your words are ready when you are — no rush!",
    },
    {
      'title': 'Your words miss you! 📖',
      'body': "They've been waiting all night — come say hola!",
    },
    {
      'title': 'Spanish o\'clock! 🕐',
      'body': 'Sneak in a quick round before the day takes over!',
    },
    {
      'title': 'Perfect morning for it! ☕',
      'body': "A little Spanish now and you're set for the day!",
    },
  ];

  // --- Come-back messages (#2) ---
  static const List<Map<String, String>> _comebackMessages = [
    {
      'title': 'Time for a Spanish break! ☕',
      'body': 'Step away from the routine — learn something new in 5 minutes!',
    },
    {
      'title': 'Hey, remember us? 😊',
      'body': "Your Spanish words are still here — come say hola when you're free!",
    },
    {
      'title': 'Quick break? 🌤️',
      'body': "Recharge with a quick Spanish round — you've earned it!",
    },
    {
      'title': 'Still got some time! 📚',
      'body': 'A few more words today and tomorrow-you will be grateful!',
    },
    {
      'title': 'Your brain could use a reset! 🧠',
      'body': "Swap the scrolling for some Spanish — it's way more fun!",
    },
  ];

  Future<void> init() async {
    tz.initializeTimeZones();

    // Set local timezone from device (otherwise defaults to UTC)
    final deviceTzInfo = await FlutterTimezone.getLocalTimezone();
    final tzName = deviceTzInfo.identifier;
    tz.setLocalLocation(tz.getLocation(tzName));
    debugPrint("🕐 Device timezone: $tzName");

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/notification_icon');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _plugin.initialize(initializationSettings);

    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      debugPrint("🔔 Notification permission granted: $granted");
    }
  }

  /// Called when user OPENS the app.
  /// Cancels all notifications (user is active) and schedules future ones.
  Future<void> onAppOpened() async {
    final enabled = await areNotificationsEnabled();
    if (!enabled) {
      debugPrint("🔕 Notifications not enabled — skipping schedule");
      return;
    }

    // Cancel everything — user is here
    for (final id in _allIds) {
      await _plugin.cancel(id);
    }

    final now = tz.TZDateTime.now(tz.local);
    final streak = await LocalDB.instance.getStreakCount();

    // --- Schedule for TOMORROW (day 1 of absence) ---
    final tomorrow = now.add(const Duration(days: 1));

    // Morning #1 — tomorrow at 10:00
    final morning1 = _pickRandom(_morningMessages);
    await _schedule(
      _morningDay1,
      morning1['title']!,
      morning1['body']!,
      tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, 10, 0),
    );

    // Streak #3 — tomorrow at ~21:00 (random ±30min)
    final streakMinutes = 21 * 60 + _random.nextInt(61) - 30; // 20:30 to 21:30
    final streakHour = streakMinutes ~/ 60;
    final streakMin = streakMinutes % 60;
    if (streak > 0) {
      await _schedule(
        _streakDay1,
        "Don't break your $streak-day streak! 🔥",
        "The night is still young — one quick session and you're safe!",
        tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, streakHour, streakMin),
      );
    } else {
      await _schedule(
        _streakDay1,
        "Time to get back on track! 🔥",
        "Start a streak today — even one quick round counts!",
        tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, streakHour, streakMin),
      );
    }

    // --- Schedule for DAY 2 of absence ---
    final day2 = now.add(const Duration(days: 2));

    // Morning #1 — day 2 at 10:00 (different message)
    final morning2 = _pickRandom(_morningMessages);
    await _schedule(
      _morningDay2,
      morning2['title']!,
      morning2['body']!,
      tz.TZDateTime(tz.local, day2.year, day2.month, day2.day, 10, 0),
    );

    // Streak #3 — day 2 at ~21:00
    final streak2Minutes = 21 * 60 + _random.nextInt(61) - 30;
    final streak2Hour = streak2Minutes ~/ 60;
    final streak2Min = streak2Minutes % 60;
    if (streak > 0) {
      await _schedule(
        _streakDay2,
        "Your streak is fading... 😟",
        "Don't let $streak days of hard work go to waste!",
        tz.TZDateTime(tz.local, day2.year, day2.month, day2.day, streak2Hour, streak2Min),
      );
    } else {
      await _schedule(
        _streakDay2,
        "We miss you! 🇪🇸",
        "Your Spanish words are gathering dust — come back for a quick round!",
        tz.TZDateTime(tz.local, day2.year, day2.month, day2.day, streak2Hour, streak2Min),
      );
    }

    // --- INACTIVITY: Day 3 (after 2 days of silence, stop daily, just this) ---
    final day3 = now.add(const Duration(days: 3));
    await _schedule(
      _inactivityDay3,
      "Don't stop trying! 💪",
      "Find 5 minutes — that's all it takes to keep going!",
      tz.TZDateTime(tz.local, day3.year, day3.month, day3.day, 12, 0),
    );

    // --- INACTIVITY: Day 7 (one last nudge) ---
    final day7 = now.add(const Duration(days: 7));
    await _schedule(
      _inactivityDay7,
      "It's been a while! 🌱",
      "Your Spanish is still in there — 5 minutes to bring it back!",
      tz.TZDateTime(tz.local, day7.year, day7.month, day7.day, 12, 0),
    );

    debugPrint("🔔 Scheduled all notifications (streak: $streak)");
  }

  /// Called when user MINIMIZES the app.
  /// Schedules come-back notification for 5h later (if before 22:00, once per day).
  Future<void> onAppMinimized() async {
    final enabled = await areNotificationsEnabled();
    if (!enabled) return;

    // Cancel previous come-back (in case they minimize multiple times)
    await _plugin.cancel(_comeback);

    final now = tz.TZDateTime.now(tz.local);
    final comebackTime = now.add(const Duration(hours: 5));

    // Only schedule if it would fire before 22:00
    if (comebackTime.hour < 22) {
      final msg = _pickRandom(_comebackMessages);
      await _schedule(
        _comeback,
        msg['title']!,
        msg['body']!,
        comebackTime,
      );
      debugPrint("🔔 Scheduled come-back at ${comebackTime.hour}:${comebackTime.minute.toString().padLeft(2, '0')}");
    } else {
      debugPrint("🔔 Skipped come-back — would fire after 22:00");
    }
  }

  /// Schedule a single notification with exact/inexact fallback
  Future<void> _schedule(int id, String title, String body, tz.TZDateTime when) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_study_id',
      'Study Reminders',
      channelDescription: 'Daily reminder to practice Spanish',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFFFF9800),
      colorized: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e2) {
        debugPrint("⚠️ Could not schedule notification $id: $e2");
      }
    }
  }

  Map<String, String> _pickRandom(List<Map<String, String>> messages) {
    return messages[_random.nextInt(messages.length)];
  }

  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final androidImplementation = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await androidImplementation?.areNotificationsEnabled() ?? false;
    } else if (Platform.isIOS) {
      return await Permission.notification.isGranted;
    }
    return false;
  }


  Future<void> openSettings() async {
    await openAppSettings();
  }
}
