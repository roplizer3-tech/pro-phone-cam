import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/camera_info.dart';

class FrameReceiver {
  final Function(Uint8List frameBytes, int timestampMs, int cameraId) onFrameReceived;
  final Function(List<CameraModel> cameras) onCamerasUpdated;
  final Function(int batteryLevel, bool isBlackScreen) onTelemetryReceived;
  final Function(bool isConnected) onConnectionStateChanged;
  final Function(double fps, double mbps) onPerformanceStats;
  final Function(String log) onLog;

  Socket? _socket;
  bool _isRunning = false;
  bool _isConnected = false;

  static const int headerSize = 16;
  static const List<int> magicBytes = [0x50, 0x50, 0x43, 0x4D];

  final BytesBuilder _buffer = BytesBuilder(copy: false);

  int _frameCount = 0;
  int _byteCount = 0;
  DateTime _lastStatsTime = DateTime.now();
  Timer? _statsTimer;

  FrameReceiver({
    required this.onFrameReceived,
    required this.onCamerasUpdated,
    required this.onTelemetryReceived,
    required this.onConnectionStateChanged,
    required this.onPerformanceStats,
    required this.onLog,
  });

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _connectLoop();
    _startStatsTimer();
  }

  void stop() {
    _isRunning = false;
    _statsTimer?.cancel();
    _disconnect();
  }

  Future<void> _connectLoop() async {
    while (_isRunning) {
      if (!_isConnected) {
        try {
          onLog('Attempting TCP handshake with Phone on 127.0.0.1:5000...');
          final socket = await Socket.connect('127.0.0.1', 5000, timeout: const Duration(seconds: 2));
          socket.setOption(SocketOption.tcpNoDelay, true);
          _socket = socket;
          _isConnected = true;
          onConnectionStateChanged(true);
          onLog('Connected to Phone USB Stream Server!');

          sendCommand({'action': 'get_cameras'});

          socket.listen(
            _onDataReceived,
            onError: (err) {
              onLog('Socket error: $err');
              _disconnect();
            },
            onDone: () {
              onLog('Socket closed by phone.');
              _disconnect();
            },
            cancelOnError: true,
          );
        } catch (_) {}
      }
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  void _onDataReceived(Uint8List data) {
    _byteCount += data.length;
    _buffer.add(data);

    while (true) {
      final currentBytes = _buffer.toBytes();
      if (currentBytes.length < headerSize) break;

      int magicIdx = -1;
      for (int i = 0; i <= currentBytes.length - 4; i++) {
        if (currentBytes[i] == magicBytes[0] &&
            currentBytes[i + 1] == magicBytes[1] &&
            currentBytes[i + 2] == magicBytes[2] &&
            currentBytes[i + 3] == magicBytes[3]) {
          magicIdx = i;
          break;
        }
      }

      if (magicIdx == -1) {
        _buffer.clear();
        break;
      }

      if (magicIdx > 0) {
        final remaining = currentBytes.sublist(magicIdx);
        _buffer.clear();
        _buffer.add(remaining);
        continue;
      }

      if (currentBytes.length < headerSize) break;

      final byteData = ByteData.sublistView(currentBytes, 0, headerSize);
      final int packetType = byteData.getUint8(4);
      final int cameraIdIndex = byteData.getUint16(6, Endian.big);
      final int payloadLength = byteData.getUint32(8, Endian.big);
      final int timestampMs = byteData.getUint32(12, Endian.big);

      final int totalPacketSize = headerSize + payloadLength;
      if (currentBytes.length < totalPacketSize) break;

      final payload = currentBytes.sublist(headerSize, totalPacketSize);
      final remaining = currentBytes.sublist(totalPacketSize);
      _buffer.clear();
      _buffer.add(remaining);

      if (packetType == 0x01) {
        _frameCount++;
        onFrameReceived(payload, timestampMs, cameraIdIndex);
      } else if (packetType == 0x02 || packetType == 0x03) {
        try {
          final jsonStr = utf8.decode(payload);
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic>) {
            final type = decoded['type'];
            if (type == 'camera_list') {
              final rawList = decoded['cameras'] as List<dynamic>? ?? [];
              final cams = rawList.map((e) => CameraModel.fromJson(e as Map<String, dynamic>)).toList();
              onCamerasUpdated(cams);
            } else if (type == 'telemetry') {
              final battery = (decoded['battery_level'] as num?)?.toInt() ?? 100;
              final blackScreen = decoded['black_screen'] as bool? ?? false;
              onTelemetryReceived(battery, blackScreen);
            }
          }
        } catch (e) {
          onLog('Error parsing telemetry JSON: $e');
        }
      }
    }
  }

  void sendCommand(Map<String, dynamic> command) {
    if (_socket != null && _isConnected) {
      try {
        final line = '${jsonEncode(command)}\n';
        _socket!.write(line);
      } catch (e) {
        onLog('Error sending command: $e');
      }
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final diff = now.difference(_lastStatsTime).inMilliseconds / 1000.0;
      if (diff > 0) {
        final fps = _frameCount / diff;
        final mbps = (_byteCount * 8.0) / (diff * 1024 * 1024);
        onPerformanceStats(fps, mbps);
      }
      _frameCount = 0;
      _byteCount = 0;
      _lastStatsTime = now;
    });
  }

  void _disconnect() {
    _isConnected = false;
    onConnectionStateChanged(false);
    try {
      _socket?.destroy();
      _socket = null;
    } catch (_) {}
    _buffer.clear();
  }
}
