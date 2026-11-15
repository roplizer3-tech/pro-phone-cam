import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/camera_info.dart';

class NativeCameraBridge {
  static const MethodChannel _methodChannel = MethodChannel('com.prophone.cam/methods');
  static const EventChannel _eventChannel = EventChannel('com.prophone.cam/events');

  Stream<dynamic> get eventStream => _eventChannel.receiveBroadcastStream();

  Future<bool> startServer() async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('startServer');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopServer() async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('stopServer');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<PhysicalCamera>> getCameras() async {
    try {
      final String? jsonStr = await _methodChannel.invokeMethod<String>('getCameras');
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final List<dynamic> list = data['cameras'] as List<dynamic>? ?? [];
      return list.map((e) => PhysicalCamera.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> switchCamera(String cameraId) async {
    await _methodChannel.invokeMethod('switchCamera', {'cameraId': cameraId});
  }

  Future<void> setZoom(double zoom) async {
    await _methodChannel.invokeMethod('setZoom', {'zoom': zoom});
  }

  Future<void> setFocus(String mode, double distance) async {
    await _methodChannel.invokeMethod('setFocus', {
      'mode': mode,
      'distance': distance,
    });
  }

  Future<void> setExposure(int ev) async {
    await _methodChannel.invokeMethod('setExposure', {'ev': ev});
  }

  Future<void> setWhiteBalance(String mode) async {
    await _methodChannel.invokeMethod('setWhiteBalance', {'mode': mode});
  }

  Future<void> setTorch(bool enabled) async {
    await _methodChannel.invokeMethod('setTorch', {'enabled': enabled});
  }

  Future<void> setBlackScreenMode(bool enabled) async {
    await _methodChannel.invokeMethod('setBlackScreenMode', {'enabled': enabled});
  }
}
