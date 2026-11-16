import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/grading_settings.dart';

class PreviewPanel extends StatelessWidget {
  final Uint8List? frameBytes;
  final GradingSettings grading;
  final double currentFps;
  final double currentMbps;
  final int batteryLevel;
  final bool isPhoneConnected;
  final bool isOledBlackScreenActive;

  const PreviewPanel({
    super.key,
    required this.frameBytes,
    required this.grading,
    required this.currentFps,
    required this.currentMbps,
    required this.batteryLevel,
    required this.isPhoneConnected,
    required this.isOledBlackScreenActive,
  });

  ColorFilter _buildColorFilter(GradingSettings g) {
    final double b = g.brightness * 1.5;
    final double c = g.contrast;
    final double s = g.saturation;
    final double w = g.warmth * 1.2;
    final double t = g.tint * 1.2;

    const double lr = 0.2126;
    const double lg = 0.7152;
    const double lb = 0.0722;

    final double invS = 1.0 - s;
    final double rR = (invS * lr + s) * c;
    final double rG = (invS * lg) * c;
    final double rB = (invS * lb) * c;

    final double gR = (invS * lr) * c;
    final double gG = (invS * lg + s) * c;
    final double gB = (invS * lb) * c;

    final double bR = (invS * lr) * c;
    final double bG = (invS * lg) * c;
    final double bB = (invS * lb + s) * c;

    final double offR = b + w + (128.0 * (1.0 - c));
    final double offG = b + t + (128.0 * (1.0 - c));
    final double offB = b - w + (128.0 * (1.0 - c));

    return ColorFilter.matrix([
      rR, rG, rB, 0, offR,
      gR, gG, gB, 0, offG,
      bR, bG, bB, 0, offB,
      0,  0,  0,  1, 0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF090B10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232838), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (frameBytes != null && isPhoneConnected)
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(grading.flipHorizontal ? -1.0 : 1.0, grading.flipVertical ? -1.0 : 1.0)
                ..rotateZ(grading.rotation * (math.pi / 180.0)),
              child: ColorFiltered(
                colorFilter: _buildColorFilter(grading),
                child: Image.memory(
                  frameBytes!,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
                ),
              ),
            )
          else
            _buildNoSignalPlaceholder(),

          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLiveBadge(),
                Row(
                  children: [
                    if (grading.flipHorizontal) _buildAntiMirrorActiveBadge(),
                    const SizedBox(width: 8),
                    _buildBatteryBadge(),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildResolutionFpsBadge(),
                if (isOledBlackScreenActive) _buildOledIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSignalPlaceholder() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.usb_rounded,
          size: 64,
          color: isPhoneConnected ? const Color(0xFF10B981) : Colors.white24,
        ),
        const SizedBox(height: 16),
        Text(
          isPhoneConnected
              ? 'Connected to Phone! Initializing 1080p Stream...'
              : 'Waiting for Phone USB Connection...',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Text(
          isPhoneConnected
              ? 'Opening Camera2 ISP hardware pipeline'
              : 'Connect phone via USB cable with USB Debugging enabled',
          style: const TextStyle(fontSize: 12, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isPhoneConnected ? Colors.redAccent.withOpacity(0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPhoneConnected ? Colors.redAccent : Colors.white24,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPhoneConnected ? Colors.redAccent : Colors.grey,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isPhoneConnected ? 'LIVE FEED' : 'STANDBY',
            style: TextStyle(
              color: isPhoneConnected ? Colors.redAccent : Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAntiMirrorActiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF6366F1), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.flip_rounded, size: 14, color: Color(0xFF818CF8)),
          SizedBox(width: 6),
          Text(
            'True-View (Anti-Mirror Active)',
            style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2D3345)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            batteryLevel > 20 ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded,
            size: 16,
            color: batteryLevel > 20 ? const Color(0xFF10B981) : Colors.amber,
          ),
          const SizedBox(width: 6),
          Text(
            '$batteryLevel%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionFpsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        '1920x1080  |  ${currentFps.toStringAsFixed(1)} FPS  |  ${currentMbps.toStringAsFixed(2)} Mbps',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildOledIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.nights_stay_rounded, size: 14, color: Color(0xFF10B981)),
          SizedBox(width: 6),
          Text(
            'Phone OLED Cold Screen Active',
            style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
