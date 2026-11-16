import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'models/camera_info.dart';
import 'models/grading_settings.dart';
import 'services/adb_daemon.dart';
import 'services/frame_receiver.dart';
import 'services/virtual_camera_ffi.dart';
import 'widgets/preview_panel.dart';
import 'widgets/studio_controls.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProPhoneStudioApp());
}

class ProPhoneStudioApp extends StatelessWidget {
  const ProPhoneStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProPhone Webcam Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0C12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF131722),
        ),
      ),
      home: const StudioMainPage(),
    );
  }
}

class StudioMainPage extends StatefulWidget {
  const StudioMainPage({super.key});

  @override
  State<StudioMainPage> createState() => _StudioMainPageState();
}

class _StudioMainPageState extends State<StudioMainPage> {
  // Services
  late final AdbDaemon _adbDaemon;
  late final FrameReceiver _frameReceiver;
  final VirtualCameraBridge _virtualCam = VirtualCameraBridge();

  // State
  bool _isPhoneConnected = false;
  String _phoneSerial = 'None';
  bool _isVirtualCamRegistered = false;

  Uint8List? _latestFrameBytes;
  double _currentFps = 0.0;
  double _currentMbps = 0.0;
  int _batteryLevel = 100;
  bool _isOledBlackScreen = false;

