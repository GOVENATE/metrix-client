import 'dart:io';
import 'dart:math';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

class Preferences {
  static const int defaultInterval = 60;
  static const int defaultDistance = 25;
  static const int defaultHeartbeat = 60;
  static const int defaultFastestInterval = 15;
  static const int legacyDefaultInterval = 300;
  static const int legacyDefaultDistance = 75;
  static const int legacyDefaultFastestInterval = 30;

  /// Server the field devices must report to. Used by the diagnostics screen to
  /// flag misconfigured devices and as the default for fresh installs.
  static const String expectedUrl = 'http://45.132.241.82:6055';

  /// How long the device may go without a successful upload before the watchdog
  /// warns the user that tracking has stalled (seconds).
  static const int watchdogTimeoutSeconds = 900;

  /// Minimum gap between repeated watchdog notifications (seconds).
  static const int watchdogRealertSeconds = 1800;

  static Future<void>? _initFuture;
  static late SharedPreferencesWithCache instance;

  static const String id = 'id';
  static const String url = 'url';
  static const String accuracy = 'accuracy';
  static const String distance = 'distance';
  static const String interval = 'interval';
  static const String angle = 'angle';
  static const String heartbeat = 'heartbeat';
  static const String fastestInterval = 'fastest_interval';
  static const String buffer = 'buffer';
  static const String wakelock = 'wakelock';
  static const String stopDetection = 'stop_detection';
  static const String password = 'password';
  static const String watchdog = 'watchdog';

  static const String lastTimestamp = 'lastTimestamp';
  static const String lastLatitude = 'lastLatitude';
  static const String lastLongitude = 'lastLongitude';
  static const String lastHeading = 'lastHeading';
  static const String lastSync = 'lastSync';
  static const String lastWatchdogAlert = 'lastWatchdogAlert';

  static Future<void> init() async {
    _initFuture ??= _createInstance();
    await _initFuture;
  }

