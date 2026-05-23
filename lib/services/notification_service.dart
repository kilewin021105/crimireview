import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'storage_service.dart';

/// Service for handling local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final StorageService _storage = StorageService();
  bool _initialized = false;

  NotificationService._();

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;
    
    // Initialize timezone
    tz.initializeTimeZones();
    
    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    _initialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - can navigate to specific screen
    final payload = response.payload;
    if (payload != null) {
      // TODO: Handle navigation based on payload
    }
  }

  /// Request notification permissions (for iOS/Android 13+)
  Future<bool> requestPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    
    return true;
  }

  /// Setup daily study reminder notifications
  Future<void> setupScheduledNotifications() async {
    final enabled = await _storage.getNotificationsEnabled();
    if (!enabled) {
      await cancelAll();
      return;
    }
    
    // Cancel existing scheduled notifications
    await cancelAll();
    
    // Schedule morning reminder at 9:00 AM
    await _scheduleDailyReminder(
      id: 1,
      hour: 9,
      minute: 0,
      title: 'Good Morning!',
      body: 'Start your day with a quick review. Keep your streak going!',
    );
    
    // Schedule evening reminder at 7:00 PM
    await _scheduleDailyReminder(
      id: 2,
      hour: 19,
      minute: 0,
      title: 'Evening Study Time',
      body: 'Don\'t forget to review before bed. It helps with retention!',
    );
  }

  Future<void> _scheduleDailyReminder({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    
    // If time has passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Daily Study Reminders',
          channelDescription: 'Reminds you to study daily',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_reminder',
    );
  }

  /// Show immediate notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final enabled = await _storage.getNotificationsEnabled();
    if (!enabled) return;
    
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'general',
          'General Notifications',
          channelDescription: 'General app notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Show achievement notification
  Future<void> showAchievementNotification(String achievementName) async {
    await showNotification(
      title: 'Achievement Unlocked!',
      body: 'You earned: $achievementName',
      payload: 'achievement',
    );
  }

  /// Show streak milestone notification
  Future<void> showStreakMilestone(int days) async {
    await showNotification(
      title: 'Streak Milestone!',
      body: 'Amazing! You\'ve studied for $days days in a row!',
      payload: 'streak',
    );
  }

  /// Show quiz complete notification
  Future<void> showQuizCompleteNotification(int score) async {
    String message;
    if (score >= 80) {
      message = 'Excellent! You scored $score%. Keep it up!';
    } else if (score >= 60) {
      message = 'Good job! You scored $score%. Practice more!';
    } else {
      message = 'You scored $score%. Don\'t give up, keep studying!';
    }
    
    await showNotification(
      title: 'Quiz Complete',
      body: message,
      payload: 'quiz_complete',
    );
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Cancel specific notification
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
