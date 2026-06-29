import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:metrix_client/brand.dart';
import 'package:metrix_client/health_service.dart';
import 'package:metrix_client/main.dart';
import 'package:metrix_client/password_service.dart';

import 'l10n/app_localizations.dart';
import 'settings_screen.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  List<HealthCheck> _checks = [];
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final checks = await HealthService.runChecks();
    if (!mounted) return;
    setState(() {
      _checks = checks;
      _loading = false;
    });
  }

  Future<void> _scanAndRepair() async {
    setState(() => _scanning = true);
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.healthScanningMessage),
      ),
    );
    await HealthService.requestAll();
    if (!mounted) return;
    setState(() => _scanning = false);
    await _refresh();
  }

  Future<void> _fix(HealthCheckId id) async {
    switch (id) {
      case HealthCheckId.tracking:
        await _startTracking();
      case HealthCheckId.location:
        await HealthService.requestLocation();
      case HealthCheckId.activity:
        await HealthService.requestActivity();
      case HealthCheckId.notifications:
        await HealthService.requestNotifications();
      case HealthCheckId.battery:
        await HealthService.requestBattery();
      case HealthCheckId.serverUrl:
        if (await PasswordService.authenticate(context) && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        }
      case HealthCheckId.upload:
        await _sendLocationNow();
    }
    await _refresh();
  }

  Future<void> _startTracking() async {
    if (!await PasswordService.authenticate(context) || !mounted) return;
    final errorText = AppLocalizations.of(context)!.trackingStartError;
    try {
      await bg.BackgroundGeolocation.start();
    } on PlatformException {
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(errorText)),
      );
    }
  }

  Future<void> _sendLocationNow() async {
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.healthTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildOverallBanner(l10n),
                  const SizedBox(height: 16),
                  ..._checks.map(_buildCheckTile),
                ],
              ),
    );
  }

  Widget _buildOverallBanner(AppLocalizations l10n) {
    final status = HealthService.overallStatus(_checks);
    final color = _statusColor(status);
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(_statusIcon(status), color: color, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _overallMessage(l10n, status),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _scanning ? null : _scanAndRepair,
                icon:
                    _scanning
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.health_and_safety),
                label: Text(l10n.healthScanButton),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckTile(HealthCheck check) {
    final l10n = AppLocalizations.of(context)!;
    final color = _statusColor(check.status);
    return Card(
      child: ListTile(
        leading: Icon(_statusIcon(check.status), color: color),
        title: Text(_checkTitle(l10n, check.id)),
        subtitle: Text(_checkSubtitle(l10n, check)),
        isThreeLine: check.id == HealthCheckId.serverUrl,
        trailing:
            check.status == HealthStatus.ok
                ? Icon(Icons.check, color: Brand.green)
                : TextButton(
                  onPressed: () => _fix(check.id),
                  child: Text(l10n.healthFixButton),
                ),
      ),
    );
  }

  // --- Presentation helpers -------------------------------------------------

  Color _statusColor(HealthStatus status) => switch (status) {
    HealthStatus.ok => Brand.green,
    HealthStatus.warning => Colors.orange.shade700,
    HealthStatus.error => Colors.red.shade600,
  };

  IconData _statusIcon(HealthStatus status) => switch (status) {
    HealthStatus.ok => Icons.check_circle,
    HealthStatus.warning => Icons.warning_amber_rounded,
    HealthStatus.error => Icons.cancel,
  };

  String _overallMessage(AppLocalizations l10n, HealthStatus status) =>
      switch (status) {
        HealthStatus.ok => l10n.healthCardOk,
        HealthStatus.warning => l10n.healthCardWarning,
        HealthStatus.error => l10n.healthCardError,
      };

  String _checkTitle(AppLocalizations l10n, HealthCheckId id) => switch (id) {
    HealthCheckId.tracking => l10n.checkTrackingTitle,
    HealthCheckId.location => l10n.checkLocationTitle,
    HealthCheckId.activity => l10n.checkActivityTitle,
    HealthCheckId.notifications => l10n.checkNotificationsTitle,
    HealthCheckId.battery => l10n.checkBatteryTitle,
    HealthCheckId.serverUrl => l10n.checkUrlTitle,
    HealthCheckId.upload => l10n.checkUploadTitle,
  };

  String _checkSubtitle(AppLocalizations l10n, HealthCheck check) {
    switch (check.id) {
      case HealthCheckId.tracking:
        return check.status == HealthStatus.ok
            ? l10n.checkTrackingOk
            : l10n.checkTrackingError;
      case HealthCheckId.location:
        return switch (check.status) {
          HealthStatus.ok => l10n.checkLocationOk,
          HealthStatus.warning => l10n.checkLocationWarning,
          HealthStatus.error => l10n.checkLocationError,
        };
      case HealthCheckId.activity:
      case HealthCheckId.notifications:
        return switch (check.status) {
          HealthStatus.ok => l10n.permissionGranted,
          HealthStatus.warning => l10n.permissionLimited,
          HealthStatus.error => l10n.permissionDenied,
        };
      case HealthCheckId.battery:
        return check.status == HealthStatus.ok
            ? l10n.checkBatteryOk
            : l10n.checkBatteryError;
      case HealthCheckId.serverUrl:
        final note = switch (check.status) {
          HealthStatus.ok => l10n.checkUrlOk,
          HealthStatus.warning => l10n.checkUrlMismatch,
          HealthStatus.error => l10n.checkUrlError,
        };
        final url = check.info ?? '';
        return url.isEmpty ? note : '$url\n$note';
      case HealthCheckId.upload:
        final seconds = int.tryParse(check.info ?? '');
        if (seconds == null) return l10n.uploadNever;
        final minutes = seconds ~/ 60;
        return minutes <= 0 ? l10n.uploadJustNow : l10n.uploadAgo(minutes);
    }
  }
}