  static Future<void> _createInstance() async {
    instance = await SharedPreferencesWithCache.create(
      sharedPreferencesOptions:
          Platform.isAndroid
              ? SharedPreferencesAsyncAndroidOptions(
                backend:
                    SharedPreferencesAndroidBackendLibrary.SharedPreferences,
              )
              : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: {
          id,
          url,
          accuracy,
          distance,
          interval,
          angle,
          heartbeat,
          fastestInterval,
          buffer,
          wakelock,
          stopDetection,
          password,
          watchdog,
          lastTimestamp,
          lastLatitude,
          lastLongitude,
          lastHeading,
          lastSync,
          lastWatchdogAlert,
        },
      ),
    );
    if (instance.getString(id) == null) {
      await instance.setString(
        id,
        (Random().nextInt(90000000) + 10000000).toString(),
      );
      await instance.setString(url, expectedUrl);
      await instance.setString(accuracy, 'medium');
      await instance.setInt(interval, defaultInterval);
      await instance.setInt(distance, defaultDistance);
      await instance.setInt(heartbeat, defaultHeartbeat);
      await instance.setBool(buffer, true);
      await instance.setBool(stopDetection, false);
      await instance.setBool(wakelock, Platform.isAndroid);
      await instance.setBool(watchdog, true);
      await instance.setInt(fastestInterval, defaultFastestInterval);
    } else {
      await _applyReliableTrackingDefaults();
    }
  }

  static Future<void> _applyReliableTrackingDefaults() async {
    final currentInterval = instance.getInt(interval);
    if (currentInterval == null || currentInterval == legacyDefaultInterval) {
      await instance.setInt(interval, defaultInterval);
    }
    final currentDistance = instance.getInt(distance);
    if (currentDistance == null || currentDistance == legacyDefaultDistance) {
      await instance.setInt(distance, defaultDistance);
    }
    final currentHeartbeat = instance.getInt(heartbeat);
    if (currentHeartbeat == null || currentHeartbeat <= 0) {
      await instance.setInt(heartbeat, defaultHeartbeat);
    }
    final currentFastestInterval = instance.getInt(fastestInterval);
    if (currentFastestInterval == null ||
        currentFastestInterval == legacyDefaultFastestInterval) {
      await instance.setInt(fastestInterval, defaultFastestInterval);
    }
    if (instance.getBool(wakelock) == null && Platform.isAndroid) {
      await instance.setBool(wakelock, true);
    }
    if (instance.getBool(stopDetection) != false) {
      await instance.setBool(stopDetection, false);
    }
    if (instance.getBool(watchdog) == null) {
      await instance.setBool(watchdog, true);
    }
  }

  static bg.Config geolocationConfig(bool reset) {
    final isHighestAccuracy = instance.getString(accuracy) == 'highest';
    final locationUpdateInterval = (instance.getInt(interval) ?? 0) * 1000;
    final fastestLocationUpdateInterval =
        (instance.getInt(fastestInterval) ?? 30) * 1000;
    final heartbeatInterval = instance.getInt(heartbeat) ?? 0;
    return bg.Config(
      reset: reset,
      geolocation: bg.GeoConfig(
        desiredAccuracy: switch (instance.getString(accuracy)) {
          'highest' =>
            Platform.isIOS
                ? bg.DesiredAccuracy.navigation
                : bg.DesiredAccuracy.high,
          'high' => bg.DesiredAccuracy.high,
          'low' => bg.DesiredAccuracy.low,
          _ => bg.DesiredAccuracy.medium,
        },
        distanceFilter:
            isHighestAccuracy ? 0 : instance.getInt(distance)?.toDouble(),
        locationUpdateInterval:
            Platform.isAndroid
                ? (isHighestAccuracy
                    ? 0
                    : (locationUpdateInterval > 0
                        ? locationUpdateInterval
                        : null))
                : null,
        fastestLocationUpdateInterval:
            Platform.isAndroid
                ? (isHighestAccuracy ? 0 : fastestLocationUpdateInterval)
                : null,
        disableElasticity: true,
        locationAuthorizationRequest: Platform.isIOS ? 'Always' : null,
        pausesLocationUpdatesAutomatically: false,
        showsBackgroundLocationIndicator: Platform.isIOS ? false : null,
      ),
      app: bg.AppConfig(
        enableHeadless: Platform.isAndroid ? true : null,
        stopOnTerminate: false,
        startOnBoot: true,
        heartbeatInterval:
            heartbeatInterval > 0 ? heartbeatInterval.toDouble() : null,
        preventSuspend: Platform.isIOS ? (heartbeatInterval > 0) : null,
        backgroundPermissionRationale:
            Platform.isAndroid
                ? bg.PermissionRationale(
                  title:
                      'Allow {applicationName} to access this device\'s location in the background',
                  message:
                      'For reliable tracking, please enable {backgroundPermissionOptionLabel} location access.',
                  positiveAction: 'Change to {backgroundPermissionOptionLabel}',
                  negativeAction: 'Cancel',
                )
                : null,
        notification:
            Platform.isAndroid
                ? bg.Notification(
                  smallIcon: 'drawable/ic_stat_notify',
                  priority: bg.NotificationPriority.defaultPriority,
                  sticky: true,
                )
                : null,
      ),
      http: bg.HttpConfig(
        autoSync: true,
        autoSyncThreshold: 1,
        batchSync: false,
        url: _formatUrl(instance.getString(url)),
        params: {'device_id': instance.getString(id)},
      ),
      logger: const bg.LoggerConfig(
        logLevel: bg.LogLevel.verbose,
        logMaxDays: 1,
      ),
      activity: bg.ActivityConfig(
        disableStopDetection: instance.getBool(stopDetection) == false,
      ),
      persistence: bg.PersistenceConfig(
        maxRecordsToPersist: instance.getBool(buffer) != false ? -1 : 1,
        locationTemplate: _locationTemplate(),
      ),
    );
  }

  static String? _formatUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.parse(url);
    if ((uri.path.isEmpty || uri.path == '') && !url.endsWith('/')) {
      return '$url/';
    }
    return url;
  }

  static String _locationTemplate() {
    return '''{
      "timestamp": "<%= timestamp %>",
      "coords": {
        "latitude": <%= latitude %>,
        "longitude": <%= longitude %>,
        "accuracy": <%= accuracy %>,
        "speed": <%= speed %>,
        "heading": <%= heading %>,
        "altitude": <%= altitude %>
      },
      "is_moving": <%= is_moving %>,
      "odometer": <%= odometer %>,
      "event": "<%= event %>",
      "battery": {
        "level": <%= battery.level %>,
        "is_charging": <%= battery.is_charging %>
      },
      "activity": {
        "type": "<%= activity.type %>"
      },
      "extras": {},
      "_": "&id=${instance.getString(id)}&lat=<%= latitude %>&lon=<%= longitude %>&timestamp=<%= timestamp %>&"
    }'''.split('\n').map((line) => line.trimLeft()).join();
  }
}
