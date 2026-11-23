import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../features/chat/service/chat_database.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    // Configure tz.local matching the device timezone offset accurately
    try {
      final now = DateTime.now();
      final offset = now.timeZoneOffset;
      final offsetHours = offset.inHours.abs();
      final sign = offset.isNegative ? '+' : '-';
      final locationName = 'Etc/GMT$sign$offsetHours';

      try {
        tz.setLocalLocation(tz.getLocation(locationName));
      } catch (_) {
        // Safe fallback location if not found in table
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
    } catch (e) {
      log('Timezone initialization warning: $e');
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        const androidSettings =
            AndroidInitializationSettings('@mipmap/launcher_icon');

        const settings = InitializationSettings(
          android: androidSettings,
        );

        await _notifications.initialize(settings: settings);

        // Request notification permission on Android 13+
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();

        // Request exact alarm permission on Android 12+
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestExactAlarmsPermission();
      } catch (e) {
        log('Notification initialization warning: $e');
      }
    }

    _isInitialized = true;
  }

  /// Schedules a notification using reliable Android alarm modes.
  Future<int> createReminder({
    required String title,
    required int delayMinutes,
    int? id,
  }) async {
    await initialize();

    final safeMinutes = delayMinutes <= 0 ? 1 : delayMinutes;
    final scheduledDate =
        tz.TZDateTime.now(tz.local).add(Duration(minutes: safeMinutes));
    final reminderId = id ?? (DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF);

    const androidDetails = AndroidNotificationDetails(
      'arivu_ai_reminders',
      'Reminders',
      channelDescription: 'Offline personal reminders and alerts',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
      playSound: true,
      enableVibration: true,
    );

    if (!kIsWeb && Platform.isAndroid) {
      try {
        // Use exact alarmClock schedule (rings even in Android background/Doze mode)
        await _notifications.zonedSchedule(
          id: reminderId,
          title: 'Arivu AI Reminder',
          body: title,
          scheduledDate: scheduledDate,
          notificationDetails: const NotificationDetails(android: androidDetails),
          androidScheduleMode: AndroidScheduleMode.alarmClock,
        );
      } catch (e) {
        log('Fallback from alarmClock to exactAllowWhileIdle: $e');
        try {
          await _notifications.zonedSchedule(
            id: reminderId,
            title: 'Arivu AI Reminder',
            body: title,
            scheduledDate: scheduledDate,
            notificationDetails: const NotificationDetails(android: androidDetails),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        } catch (e2) {
          log('Fallback to inexactAllowWhileIdle: $e2');
          await _notifications.zonedSchedule(
            id: reminderId,
            title: 'Arivu AI Reminder',
            body: title,
            scheduledDate: scheduledDate,
            notificationDetails: const NotificationDetails(android: androidDetails),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    }

    // Persist to local SQLite database
    try {
      await ChatDatabase.instance.saveReminder(
        id: reminderId,
        title: title,
        scheduledAt: scheduledDate.millisecondsSinceEpoch,
      );
    } catch (_) {}

    return reminderId;
  }

  /// Helper to test notification immediately (0 second delay)
  Future<void> showImmediateNotification({
    required String title,
    required String body,
  }) async {
    await initialize();
    const androidDetails = AndroidNotificationDetails(
      'arivu_ai_reminders',
      'Reminders',
      channelDescription: 'Offline personal reminders',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
    );
    await _notifications.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancelReminder(int id) async {
    await initialize();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _notifications.cancel(id: id);
      } catch (e) {
        log('Error cancelling notification: $e');
      }
    }
    try {
      await ChatDatabase.instance.deleteReminder(id);
    } catch (_) {}
  }

  Future<void> cancelAllReminders() async {
    await initialize();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _notifications.cancelAll();
      } catch (e) {
        log('Error cancelling all notifications: $e');
      }
    }
    try {
      final db = await ChatDatabase.instance.database;
      await db.delete('reminders');
    } catch (_) {}
  }

  /// Retrieves upcoming active reminders, automatically marking expired reminders as completed.
  Future<List<Map<String, dynamic>>> getUpcomingReminders() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rawReminders = await ChatDatabase.instance.getActiveReminders();
      final upcoming = <Map<String, dynamic>>[];

      for (final r in rawReminders) {
        final scheduledAt = r['scheduled_at'] as int? ?? 0;
        final id = r['id'] as int;
        if (scheduledAt < now - 60000) {
          // Mark past reminders as completed in database
          await ChatDatabase.instance.markReminderCompleted(id);
        } else {
          upcoming.add(r);
        }
      }
      return upcoming;
    } catch (e) {
      log('Error getting upcoming reminders: $e');
      return [];
    }
  }
}
