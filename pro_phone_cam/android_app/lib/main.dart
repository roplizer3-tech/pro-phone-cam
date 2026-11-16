import 'dart:async';
import 'package:flutter/material.dart';
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

          // True-Black OLED Screen Overlay for Power Saving & Heat Reduction
          if (_isBlackScreenActive)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _toggleBlackScreen(false),
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_rounded,
                        size: 48,
                        color: Colors.white.withAlpha(51),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '1080p @ 60 FPS Streaming Active\nTap anywhere to wake display',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withAlpha(77),
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withAlpha(51),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF818CF8)),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ProPhone Cam',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  'USB 1080p @ 60 FPS Native',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          onPressed: _toggleTorch,
          icon: Icon(
            _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            color: _isTorchOn ? Colors.amberAccent : Colors.white38,
          ),
          tooltip: 'Toggle Flashlight',
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
          color: _isConnectedToPc ? const Color(0xFF10B981) : Colors.white12,
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
                  color: (_isConnectedToPc ? const Color(0xFF10B981) : Colors.amber).withAlpha(128),
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
                  _isConnectedToPc ? 'Connected to Windows Studio' : 'Waiting for USB Connection',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusMessage.isEmpty
                      ? (_isConnectedToPc ? 'Zero-latency TCP streaming' : 'Port 5000 listening via ADB')
                      : _statusMessage,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          const Icon(Icons.usb_rounded, color: Colors.white38),
        ],
      ),
    );
  }

  Widget _buildLensSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PHYSICAL CAMERA SENSORS',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.1),
        ),
        const SizedBox(height: 12),
        if (_cameras.isEmpty)
          const Text('Discovering cameras via Camera2...', style: TextStyle(color: Colors.white54, fontSize: 13))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cameras.map((cam) {
              final bool isSelected = cam.id == _selectedCameraId;
              return ChoiceChip(
                label: Text('${cam.label} (${cam.facing})'),
                selected: isSelected,
                selectedColor: const Color(0xFF6366F1),
                backgroundColor: const Color(0xFF1E222D),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                onSelected: (val) {
                  if (val) _switchCamera(cam.id);
                },
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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: Color(0xFF818CF8)),
              SizedBox(width: 8),
              Text(
                'Hardware Tuners Active',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Zoom, Focus, Exposure & White Balance parameters are automatically orchestrated from Windows Control Studio via bi-directional JSON control link.',
            style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildBlackScreenButton() {
    return ElevatedButton.icon(
      onPressed: () => _toggleBlackScreen(true),
      icon: const Icon(Icons.energy_savings_leaf_rounded, color: Colors.white),
      label: const Text('Enable OLED Power-Saver Mode'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E222D),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white12),
        ),
      ),
    );
  }
}
