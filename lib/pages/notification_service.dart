import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../local_db.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _appId = '599aa9dc-e2cb-4f4c-8c29-c4dd29b9dc97';

  Future<void> init() async {
    OneSignal.initialize(_appId);
    await OneSignal.Notifications.requestPermission(true);
    debugPrint("🔔 OneSignal initialized");
  }

  /// Called when user OPENS the app.
  /// Updates OneSignal tags so automated messages can reference streak count.
  Future<void> onAppOpened() async {
    try {
      final streak = await LocalDB.instance.getStreakCount();
      OneSignal.User.addTagWithKey('streak_count', streak.toString());
      OneSignal.User.addTagWithKey(
        'last_active_ms',
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      debugPrint("🔔 OneSignal tags updated (streak: $streak)");
    } catch (e) {
      debugPrint("⚠️ Could not update OneSignal tags: $e");
    }
  }

  /// Called when user MINIMIZES the app.
  Future<void> onAppMinimized() async {}

  Future<bool> areNotificationsEnabled() async {
    return OneSignal.Notifications.permission;
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}
