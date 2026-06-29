import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'l10n/app_localizations.dart';

/// Shows local notifications used to alert the operator when tracking stops
/// reporting. Safe to call from the background/headless isolate.
class NotificationService {
  static const String _channelId = 'metrix_watchdog';
  static const String _channelName = 'Tracking alerts';
  static const int _watchdogNotificationId = 4001;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('ic_stat_notify');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      ),
    );
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              importance: Importance.high,
            ),
          );
    }
    _initialized = true;
  }

  /// Alerts the operator that location stopped being sent to the server.
  static Future<void> showTrackingStalled() async {
    try {
      await init();
      final l10n = _localizations();
      await _plugin.show(
        _watchdogNotificationId,
        l10n.watchdogNotificationTitle,
        l10n.watchdogNotificationBody,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.error,
            ongoing: false,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      developer.log('Failed to show watchdog notification', error: error);
    }
  }

  /// Clears any active watchdog alert once reporting recovers.
  static Future<void> clearTrackingStalled() async {
    try {
      await init();
      await _plugin.cancel(_watchdogNotificationId);
    } catch (error) {
      developer.log('Failed to clear watchdog notification', error: error);
    }
  }

  static AppLocalizations _localizations() {
    final code = Platform.localeName.split(RegExp('[_-]')).first;
    try {
      return lookupAppLocalizations(Locale(code));
    } on FlutterError {
      return lookupAppLocalizations(const Locale('en'));
    }
  }
}
