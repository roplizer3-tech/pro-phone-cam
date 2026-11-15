import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import '../models/grading_settings.dart';

typedef _InitCamC = Int32 Function(Int32 width, Int32 height, Int32 fps);
typedef _InitCamDart = int Function(int width, int height, int fps);

typedef _SendFrameGradingC = Int32 Function(
  Pointer<Uint8> rawBgra,
  Int32 bufferSize,
  Float brightness,
  Float contrast,
  Float saturation,
  Float warmth,
  Float tint,
  Int32 flipH,
  Int32 flipV,
  Int32 rotation,
);

typedef _SendFrameGradingDart = int Function(
  Pointer<Uint8> rawBgra,
  int bufferSize,
  double brightness,
  double contrast,
  double saturation,
  double warmth,
  double tint,
  int flipH,
  int flipV,
  int rotation,
);

typedef _RegisterFilterC = Int32 Function(Pointer<Utf16> friendlyName);
typedef _RegisterFilterDart = int Function(Pointer<Utf16> friendlyName);

typedef _UnregisterFilterC = Int32 Function();
typedef _UnregisterFilterDart = int Function();

typedef _CloseCamC = Void Function();
typedef _CloseCamDart = void Function();

class VirtualCameraBridge {
  DynamicLibrary? _dylib;
  _InitCamDart? _initCam;
  _SendFrameGradingDart? _sendFrameGrading;
  _RegisterFilterDart? _registerFilter;
  _UnregisterFilterDart? _unregisterFilter;
  _CloseCamDart? _closeCam;

  bool _isInitialized = false;
  bool get isDriverLoaded => _dylib != null;

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
        _sendFrameGrading = _dylib!.lookupFunction<_SendFrameGradingC, _SendFrameGradingDart>('SendFrameWithGrading');
        _registerFilter = _dylib!.lookupFunction<_RegisterFilterC, _RegisterFilterDart>('RegisterVirtualCameraFilter');
        _unregisterFilter = _dylib!.lookupFunction<_UnregisterFilterC, _UnregisterFilterDart>('UnregisterVirtualCameraFilter');
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

  int sendFrame(Pointer<Uint8> bgraPointer, int size, GradingSettings settings) {
    if (_sendFrameGrading != null && _isInitialized) {
      return _sendFrameGrading!(
        bgraPointer,
        size,
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
    return -1;
  }

  bool registerSystemWebcam(String friendlyName) {
    if (_registerFilter != null) {
      final namePtr = friendlyName.toNativeUtf16();
      final res = _registerFilter!(namePtr);
      calloc.free(namePtr);
      return res == 0;
    }
    return false;
  }

  bool unregisterSystemWebcam() {
    if (_unregisterFilter != null) {
      return _unregisterFilter!() == 0;
    }
    return false;
  }

  void close() {
    _closeCam?.call();
    _isInitialized = false;
  }
}
