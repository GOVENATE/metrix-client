import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:metrix_client/location_cache.dart';
import 'package:metrix_client/notification_service.dart';
import 'package:metrix_client/preferences.dart';
import 'package:wakelock_partial_android/wakelock_partial_android.dart';

class GeolocationService {
  static Future<void> init() async {
    await bg.BackgroundGeolocation.ready(Preferences.geolocationConfig(false));
    if (Platform.isAndroid) {
      await bg.BackgroundGeolocation.registerHeadlessTask(headlessTask);
    }
    FirebaseCrashlytics.instance.log('geolocation_init');
    bg.BackgroundGeolocation.onEnabledChange(onEnabledChange);
    bg.BackgroundGeolocation.onMotionChange(onMotionChange);
    bg.BackgroundGeolocation.onHeartbeat(onHeartbeat);
    bg.BackgroundGeolocation.onConnectivityChange(onConnectivityChange);
    bg.BackgroundGeolocation.onHttp(onHttp);
    bg.BackgroundGeolocation.onLocation(onLocation, (bg.LocationError error) {
      developer.log('Location error', error: error);
    });
  }

  /// Records the time of every successful upload so the watchdog and the
  /// diagnostics screen can tell whether the device is still reporting.
  static Future<void> onHttp(bg.HttpEvent event) async {
    FirebaseCrashlytics.instance.log('geolocation_http:${event.status}');
    if (event.success) {
      await Preferences.instance.setInt(
        Preferences.lastSync,
        DateTime.now().millisecondsSinceEpoch,
      );
      await NotificationService.clearTrackingStalled();
    }
  }

  static Future<void> onEnabledChange(bool enabled) async {
    FirebaseCrashlytics.instance.log('geolocation_enabled:$enabled');
    if (Preferences.instance.getBool(Preferences.wakelock) ?? false) {
      if (!enabled) {
        await WakelockPartialAndroid.release();
      } else if (Platform.isAndroid) {
        final state = await bg.BackgroundGeolocation.state;
        if (state.isMoving == true) {
          await WakelockPartialAndroid.acquire();
        }
      }
    }
    if (enabled) {
      await _syncLocations();
    }
  }

  static Future<void> onMotionChange(bg.Location location) async {
    FirebaseCrashlytics.instance.log('geolocation_motion:${location.isMoving}');
    if (Preferences.instance.getBool(Preferences.wakelock) ?? false) {
      if (location.isMoving) {
        await WakelockPartialAndroid.acquire();
      } else {
        await WakelockPartialAndroid.release();
      }
    }
  }

