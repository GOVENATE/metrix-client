import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:metrix_client/brand.dart';
import 'package:metrix_client/health_service.dart';
import 'package:metrix_client/main.dart';
import 'package:metrix_client/password_service.dart';
import 'package:metrix_client/preferences.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;

import 'l10n/app_localizations.dart';
import 'health_screen.dart';
import 'status_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool trackingEnabled = false;
  bool? isMoving;
  List<HealthCheck> _healthChecks = [];

  @override
  void initState() {
    super.initState();
    _initState();
  }

  void _initState() async {
    final state = await bg.BackgroundGeolocation.state;
    setState(() {
      trackingEnabled = state.enabled;
      isMoving = state.isMoving;
    });
    _refreshHealth();
    bg.BackgroundGeolocation.onEnabledChange((bool enabled) {
      setState(() {
        trackingEnabled = enabled;
      });
      _refreshHealth();
    });
    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      setState(() {
        isMoving = location.isMoving;
      });
    });
  }

  Future<void> _refreshHealth() async {
    final checks = await HealthService.runChecks();
    if (!mounted) return;
    setState(() => _healthChecks = checks);
  }

  Future<void> _checkBatteryOptimizations(BuildContext context) async {
    try {
      if (!await bg.DeviceSettings.isIgnoringBatteryOptimizations) {
        final request =
            await bg.DeviceSettings.showIgnoreBatteryOptimizations();
        if (!request.seen && context.mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              scrollable: true,
              content: Text(AppLocalizations.of(context)!.optimizationMessage),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    bg.DeviceSettings.show(request);
                  },
                  child: Text(AppLocalizations.of(context)!.okButton),
                ),
              ],
            ),
          );
        }
      }
    } catch (error) {
      debugPrint(error.toString());
    }
  }

  Widget _buildBrandHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          Image.asset(Brand.logo, width: 156, height: 156, fit: BoxFit.contain),
          const SizedBox(height: 8),
          Text(
            'METRIX',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard() {
    final l10n = AppLocalizations.of(context)!;
    if (_healthChecks.isEmpty) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final status = HealthService.overallStatus(_healthChecks);
    final (color, icon, message) = switch (status) {
      HealthStatus.ok => (Brand.green, Icons.check_circle, l10n.healthCardOk),
      HealthStatus.warning => (
        Colors.orange.shade700,
        Icons.warning_amber_rounded,
        l10n.healthCardWarning,
      ),
      HealthStatus.error => (
        Colors.red.shade600,
        Icons.cancel,
        l10n.healthCardError,
      ),
    };
    return Card(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HealthScreen()),
          );
          _refreshHealth();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      l10n.healthReviewButton,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.trackingTitle),
              titleTextStyle: Theme.of(context).textTheme.headlineMedium,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.idLabel),
              subtitle: Text(
                Preferences.instance.getString(Preferences.id) ?? '',
              ),
            ),
            if (Platform.isAndroid) ...[
              Text(
                AppLocalizations.of(context)!.disclosureMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.trackingLabel),
              value: trackingEnabled,
              activeTrackColor: isMoving == false
                  ? Theme.of(context).colorScheme.secondary
                  : null,
              onChanged: (bool value) async {
                if (await PasswordService.authenticate(context) && mounted) {
                  if (value) {
                    try {
                      FirebaseCrashlytics.instance.log('tracking_toggle_start');
                      await bg.BackgroundGeolocation.start();
                      if (mounted) {
                        _checkBatteryOptimizations(context);
                      }
                    } on PlatformException catch (error) {
                      final providerState =
                          await bg.BackgroundGeolocation.providerState;
                      final isPermissionError =
                          providerState.status ==
                              bg
                                  .ProviderChangeEvent
                                  .AUTHORIZATION_STATUS_DENIED ||
                          providerState.status ==
                              bg
                                  .ProviderChangeEvent
                                  .AUTHORIZATION_STATUS_RESTRICTED;
                      if (!mounted) return;
                      messengerKey.currentState?.showSnackBar(
                        SnackBar(
                          content: Text(error.message ?? error.code),
                          duration: const Duration(seconds: 4),
                          action: isPermissionError
                              ? SnackBarAction(
                                  label: AppLocalizations.of(
                                    context,
                                  )!.settingsTitle,
                                  onPressed: () => AppSettings.openAppSettings(
                                    type: AppSettingsType.settings,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }
                  } else {
                    FirebaseCrashlytics.instance.log('tracking_toggle_stop');
                    bg.BackgroundGeolocation.stop();
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            OverflowBar(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    try {
                      await bg.BackgroundGeolocation.getCurrentPosition(
                        samples: 1,
                        persist: true,
                        extras: {'manual': true},
                      );
                    } on PlatformException catch (error) {
                      messengerKey.currentState?.showSnackBar(
                        SnackBar(content: Text(error.message ?? error.code)),
                      );
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.locationButton),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StatusScreen()),
                    );
                  },
                  child: Text(AppLocalizations.of(context)!.statusButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.settingsTitle),
              titleTextStyle: Theme.of(context).textTheme.headlineMedium,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.urlLabel),
              subtitle: Text(Preferences.serverUrl),
            ),
            const SizedBox(height: 8),
            OverflowBar(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    if (await PasswordService.authenticate(context) &&
                        mounted) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                      setState(() {});
                      _refreshHealth();
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.settingsButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(Brand.logo, width: 40, height: 40, fit: BoxFit.contain),
            const SizedBox(width: 8),
            const Text(Brand.appName),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildBrandHeader(),
            _buildHealthCard(),
            const SizedBox(height: 16),
            _buildTrackingCard(),
            const SizedBox(height: 16),
            _buildSettingsCard(),
          ],
        ),
      ),
    );
  }
}
