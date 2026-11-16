import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
  static const int magic0 = 0x50; // 'P'
  static const int magic1 = 0x50; // 'P'
  static const int magic2 = 0x43; // 'C'
  static const int magic3 = 0x4D; // 'M'

  // Pre-allocated 4MB linear ring-free packet assembly buffer
  final Uint8List _ringBuf = Uint8List(4 * 1024 * 1024);
  int _bufWritePos = 0;

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

  void _onDataReceived(Uint8List chunk) {
    final int chunkLen = chunk.length;
    _byteCount += chunkLen;

    // Guard against buffer overflow
    if (_bufWritePos + chunkLen > _ringBuf.length) {
      _bufWritePos = 0; // Reset if choked
    }

    _ringBuf.setRange(_bufWritePos, _bufWritePos + chunkLen, chunk);
    _bufWritePos += chunkLen;

    int readOffset = 0;

    while (true) {
      final int available = _bufWritePos - readOffset;
      if (available < headerSize) break;

      // Scan for 'PPCM' magic bytes
      int magicIdx = -1;
      for (int i = readOffset; i <= _bufWritePos - 4; i++) {
        if (_ringBuf[i] == magic0 &&
            _ringBuf[i + 1] == magic1 &&
            _ringBuf[i + 2] == magic2 &&
            _ringBuf[i + 3] == magic3) {
          magicIdx = i;
          break;
        }
      }

      if (magicIdx == -1) {
        // No magic header found in the entire buffer; discard garbage
        _bufWritePos = 0;
        break;
      }

      readOffset = magicIdx;
      if (_bufWritePos - readOffset < headerSize) break;

      final byteData = ByteData.sublistView(_ringBuf, readOffset, readOffset + headerSize);
      final int packetType = byteData.getUint8(4);
      final int cameraIdIndex = byteData.getUint16(6, Endian.big);
      final int payloadLength = byteData.getUint32(8, Endian.big);
      final int timestampMs = byteData.getUint32(12, Endian.big);

      // Sanity check payload size (< 5MB)
      if (payloadLength > 5 * 1024 * 1024) {
        readOffset += 4;
        continue;
      }

      final int totalPacketSize = headerSize + payloadLength;
      if (_bufWritePos - readOffset < totalPacketSize) {
        // Need more data from next TCP packet
        break;
      }

      final int payloadStart = readOffset + headerSize;
      final int payloadEnd = payloadStart + payloadLength;

      if (packetType == 0x01) {
        _frameCount++;
        // Fast zero-copy typed view of the frame JPEG payload
        final payloadView = Uint8List.sublistView(_ringBuf, payloadStart, payloadEnd);
        onFrameReceived(payloadView, timestampMs, cameraIdIndex);
      } else if (packetType == 0x02 || packetType == 0x03) {
        try {
          final payloadBytes = Uint8List.sublistView(_ringBuf, payloadStart, payloadEnd);
          final jsonStr = utf8.decode(payloadBytes);
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
        } catch (_) {}
      }

      readOffset += totalPacketSize;
    }

    // Shift remaining unprocessed bytes to front
    if (readOffset > 0) {
      final int remaining = _bufWritePos - readOffset;
      if (remaining > 0) {
        _ringBuf.setRange(0, remaining, _ringBuf, readOffset);
      }
      _bufWritePos = remaining;
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
    _bufWritePos = 0;
  }
}
