import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class AdbDaemon {
  final Function(String serial) onDevicePlugged;
  final VoidCallback onDeviceUnplugged;
  final Function(String log) onLog;

  Timer? _pollingTimer;
  bool _isDeviceConnected = false;
  String? _connectedDeviceSerial;
  String? _cachedAdbPath;
  bool _isAutoLaunchTriggered = false;

  AdbDaemon({
    required this.onDevicePlugged,
    required this.onDeviceUnplugged,
    required this.onLog,
  });

  Future<String?> resolveAdbPath() async {
    if (_cachedAdbPath != null) return _cachedAdbPath;

    final appDir = File(Platform.resolvedExecutable).parent.path;
    final bundledAdb = File(p.join(appDir, 'tools', 'adb.exe'));
    if (await bundledAdb.exists()) {
      _cachedAdbPath = bundledAdb.path;
      onLog('Using portable bundled ADB: ${_cachedAdbPath}');
      return _cachedAdbPath;
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final sdkAdb = File(p.join(localAppData, 'Android', 'Sdk', 'platform-tools', 'adb.exe'));
      if (await sdkAdb.exists()) {
        _cachedAdbPath = sdkAdb.path;
        onLog('Using Android SDK ADB: ${_cachedAdbPath}');
        return _cachedAdbPath;
      }
    }

    try {
      final res = await Process.run('where', ['adb.exe'], runInShell: true);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final firstPath = res.stdout.toString().trim().split('\n').first.trim();
        _cachedAdbPath = firstPath;
        onLog('Using System PATH ADB: ${_cachedAdbPath}');
        return _cachedAdbPath;
      }
    } catch (_) {}

    _cachedAdbPath = 'adb';
    return _cachedAdbPath;
  }

  void start() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollUsbDevices());
    onLog('Auto-USB Plug & Play daemon started (Polling every 2s)...');
    _pollUsbDevices();
  }

  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _pollUsbDevices() async {
    final adb = await resolveAdbPath();
    if (adb == null) return;

    try {
      final result = await Process.run(adb, ['devices'], runInShell: true);
      if (result.exitCode != 0) return;

      final lines = result.stdout.toString().split('\n');
      String? foundSerial;

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('List of devices attached')) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1] == 'device') {
          foundSerial = parts[0];
          break;
        }
      }

      if (foundSerial != null) {
        if (!_isDeviceConnected || _connectedDeviceSerial != foundSerial) {
          _isDeviceConnected = true;
          _connectedDeviceSerial = foundSerial;
          _isAutoLaunchTriggered = false;
          onLog('USB Phone Connected! Serial: $foundSerial');
          await _setupTunnelAndLaunch(adb, foundSerial);
          onDevicePlugged(foundSerial);
        }
      } else {
        if (_isDeviceConnected) {
          _isDeviceConnected = false;
          _connectedDeviceSerial = null;
          _isAutoLaunchTriggered = false;
          onLog('USB Phone Disconnected.');
          onDeviceUnplugged();
        }
      }
    } catch (_) {
      // Ignore transient scan failure while device initializes
    }
  }

  Future<void> _setupTunnelAndLaunch(String adb, String serial) async {
    try {
      onLog('Executing: adb -s $serial forward tcp:5000 tcp:5000');
      final fwdRes = await Process.run(adb, ['-s', serial, 'forward', 'tcp:5000', 'tcp:5000'], runInShell: true);
      if (fwdRes.exitCode == 0) {
        onLog('USB Port 5000 forwarded with zero-latency tunnel.');
      }

      if (!_isAutoLaunchTriggered) {
        onLog('Auto-launching ProPhone Cam on device...');
        await Process.run(adb, [
          '-s',
          serial,
          'shell',
          'am',
          'start',
          '-n',
          'com.prophone.cam/.MainActivity',
        ], runInShell: true);
        _isAutoLaunchTriggered = true;
      }
    } catch (e) {
      onLog('Failed configuring ADB tunnel: $e');
    }
  }

  Future<void> forceForwardAndLaunch() async {
    final adb = await resolveAdbPath();
    if (adb != null && _connectedDeviceSerial != null) {
      await _setupTunnelAndLaunch(adb, _connectedDeviceSerial!);
    }
  }
}
