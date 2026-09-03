import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;

import 'preferences.dart';

class ConfigurationService {
  static Future<void> applyUri(Uri uri) async {
    final parameters = uri.queryParameters;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final value = '${uri.origin}${uri.path}';
      await Preferences.instance.setString(Preferences.primaryUrl, value);
    } else {
      final url = parameters['primary_url'] ?? parameters['url'];
      if (url != null) {
        await Preferences.instance.setString(Preferences.primaryUrl, url);
      }
    }
    await Preferences.instance.setString(
      Preferences.url,
      Preferences.serverUrl,
    );
    await _applyStringParameter(parameters, Preferences.id);
    await _applyStringParameter(parameters, Preferences.accuracy);
    await _applyIntParameter(parameters, Preferences.distance);
    await _applyIntParameter(parameters, Preferences.interval);
    await _applyIntParameter(parameters, Preferences.angle);
    await _applyIntParameter(parameters, Preferences.heartbeat);
    await _applyIntParameter(parameters, Preferences.fastestInterval);
    await _applyBoolParameter(parameters, Preferences.wakelock);
    await _applyBoolParameter(parameters, Preferences.stopDetection);
    await Preferences.instance.setBool(Preferences.buffer, true);
    await bg.BackgroundGeolocation.setConfig(
      Preferences.geolocationConfig(false),
    );
    await bg.BackgroundGeolocation.sync();
  }

  static Future<void> _applyStringParameter(
    Map<String, String> parameters,
    String key,
  ) async {
    final value = parameters[key];
    if (value != null) {
      await Preferences.instance.setString(key, value);
    }
  }

  static Future<void> _applyIntParameter(
    Map<String, String> parameters,
    String key,
  ) async {
    final stringValue = parameters[key];
    if (stringValue != null) {
      final value = int.tryParse(stringValue);
      if (value != null) {
        await Preferences.instance.setInt(key, value);
      }
    }
  }

  static Future<void> _applyBoolParameter(
    Map<String, String> parameters,
    String key,
  ) async {
    final value = parameters[key];
    if (value != null) {
      switch (value) {
        case 'false':
          await Preferences.instance.setBool(key, false);
        case 'true':
          await Preferences.instance.setBool(key, true);
      }
    }
  }
}
