import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import '../models/grading_settings.dart';

typedef _InitCamC = Int32 Function(Int32 width, Int32 height, Int32 fps);
typedef _InitCamDart = int Function(int width, int height, int fps);

typedef _SendJpegFrameC = Int32 Function(
  Pointer<Uint8> jpegBytes,
  Int32 jpegSize,
  Float brightness,
  Float contrast,
  Float saturation,
  Float warmth,
  Float tint,
  Int32 flipH,
  Int32 flipV,
  Int32 rotation,
);

typedef _SendJpegFrameDart = int Function(
  Pointer<Uint8> jpegBytes,
  int jpegSize,
  double brightness,
  double contrast,
  double saturation,
  double warmth,
  double tint,
  int flipH,
  int flipV,
  int rotation,
);

typedef _CloseCamC = Void Function();
typedef _CloseCamDart = void Function();

class VirtualCameraBridge {
  DynamicLibrary? _dylib;
  _InitCamDart? _initCam;
  _SendJpegFrameDart? _sendJpegFrame;
  _CloseCamDart? _closeCam;

  bool _isInitialized = false;
  bool get isDriverLoaded => _dylib != null;

  // Reusable native buffer for passing frame bytes without churn
  Pointer<Uint8>? _nativeBuffer;
  int _allocatedBufferSize = 0;

  VirtualCameraBridge() {
    _loadLibrary();
  }

  void _loadLibrary() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final dllPath = p.join(exeDir, 'prophone_cam_driver.dll');

      if (File(dllPath).existsSync()) {
        _dylib = DynamicLibrary.open(dllPath);
      } else {
        _dylib = DynamicLibrary.open('prophone_cam_driver.dll');
      }

      if (_dylib != null) {
        _initCam = _dylib!.lookupFunction<_InitCamC, _InitCamDart>('InitVirtualCamera');
        _sendJpegFrame = _dylib!.lookupFunction<_SendJpegFrameC, _SendJpegFrameDart>('SendJpegFrameWithGrading');
        _closeCam = _dylib!.lookupFunction<_CloseCamC, _CloseCamDart>('CloseVirtualCamera');
      }
    } catch (_) {}
  }

  bool initCamera(int width, int height, int fps) {
    if (_initCam != null) {
      final res = _initCam!(width, height, fps);
      _isInitialized = (res == 0);
      return _isInitialized;
    }
    return false;
  }

  int sendJpegFrame(Uint8List jpegBytes, GradingSettings settings) {
    if (_sendJpegFrame == null || !_isInitialized || jpegBytes.isEmpty) {
      return -1;
    }

    // Allocate / reuse native buffer
    final int len = jpegBytes.length;
    if (_nativeBuffer == null || _allocatedBufferSize < len) {
      if (_nativeBuffer != null) {
        calloc.free(_nativeBuffer!);
      }
      _allocatedBufferSize = (len * 1.5).toInt();
      _nativeBuffer = calloc<Uint8>(_allocatedBufferSize);
    }

    // Copy bytes to native memory
    _nativeBuffer!.asTypedList(len).setAll(0, jpegBytes);

    return _sendJpegFrame!(
      _nativeBuffer!,
      len,
      settings.brightness,
      settings.contrast,
      settings.saturation,
      settings.warmth,
      settings.tint,
      settings.flipHorizontal ? 1 : 0,
      settings.flipVertical ? 1 : 0,
      settings.rotation,
    );
  }

  Future<bool> registerSystemWebcam() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final batPath = p.join(exeDir, 'Register-Camera.bat');
      
      // Execute elevated registration using PowerShell Start-Process -Verb RunAs
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command',
        'Start-Process', 'cmd.exe',
        '-ArgumentList', "\"/c `\"$batPath`\"\"",
        '-Verb', 'RunAs',
        '-Wait'
      ]);

      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void close() {
    _closeCam?.call();
    if (_nativeBuffer != null) {
      calloc.free(_nativeBuffer!);
      _nativeBuffer = null;
      _allocatedBufferSize = 0;
    }
    _isInitialized = false;
  }
}