  GradingSettings _grading = GradingSettings();
  List<CameraModel> _cameras = [];
  String _selectedCameraId = '0';
  double _currentZoom = 1.0;
  bool _isAutoFocus = true;
  double _manualFocusDistance = 0.3;
  int _exposureEv = 0;
  String _whiteBalance = 'auto';
  bool _isTorchOn = false;

  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _initServices();
  }

  Future<void> _loadSavedSettings() async {
    try {
      final file = File('prophone_preset.json');
      if (await file.exists()) {
        final savedJson = await file.readAsString();
        setState(() {
          _grading = GradingSettings.fromJson(jsonDecode(savedJson));
        });
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final file = File('prophone_preset.json');
      await file.writeAsString(jsonEncode(_grading.toJson()));
    } catch (_) {}
  }

  void _initServices() {
    // 1. Initialize DirectShow Virtual Camera in Shared Memory (1080p @ 60 FPS)
    _virtualCam.initCamera(1920, 1080, 60);

    // 2. Setup Frame Receiver
    _frameReceiver = FrameReceiver(
      onFrameReceived: (bytes, timestamp, cameraId) {
        setState(() {
          _latestFrameBytes = bytes;
        });
      },
      onCamerasUpdated: (cams) {
        setState(() {
          _cameras = cams;
          if (cams.isNotEmpty && !_cameras.any((c) => c.id == _selectedCameraId)) {
            _selectedCameraId = cams.first.id;
          }
        });
      },
      onTelemetryReceived: (battery, blackScreen) {
        setState(() {
          _batteryLevel = battery;
          _isOledBlackScreen = blackScreen;
        });
      },
      onConnectionStateChanged: (connected) {
        setState(() {
          _isPhoneConnected = connected;
        });
      },
      onPerformanceStats: (fps, mbps) {
        setState(() {
          _currentFps = fps;
          _currentMbps = mbps;
        });
      },
      onLog: _addLog,
    );

    // 3. Setup Auto-USB Plug & Play Daemon
    _adbDaemon = AdbDaemon(
      onDevicePlugged: (serial) {
        setState(() {
          _phoneSerial = serial;
        });
        _frameReceiver.start();
      },
      onDeviceUnplugged: () {
        setState(() {
          _phoneSerial = 'Disconnected';
          _isPhoneConnected = false;
          _latestFrameBytes = null;
        });
        _frameReceiver.stop();
      },
      onLog: _addLog,
    );

    _adbDaemon.start();
  }

  void _addLog(String msg) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _logs.insert(0, '[$time] $msg');
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  void _handleGradingChanged(GradingSettings newSettings) {
    setState(() {
      _grading = newSettings;
    });
    _saveSettings();
  }

  void _handleSwitchCamera(String id) {
    setState(() {
      _selectedCameraId = id;
    });
    _frameReceiver.sendCommand({'action': 'set_camera', 'camera_id': id});
  }

  void _handleZoomChanged(double zoom) {
    setState(() {
      _currentZoom = zoom;
    });
    _frameReceiver.sendCommand({'action': 'set_zoom', 'zoom_ratio': zoom});
  }

  void _handleFocusChanged(bool isAuto, double dist) {
    setState(() {
      _isAutoFocus = isAuto;
      _manualFocusDistance = dist;
    });
    _frameReceiver.sendCommand({
      'action': 'set_focus_mode',
      'mode': isAuto ? 'auto' : 'manual',
      'focus_distance': dist,
    });
  }

  void _handleToggleTorch() {
    final newState = !_isTorchOn;
    setState(() {
      _isTorchOn = newState;
    });
    _frameReceiver.sendCommand({'action': 'set_torch', 'enabled': newState});
  }

  void _handleToggleOledBlackScreen() {
    final newState = !_isOledBlackScreen;
    setState(() {
      _isOledBlackScreen = newState;
    });
    _frameReceiver.sendCommand({'action': 'set_power_save', 'enabled': newState});
  }

  void _registerVirtualCameraInSystem() {
    final res = _virtualCam.registerSystemWebcam('ProPhone Webcam');
    setState(() {
      _isVirtualCamRegistered = res;
    });
    _addLog(res
        ? 'Successfully registered "ProPhone Webcam" in Windows DirectShow!'
        : 'Failed registering DirectShow filter (Requires admin permissions).');
  }

  @override
  void dispose() {
    _adbDaemon.stop();
    _frameReceiver.stop();
    _virtualCam.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopAppBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left/Center: Video Canvas Preview & Real-Time Stats
                    Expanded(
                      child: PreviewPanel(
                        frameBytes: _latestFrameBytes,
                        grading: _grading,
                        currentFps: _currentFps,
                        currentMbps: _currentMbps,
                        batteryLevel: _batteryLevel,
                        isPhoneConnected: _isPhoneConnected,
                        isOledBlackScreenActive: _isOledBlackScreen,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right: Studio Controls (Anti-Mirror, Color Grading, Camera Remote)
                    StudioControls(
                      grading: _grading,
                      onGradingChanged: _handleGradingChanged,
                      cameras: _cameras,
                      selectedCameraId: _selectedCameraId,
                      onSwitchCamera: _handleSwitchCamera,
                      currentZoom: _currentZoom,
                      onZoomChanged: _handleZoomChanged,
                      isAutoFocus: _isAutoFocus,
                      manualFocusDistance: _manualFocusDistance,
                      onFocusChanged: _handleFocusChanged,
                      exposureEv: _exposureEv,
                      onExposureChanged: (ev) => setState(() => _exposureEv = ev),
                      whiteBalance: _whiteBalance,
                      onWhiteBalanceChanged: (wb) => setState(() => _whiteBalance = wb),
                      isTorchOn: _isTorchOn,
                      onToggleTorch: _handleToggleTorch,
                      isOledBlackScreen: _isOledBlackScreen,
                      onToggleOledBlackScreen: _handleToggleOledBlackScreen,
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF131722),
        border: Border(bottom: BorderSide(color: Color(0xFF232838))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.videocam_rounded, color: Color(0xFF818CF8), size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'ProPhone Webcam Studio',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                'Windows DirectShow Driver & Color Grading Pipeline',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const Spacer(),
          // DirectShow System Registration Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isVirtualCamRegistered ? const Color(0xFF10B981) : const Color(0xFF1E222D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: _isVirtualCamRegistered ? Colors.transparent : const Color(0xFF6366F1)),
              ),
            ),
            onPressed: _registerVirtualCameraInSystem,
            icon: Icon(
              _isVirtualCamRegistered ? Icons.check_circle_rounded : Icons.app_registration_rounded,
              size: 16,
            ),
            label: Text(
              _isVirtualCamRegistered ? 'ProPhone Webcam Registered' : 'Register Windows Webcam',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          // Reconnect USB button
          IconButton(
            tooltip: 'Force USB Re-Forward & Launch',
            icon: const Icon(Icons.sync_rounded, color: Colors.white70),
            onPressed: () => _adbDaemon.forceForwardAndLaunch(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: const Color(0xFF0F1117),
      child: Row(
        children: [
          Icon(
            _isPhoneConnected ? Icons.usb_rounded : Icons.usb_off_rounded,
            size: 14,
            color: _isPhoneConnected ? const Color(0xFF10B981) : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            _isPhoneConnected ? 'Device: $_phoneSerial' : 'No Phone Connected (Checking ADB...)',
            style: TextStyle(
              fontSize: 11,
              color: _isPhoneConnected ? Colors.white70 : Colors.grey,
            ),
          ),
          const SizedBox(width: 24),
          const Text('Tunnel: 127.0.0.1:5000', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          Text(
            _logs.isNotEmpty ? _logs.first : 'Ready.',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
