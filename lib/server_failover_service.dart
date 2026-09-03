import 'dart:developer' as developer;

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;

import 'preferences.dart';

/// Keeps the SDK's durable outbox pointed at a healthy ingestion server.
///
/// The new VPS is always preferred. After repeated transport/server failures,
/// pending locations remain in the native database and are retried against the
/// legacy VPS. Client/authentication errors never trigger failover.
class ServerFailoverService {
  static const int failuresBeforeSwitch = 3;
  static const Duration primaryRetryInterval = Duration(minutes: 30);
  static bool _switching = false;

  static bool isRetryableStatus(int status) {
    return status <= 0 ||
        status == 408 ||
        status == 425 ||
        status == 429 ||
        status >= 500;
  }

  static Future<void> handleHttp(bg.HttpEvent event) async {
    await Preferences.instance.setInt(Preferences.lastHttpStatus, event.status);

    if (event.success) {
      await Preferences.instance.setInt(Preferences.serverFailures, 0);
      final selected =
          Preferences.instance.getString(Preferences.activeServer) ?? 'primary';
      await Preferences.instance.setString(
        Preferences.lastSuccessfulServer,
        selected,
      );

      if (selected == 'fallback' && _shouldRetryPrimary()) {
        await switchTo('primary', sync: false);
      }
      return;
    }

    if (!isRetryableStatus(event.status)) {
      await Preferences.instance.setInt(Preferences.serverFailures, 0);
      return;
    }

    final failures =
        (Preferences.instance.getInt(Preferences.serverFailures) ?? 0) + 1;
    await Preferences.instance.setInt(Preferences.serverFailures, failures);
    if (failures < failuresBeforeSwitch) return;

    final selected =
        Preferences.instance.getString(Preferences.activeServer) ?? 'primary';
    await switchTo(selected == 'primary' ? 'fallback' : 'primary');
  }

  static bool _shouldRetryPrimary() {
    final switchedAt =
        Preferences.instance.getInt(Preferences.lastServerSwitch) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - switchedAt;
    return elapsed >= primaryRetryInterval.inMilliseconds;
  }

  static Future<void> switchTo(String server, {bool sync = true}) async {
    if (_switching || (server != 'primary' && server != 'fallback')) return;
    final current =
        Preferences.instance.getString(Preferences.activeServer) ?? 'primary';
    if (current == server) return;

    _switching = true;
    try {
      await Preferences.instance.setString(Preferences.activeServer, server);
      await Preferences.instance.setString(
        Preferences.url,
        Preferences.activeUrl,
      );
      await Preferences.instance.setInt(Preferences.serverFailures, 0);
      await Preferences.instance.setInt(
        Preferences.lastServerSwitch,
        DateTime.now().millisecondsSinceEpoch,
      );
      await bg.BackgroundGeolocation.setConfig(
        Preferences.geolocationConfig(false),
      );
      developer.log('Location upload server changed to $server');
      if (sync) await bg.BackgroundGeolocation.sync();
    } catch (error) {
      developer.log('Failed to change location upload server', error: error);
    } finally {
      _switching = false;
    }
  }

  static Future<void> usePrimary() => switchTo('primary');
}
