import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'models/camera_info.dart';
import 'services/native_camera_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProPhoneCamApp());
}

class ProPhoneCamApp extends StatelessWidget {
  const ProPhoneCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProPhone Cam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E222D),
        ),
      ),
      home: const CameraStreamPage(),
    );
  }
}

class CameraStreamPage extends StatefulWidget {
  const CameraStreamPage({super.key});

  @override
  State<CameraStreamPage> createState() => _CameraStreamPageState();
}

class _CameraStreamPageState extends State<CameraStreamPage> {
  final NativeCameraBridge _bridge = NativeCameraBridge();
  StreamSubscription<dynamic>? _subscription;

  bool _isConnectedToPc = false;
  String _statusMessage = 'Initializing...';
  List<PhysicalCamera> _cameras = [];
  String _selectedCameraId = '0';
  bool _isBlackScreenActive = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Prevent device sleep during webcam session
    _initBridge();
  }

  Future<void> _initBridge() async {
    // Listen for native events (PC connection state, remote power-save toggles)
    _subscription = _bridge.eventStream.listen((event) {
      if (event is Map) {
        final String eventType = event['event'] as String? ?? '';
        if (eventType == 'connection_state') {
          setState(() {
            _isConnectedToPc = event['connected'] as bool? ?? false;
            _statusMessage = event['message'] as String? ?? '';
          });
        } else if (eventType == 'power_save_toggled') {
          setState(() {
            _isBlackScreenActive = event['active'] as bool? ?? false;
          });
        }
      }
    });

    // Start native USB server & default camera
    final bool started = await _bridge.startServer();
    if (started) {
      final List<PhysicalCamera> cams = await _bridge.getCameras();
      setState(() {
        _cameras = cams;
        if (cams.isNotEmpty) {
          _selectedCameraId = cams.first.id;
        }
      });
    }
  }

  void _toggleBlackScreen(bool enable) {
    setState(() {
      _isBlackScreenActive = enable;
    });
    _bridge.setBlackScreenMode(enable);
  }

  void _switchCamera(String id) {
    setState(() {
      _selectedCameraId = id;
    });
    _bridge.switchCamera(id);
  }

  void _toggleTorch() {
    final newState = !_isTorchOn;
    setState(() {
      _isTorchOn = newState;
    });
    _bridge.setTorch(newState);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.stopServer();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main Dashboard UI
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildConnectionStatusCard(),
                  const SizedBox(height: 24),
                  _buildLensSelector(),
                  const SizedBox(height: 24),
                  _buildHardwareControls(),
                  const Spacer(),
                  _buildBlackScreenButton(),
                ],
              ),
            ),
          ),

          // OLED Ultra-Low-Power Black Screen Overlay
          if (_isBlackScreenActive)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => _toggleBlackScreen(false),
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.videocam_rounded,
                          size: 48,
                          color: Colors.greenAccent.withOpacity(0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Streaming 1080p @ 60 FPS to PC',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Double-tap anywhere to wake screen',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.2),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF6366F1)),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'ProPhone Cam',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              '1080p @ 60 FPS • Zero-Latency USB',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConnectionStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isConnectedToPc ? const Color(0xFF10B981) : Colors.amber.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnectedToPc ? const Color(0xFF10B981) : Colors.amber,
              boxShadow: [
                BoxShadow(
                  color: (_isConnectedToPc ? const Color(0xFF10B981) : Colors.amber).withOpacity(0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnectedToPc ? 'Connected to PC' : 'Listening on Port 5000',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLensSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active Hardware Camera Lens',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _cameras.map((cam) {
            final isSelected = cam.id == _selectedCameraId;
            return ChoiceChip(
              selected: isSelected,
              label: Text('${cam.label} (${cam.facing})'),
              avatar: Icon(
                cam.facing == 'front' ? Icons.camera_front : Icons.camera_rear,
                size: 16,
                color: isSelected ? Colors.white : Colors.grey,
              ),
              selectedColor: const Color(0xFF6366F1),
              backgroundColor: const Color(0xFF1E222D),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (_) => _switchCamera(cam.id),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHardwareControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hardware Toggles',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('LED Torch / Flashlight'),
            subtitle: const Text('Keep flash on for face illumination in low light', style: TextStyle(fontSize: 11)),
            value: _isTorchOn,
            activeColor: const Color(0xFF6366F1),
            onChanged: (val) => _toggleTorch(),
          ),
        ],
      ),
    );
  }

  Widget _buildBlackScreenButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E222D),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF6366F1), width: 1.2),
        ),
      ),
      onPressed: () => _toggleBlackScreen(true),
      icon: const Icon(Icons.power_settings_new_rounded, color: Color(0xFF6366F1)),
      label: const Text(
        'Activate OLED Power-Saving Black Screen',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }
}