  static Future<void> onHeartbeat(bg.HeartbeatEvent event) async {
    FirebaseCrashlytics.instance.log('geolocation_heartbeat');
    try {
      await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: true,
        extras: {'heartbeat': true},
      );
      await _syncLocations();
    } catch (error) {
      developer.log('Failed to refresh heartbeat location', error: error);
    }
    await _runWatchdog();
  }

  /// Warns the operator when the device has not successfully reported a
  /// location for too long while tracking is supposed to be running. Runs on
  /// every heartbeat, including in the background/headless isolate.
  static Future<void> _runWatchdog() async {
    if (Preferences.instance.getBool(Preferences.watchdog) == false) return;
    try {
      final state = await bg.BackgroundGeolocation.state;
      if (!state.enabled) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final lastSync = Preferences.instance.getInt(Preferences.lastSync);
      final timeoutMs = Preferences.watchdogTimeoutSeconds * 1000;
      final isStalled = lastSync == null || (now - lastSync) > timeoutMs;
      if (!isStalled) return;

      final lastAlert =
          Preferences.instance.getInt(Preferences.lastWatchdogAlert) ?? 0;
      final realertMs = Preferences.watchdogRealertSeconds * 1000;
      if (now - lastAlert < realertMs) return;

      FirebaseCrashlytics.instance.log('geolocation_watchdog_alert');
      await NotificationService.showTrackingStalled();
      await Preferences.instance.setInt(Preferences.lastWatchdogAlert, now);
    } catch (error) {
      developer.log('Watchdog check failed', error: error);
    }
  }

  static Future<void> onConnectivityChange(
    bg.ConnectivityChangeEvent event,
  ) async {
    FirebaseCrashlytics.instance.log(
      'geolocation_connectivity:${event.connected}',
    );
    if (event.connected) {
      await _syncLocations();
    }
  }

  static Future<void> onLocation(bg.Location location) async {
    if (_shouldDelete(location)) {
      try {
        await bg.BackgroundGeolocation.destroyLocation(location.uuid);
      } catch (error) {
        developer.log('Failed to delete location', error: error);
      }
    } else {
      LocationCache.set(location);
      try {
        await _syncLocations();
      } catch (error) {
        developer.log('Failed to send location', error: error);
      }
    }
  }

  static bool _shouldDelete(bg.Location location) {
    if (!location.isMoving) return false;
    if (location.extras?.isNotEmpty == true) return false;

    final lastLocation = LocationCache.get();
    if (lastLocation == null) return false;

    final isHighestAccuracy =
        Preferences.instance.getString(Preferences.accuracy) == 'highest';
    final duration =
        DateTime.parse(
          location.timestamp,
        ).difference(DateTime.parse(lastLocation.timestamp)).inSeconds;

    if (!isHighestAccuracy) {
      final fastestInterval = Preferences.instance.getInt(
        Preferences.fastestInterval,
      );
      if (fastestInterval != null && duration < fastestInterval) return true;
    }

    final distance = _distance(lastLocation, location);

    final distanceFilter =
        Preferences.instance.getInt(Preferences.distance) ?? 0;
    if (distanceFilter > 0 && distance >= distanceFilter) return false;

    if (distanceFilter == 0 || isHighestAccuracy) {
      final intervalFilter =
          Preferences.instance.getInt(Preferences.interval) ?? 0;
      if (intervalFilter > 0 && duration >= intervalFilter) return false;
    }

    if (isHighestAccuracy &&
        lastLocation.heading >= 0 &&
        location.coords.heading > 0) {
      final angle = (location.coords.heading - lastLocation.heading).abs();
      final angleFilter = Preferences.instance.getInt(Preferences.angle) ?? 0;
      if (angleFilter > 0 && angle >= angleFilter) return false;
    }

    return true;
  }

  static double _distance(Location from, bg.Location to) {
    const earthRadius = 6371008.8; // meters
    final dLat = _degToRad(to.coords.latitude - from.latitude);
    final dLon = _degToRad(to.coords.longitude - from.longitude);
    final sinLat = sin(dLat / 2);
    final sinLon = sin(dLon / 2);
    final a =
        sinLat * sinLat +
        cos(_degToRad(from.latitude)) *
            cos(_degToRad(to.coords.latitude)) *
            sinLon *
            sinLon;
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double degree) => degree * pi / 180.0;

  static Future<void> _syncLocations() async {
    try {
      await bg.BackgroundGeolocation.sync();
    } catch (error) {
      developer.log('Failed to sync locations', error: error);
    }
  }
}

Future<void>? _firebaseInitialization;

@pragma('vm:entry-point')
void headlessTask(bg.HeadlessEvent headlessEvent) async {
  await (_firebaseInitialization ??= Firebase.initializeApp());
  await Preferences.init();
  FirebaseCrashlytics.instance.log(
    'geolocation_headless:${headlessEvent.name}',
  );
  switch (headlessEvent.name) {
    case bg.Event.ENABLEDCHANGE:
      await GeolocationService.onEnabledChange(headlessEvent.event);
    case bg.Event.MOTIONCHANGE:
      await GeolocationService.onMotionChange(headlessEvent.event);
    case bg.Event.HEARTBEAT:
      await GeolocationService.onHeartbeat(headlessEvent.event);
    case bg.Event.CONNECTIVITYCHANGE:
      await GeolocationService.onConnectivityChange(headlessEvent.event);
    case bg.Event.HTTP:
      await GeolocationService.onHttp(headlessEvent.event);
    case bg.Event.LOCATION:
      await GeolocationService.onLocation(headlessEvent.event);
  }
}
