import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../local_db.dart'; 
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    // 🤖 Android Settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 🍎 iOS Settings
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

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    
    // Request permission for Android 13+
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  // 🔥 THE SMART SCHEDULER
  Future<void> scheduleSmartReminder() async {
    // 1. Clear old reminders (so we don't spam)
    await flutterLocalNotificationsPlugin.cancelAll();

    // 2. Query the DB: How many words will be due 24 hours from NOW?
    final db = await LocalDB.instance.database;
    final tomorrow = DateTime.now().add(const Duration(hours: 24));
    
    // Logic: Count words where 'next_due_at' is BEFORE tomorrow
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM user_progress WHERE next_due_at <= ?",
      [tomorrow.toIso8601String()]
    );
    
    int dueCount = Sqflite.firstIntValue(result) ?? 0;

    // 3. Draft the Message based on the number
    String title = "Time to Practice! 🇪🇸";
    String body = "Keep your streak alive!";

    if (dueCount > 0) {
      title = "Review Pile-Up Alert! 🚨";
      body = "You have $dueCount words waiting for review. Clear them before they stack up!";
    } else {
      title = "Streak Danger 🔥";
      body = "You're all caught up, but don't lose your streak! Play a quick round.";
    }

    // 4. Schedule for exactly 24 hours from now
    // (If user plays tomorrow morning, this gets cancelled and pushed back again)
    final scheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(hours: 24));

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_study_id',
      'Study Reminders',
      channelDescription: 'Daily reminders based on your workload',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        0, // ID
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      print("🔔 Scheduled exact: '$body' for $scheduledDate");
    } catch (e) {
      // Exact alarms not permitted — fall back to inexact
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          0,
          title,
          body,
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        print("🔔 Scheduled inexact: '$body' for ~$scheduledDate");
      } catch (e2) {
        print("⚠️ Could not schedule notification: $e2");
      }
    }
  }

  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final androidImplementation = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await androidImplementation?.areNotificationsEnabled() ?? false;
    } else if (Platform.isIOS) {
       // You can generally assume false if not granted, or use permission_handler
       return await Permission.notification.isGranted;
    }
    return false;
  }

// Helper to open phone settings
  Future<void> openSettings() async {
    await openAppSettings();
  }

}