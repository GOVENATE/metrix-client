import 'dart:io';
import 'dart:math';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

class Preferences {
  static const int defaultInterval = 15;
  static const int defaultDistance = 10;
  static const int defaultHeartbeat = 60;
  static const int defaultFastestInterval = 5;
  static const int legacyDefaultInterval = 300;
  static const int legacyDefaultDistance = 75;
  static const int legacyDefaultFastestInterval = 30;

  /// Server the field devices must report to. Used by the diagnostics screen to
  /// flag misconfigured devices and as the default for fresh installs.
  ///
  /// Public ingestion endpoint: Apache terminates TLS for
  /// tracking.soymetrix.com and reverse-proxies `/gps/osmand/` to the Traccar
  /// OsmAnd port bound to 127.0.0.1:7055. The trailing slash is required — the
  /// `ProxyPass "/gps/osmand/"` rule only matches paths that keep it.
  static const String defaultPrimaryUrl =
      'https://tracking.soymetrix.com/gps/osmand/';
  static const String expectedUrl = defaultPrimaryUrl;
  static const int trackingProfileVersion = 5;

  /// How long the device may go without a successful upload before the watchdog
  /// warns the user that tracking has stalled (seconds).
  static const int watchdogTimeoutSeconds = 900;

  /// Minimum gap between repeated watchdog notifications (seconds).
  static const int watchdogRealertSeconds = 1800;

  static Future<void>? _initFuture;
  static late SharedPreferencesWithCache instance;

  /// A phone IMEI is exactly 15 decimal digits. The identifier is entered
  /// manually in the field, so this is the single source of truth used both to
  /// validate the input and to flag provisional identifiers in diagnostics.
  static const int imeiLength = 15;

  /// True when [value] is a syntactically valid IMEI (exactly 15 digits).
  /// Fresh installs seed a shorter provisional number, so this is what tells
  /// the app whether the operator has entered the real device IMEI yet.
  static bool isValidImei(String? value) {
    if (value == null || value.length != imeiLength) return false;
    return RegExp(r'^\d{15}$').hasMatch(value);
  }

  static const String id = 'id';
  static const String url = 'url';
  static const String primaryUrl = 'primary_url';
  static const String lastHttpStatus = 'last_http_status';
  static const String profileVersion = 'tracking_profile_version';
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
      sharedPreferencesOptions: Platform.isAndroid
          ? SharedPreferencesAsyncAndroidOptions(
              backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
            )
          : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: {
          id,
          url,
          primaryUrl,
          lastHttpStatus,
          profileVersion,
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
      await instance.setString(primaryUrl, defaultPrimaryUrl);
      await instance.setString(accuracy, 'high');
      await instance.setInt(interval, defaultInterval);
      await instance.setInt(distance, defaultDistance);
      await instance.setInt(heartbeat, defaultHeartbeat);
      await instance.setBool(buffer, true);
      await instance.setBool(stopDetection, true);
      await instance.setBool(wakelock, Platform.isAndroid);
      await instance.setBool(watchdog, true);
      await instance.setInt(fastestInterval, defaultFastestInterval);
      await instance.setInt(profileVersion, trackingProfileVersion);
    } else {
      await _applyReliableTrackingDefaults();
    }
  }

  static Future<void> _applyReliableTrackingDefaults() async {
    if (instance.getString(primaryUrl) == null) {
      await instance.setString(primaryUrl, defaultPrimaryUrl);
    }

    final currentProfile = instance.getInt(profileVersion) ?? 0;
    if (currentProfile < trackingProfileVersion) {
      // Single-server migration: devices that had failed over to the retired
      // fallback VPS are pulled back to the one active server.
      await instance.setString(primaryUrl, defaultPrimaryUrl);
      await instance.setString(url, defaultPrimaryUrl);
      await instance.setString(accuracy, 'high');
      await instance.setInt(interval, defaultInterval);
      await instance.setInt(distance, defaultDistance);
      await instance.setInt(fastestInterval, defaultFastestInterval);
      await instance.setBool(stopDetection, true);
      await instance.setBool(buffer, true);
      await instance.setInt(profileVersion, trackingProfileVersion);
    }
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
    // The native SDK database is the durable outbox. It must never be disabled:
    // queued fixes survive loss of signal, process termination and device reboot.
    if (instance.getBool(buffer) != true) await instance.setBool(buffer, true);
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
        distanceFilter: isHighestAccuracy
            ? 0
            : instance.getInt(distance)?.toDouble(),
        locationUpdateInterval: Platform.isAndroid
            ? (isHighestAccuracy
                  ? 0
                  : (locationUpdateInterval > 0
                        ? locationUpdateInterval
                        : null))
            : null,
        fastestLocationUpdateInterval: Platform.isAndroid
            ? (isHighestAccuracy ? 0 : fastestLocationUpdateInterval)
            : null,
        disableElasticity: false,
        stationaryRadius: 25,
        stopTimeout: 5,
        locationAuthorizationRequest: Platform.isIOS ? 'Always' : null,
        pausesLocationUpdatesAutomatically: false,
        showsBackgroundLocationIndicator: Platform.isIOS ? false : null,
      ),
      app: bg.AppConfig(
        enableHeadless: Platform.isAndroid ? true : null,
        stopOnTerminate: false,
        startOnBoot: true,
        heartbeatInterval: heartbeatInterval > 0
            ? heartbeatInterval.toDouble()
            : null,
        preventSuspend: Platform.isIOS ? (heartbeatInterval > 0) : null,
        backgroundPermissionRationale: Platform.isAndroid
            ? bg.PermissionRationale(
                title:
                    'Allow {applicationName} to access this device\'s location in the background',
                message:
                    'For reliable tracking, please enable {backgroundPermissionOptionLabel} location access.',
                positiveAction: 'Change to {backgroundPermissionOptionLabel}',
                negativeAction: 'Cancel',
              )
            : null,
        notification: Platform.isAndroid
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
        url: _formatUrl(serverUrl),
        params: {'device_id': instance.getString(id)},
        headers: const {'X-Metrix-Client': 'android-9.8'},
        timeout: 30,
      ),
      logger: const bg.LoggerConfig(
        logLevel: bg.LogLevel.verbose,
        logMaxDays: 1,
      ),
      activity: bg.ActivityConfig(
        disableStopDetection: instance.getBool(stopDetection) == false,
        activityRecognitionInterval: 10000,
        minimumActivityRecognitionConfidence: 70,
      ),
      persistence: bg.PersistenceConfig(
        maxRecordsToPersist: -1,
        locationTemplate: _locationTemplate(),
      ),
    );
  }

  /// The single ingestion server every device reports to.
  static String get serverUrl =>
      instance.getString(primaryUrl) ?? defaultPrimaryUrl;

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
      "uuid": "<%= uuid %>",
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
      "extras": {"position_uuid": "<%= uuid %>", "source": "metrix_mobile"},
      "_": "&id=${instance.getString(id)}&lat=<%= latitude %>&lon=<%= longitude %>&timestamp=<%= timestamp %>&accuracy=<%= accuracy %>&uuid=<%= uuid %>&"
    }'''
        .split('\n')
        .map((line) => line.trimLeft())
        .join();
  }
}
