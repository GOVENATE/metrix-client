import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:permission_handler/permission_handler.dart';

import 'preferences.dart';

enum HealthStatus { ok, warning, error }

enum HealthCheckId {
  tracking,
  deviceId,
  location,
  activity,
  notifications,
  battery,
  serverUrl,
  upload,
}

class HealthCheck {
  final HealthCheckId id;
  final HealthStatus status;

  /// Extra detail rendered as the subtitle (e.g. the configured URL or the
  /// number of seconds since the last successful upload). Localized by the UI.
  final String? info;

  const HealthCheck(this.id, this.status, {this.info});
}

/// Runs the "auto-scan" of every permission and setting required for reliable
/// background tracking, and exposes one-tap repair actions for each item.
class HealthService {
  /// Reads the current state of every check without prompting the user.
  static Future<List<HealthCheck>> runChecks() async {
    final tracking = await _trackingCheck();
    final deviceId = _deviceIdCheck();
    final location = await _locationCheck();
    final notifications = await _notificationsCheck();
    final serverUrl = _serverUrlCheck();
    final upload = await _uploadCheck(tracking.status == HealthStatus.ok);

    return [
      tracking,
      deviceId,
      location,
      if (Platform.isAndroid) await _activityCheck(),
      notifications,
      if (Platform.isAndroid) await _batteryCheck(),
      serverUrl,
      upload,
    ];
  }

  static HealthStatus overallStatus(List<HealthCheck> checks) {
    if (checks.any((c) => c.status == HealthStatus.error)) {
      return HealthStatus.error;
    }
    if (checks.any((c) => c.status == HealthStatus.warning)) {
      return HealthStatus.warning;
    }
    return HealthStatus.ok;
  }

  // --- Individual checks ----------------------------------------------------

  static Future<HealthCheck> _trackingCheck() async {
    final state = await bg.BackgroundGeolocation.state;
    return HealthCheck(
      HealthCheckId.tracking,
      state.enabled ? HealthStatus.ok : HealthStatus.error,
    );
  }

  static Future<HealthCheck> _locationCheck() async {
    final always = await Permission.locationAlways.status;
    if (always.isGranted) {
      return const HealthCheck(HealthCheckId.location, HealthStatus.ok);
    }
    final whenInUse = await Permission.locationWhenInUse.status;
    // Foreground granted but not "all the time" — tracking dies in background.
    final status = whenInUse.isGranted
        ? HealthStatus.warning
        : HealthStatus.error;
    return HealthCheck(HealthCheckId.location, status);
  }

  static Future<HealthCheck> _activityCheck() async {
    final status = await Permission.activityRecognition.status;
    return HealthCheck(HealthCheckId.activity, _fromPermission(status));
  }

  static Future<HealthCheck> _notificationsCheck() async {
    final status = await Permission.notification.status;
    return HealthCheck(HealthCheckId.notifications, _fromPermission(status));
  }

  static Future<HealthCheck> _batteryCheck() async {
    final unrestricted = await isBatteryUnrestricted();
    return HealthCheck(
      HealthCheckId.battery,
      unrestricted ? HealthStatus.ok : HealthStatus.error,
    );
  }

  /// Flags a provisional identifier: fresh installs seed a random number so the
  /// app works out of the box, but the operator must replace it with the real
  /// 15-digit phone IMEI or positions land under a throwaway device id.
  static HealthCheck _deviceIdCheck() {
    final id = Preferences.instance.getString(Preferences.id);
    final valid = Preferences.isValidImei(id);
    return HealthCheck(
      HealthCheckId.deviceId,
      valid ? HealthStatus.ok : HealthStatus.warning,
      info: id,
    );
  }

  static HealthCheck _serverUrlCheck() {
    final server = Preferences.instance.getString(Preferences.primaryUrl);
    if (server == null || server.isEmpty || !_validServer(server)) {
      return HealthCheck(
        HealthCheckId.serverUrl,
        HealthStatus.error,
        info: server,
      );
    }
    final matches = _sameServer(server, Preferences.defaultPrimaryUrl);
    return HealthCheck(
      HealthCheckId.serverUrl,
      matches ? HealthStatus.ok : HealthStatus.warning,
      info: server,
    );
  }

  static bool _validServer(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static Future<HealthCheck> _uploadCheck(bool trackingEnabled) async {
    final seconds = secondsSinceUpload();
    if (seconds == null) {
      // Never reported. Only an error once tracking is supposed to be running.
      return HealthCheck(
        HealthCheckId.upload,
        trackingEnabled ? HealthStatus.error : HealthStatus.warning,
      );
    }
    final HealthStatus status;
    if (seconds <= Preferences.watchdogTimeoutSeconds) {
      status = HealthStatus.ok;
    } else if (seconds <= Preferences.watchdogTimeoutSeconds * 2) {
      status = HealthStatus.warning;
    } else {
      status = HealthStatus.error;
    }
    return HealthCheck(HealthCheckId.upload, status, info: seconds.toString());
  }

  // --- Repair actions -------------------------------------------------------

  /// Requests every permission in the correct order, then prompts to lift
  /// battery restrictions. This is the "Escanear y reparar" action.
  static Future<void> requestAll() async {
    await requestNotifications();
    await requestLocation();
    if (Platform.isAndroid) {
      await requestActivity();
      await requestBattery();
    }
  }

  static Future<void> requestLocation() async {
    // Foreground must be granted before background ("all the time") can be.
    if (!await Permission.locationWhenInUse.isGranted) {
      await Permission.locationWhenInUse.request();
    }
    await Permission.locationAlways.request();
  }

  static Future<void> requestActivity() async {
    await Permission.activityRecognition.request();
  }

  static Future<void> requestNotifications() async {
    await Permission.notification.request();
  }

  static Future<void> requestBattery() async {
    try {
      if (!await bg.DeviceSettings.isIgnoringBatteryOptimizations) {
        final request =
            await bg.DeviceSettings.showIgnoreBatteryOptimizations();
        await bg.DeviceSettings.show(request);
      }
    } catch (error) {
      developer.log('Failed to request battery exemption', error: error);
    }
  }

  static Future<void> openSettings() => openAppSettings();

  // --- Helpers --------------------------------------------------------------

  static Future<bool> isBatteryUnrestricted() async {
    try {
      return await bg.DeviceSettings.isIgnoringBatteryOptimizations;
    } catch (error) {
      developer.log('Failed to read battery optimization state', error: error);
      return true;
    }
  }

  /// Seconds since the last successful upload, or null if none recorded.
  static int? secondsSinceUpload() {
    final lastSync = Preferences.instance.getInt(Preferences.lastSync);
    if (lastSync == null) return null;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastSync;
    return (elapsed / 1000).round();
  }

  static HealthStatus _fromPermission(PermissionStatus status) {
    if (status.isGranted) return HealthStatus.ok;
    if (status.isLimited || status.isProvisional) return HealthStatus.warning;
    return HealthStatus.error;
  }

  static bool _sameServer(String a, String b) {
    final ua = Uri.tryParse(a);
    final ub = Uri.tryParse(b);
    if (ua == null || ub == null) return false;
    return ua.host == ub.host && ua.port == ub.port;
  }
}
