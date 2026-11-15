import 'package:flutter/material.dart';
import '../models/camera_info.dart';
import '../models/grading_settings.dart';

class StudioControls extends StatelessWidget {
  final GradingSettings grading;
  final Function(GradingSettings newSettings) onGradingChanged;
  final List<CameraModel> cameras;
  final String selectedCameraId;
  final Function(String id) onSwitchCamera;
  final double currentZoom;
  final Function(double zoom) onZoomChanged;
  final bool isAutoFocus;
  final double manualFocusDistance;
  final Function(bool isAuto, double distance) onFocusChanged;
  final int exposureEv;
  final Function(int ev) onExposureChanged;
  final String whiteBalance;
  final Function(String wb) onWhiteBalanceChanged;
  final bool isTorchOn;
  final VoidCallback onToggleTorch;
  final bool isOledBlackScreen;
  final VoidCallback onToggleOledBlackScreen;

  const StudioControls({
    super.key,
    required this.grading,
    required this.onGradingChanged,
    required this.cameras,
    required this.selectedCameraId,
    required this.onSwitchCamera,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.isAutoFocus,
    required this.manualFocusDistance,
    required this.onFocusChanged,
    required this.exposureEv,
    required this.onExposureChanged,
    required this.whiteBalance,
    required this.onWhiteBalanceChanged,
    required this.isTorchOn,
    required this.onToggleTorch,
    required this.isOledBlackScreen,
    required this.onToggleOledBlackScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232838)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _buildAntiMirrorSection(),
          const Divider(color: Color(0xFF232838), height: 32),
          _buildColorGradingSection(),
          const Divider(color: Color(0xFF232838), height: 32),
          _buildHardwareCameraSection(),
        ],
      ),
    );
  }

  Widget _buildAntiMirrorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.flip_camera_android_rounded, size: 18, color: Color(0xFF818CF8)),
                SizedBox(width: 8),
                Text(
                  'True-View (Anti-Mirror)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.grey),
              tooltip: 'Reset Orientation',
              onPressed: () {
                onGradingChanged(grading.copyWith(flipHorizontal: false, flipVertical: false, rotation: 0));
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Eliminates WhatsApp & Telegram mirror preview issues by flipping raw pixels directly before entering the virtual camera.',
          style: TextStyle(fontSize: 11, color: Colors.white54, height: 1.3),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: grading.flipHorizontal ? const Color(0xFF6366F1) : const Color(0xFF1E222D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  onGradingChanged(grading.copyWith(flipHorizontal: !grading.flipHorizontal));
                },
                icon: const Icon(Icons.flip_rounded, size: 16),
                label: const Text('Flip Horizontal', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: grading.flipVertical ? const Color(0xFF6366F1) : const Color(0xFF1E222D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  onGradingChanged(grading.copyWith(flipVertical: !grading.flipVertical));
                },
                icon: const Icon(Icons.swap_vert_rounded, size: 16),
                label: const Text('Flip Vertical', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Rotation:', style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(width: 10),
            Expanded(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('0°')),
                  ButtonSegment(value: 90, label: Text('90°')),
                  ButtonSegment(value: 180, label: Text('180°')),
                  ButtonSegment(value: 270, label: Text('270°')),
                ],
                selected: {grading.rotation},
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (set) {
                  onGradingChanged(grading.copyWith(rotation: set.first));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorGradingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.palette_rounded, size: 18, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text(
                  'Color Grading Studio',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
              ],
            ),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () {
                onGradingChanged(GradingSettings.defaultPresets['Default Natural']!.copyWith(
                  flipHorizontal: grading.flipHorizontal,
                  flipVertical: grading.flipVertical,
                  rotation: grading.rotation,
                ));
              },
              child: const Text('Reset', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          children: GradingSettings.defaultPresets.entries.map((preset) {
            return ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(preset.key, style: const TextStyle(fontSize: 11)),
              backgroundColor: const Color(0xFF1E222D),
              onPressed: () {
                onGradingChanged(preset.value.copyWith(
                  flipHorizontal: grading.flipHorizontal,
                  flipVertical: grading.flipVertical,
                  rotation: grading.rotation,
                ));
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        _buildSliderRow('Brightness', grading.brightness, -50.0, 50.0, (val) => onGradingChanged(grading.copyWith(brightness: val))),
        _buildSliderRow('Contrast', grading.contrast, 0.6, 1.6, (val) => onGradingChanged(grading.copyWith(contrast: val))),
        _buildSliderRow('Saturation', grading.saturation, 0.0, 2.0, (val) => onGradingChanged(grading.copyWith(saturation: val))),
        _buildSliderRow('Warmth', grading.warmth, -40.0, 40.0, (val) => onGradingChanged(grading.copyWith(warmth: val))),
        _buildSliderRow('Tint', grading.tint, -30.0, 30.0, (val) => onGradingChanged(grading.copyWith(tint: val))),
      ],
    );
  }

  Widget _buildSliderRow(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text(val.toStringAsFixed(1), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: const Color(0xFF6366F1),
            thumbColor: const Color(0xFF818CF8),
            inactiveTrackColor: const Color(0xFF232838),
          ),
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildHardwareCameraSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.tune_rounded, size: 18, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text(
              'Hardware Lens & Controls',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Physical Camera Lens:', style: TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: cameras.map((cam) {
            final isSel = cam.id == selectedCameraId;
            return ChoiceChip(
              selected: isSel,
              label: Text(cam.label, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.white70)),
              selectedColor: const Color(0xFFF59E0B),
              backgroundColor: const Color(0xFF1E222D),
              onSelected: (_) => onSwitchCamera(cam.id),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Smooth Linear Zoom:', style: TextStyle(fontSize: 12, color: Colors.white70)),
            Text('${currentZoom.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
          ],
        ),
        Slider(
          value: currentZoom.clamp(1.0, 8.0),
          min: 1.0,
          max: 8.0,
          activeColor: const Color(0xFFF59E0B),
          onChanged: onZoomChanged,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Focus Mode:', style: TextStyle(fontSize: 12, color: Colors.white70)),
            Switch(
              value: isAutoFocus,
              activeColor: const Color(0xFF10B981),
              onChanged: (val) => onFocusChanged(val, manualFocusDistance),
            ),
          ],
        ),
        if (!isAutoFocus) ...[
          const Text('Manual Focus Lock Distance:', style: TextStyle(fontSize: 11, color: Colors.grey)),
          Slider(
            value: manualFocusDistance.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            activeColor: const Color(0xFF10B981),
            onChanged: (val) => onFocusChanged(false, val),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isTorchOn ? Colors.amber : Colors.white70,
                  side: BorderSide(color: isTorchOn ? Colors.amber : const Color(0xFF2D3345)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: onToggleTorch,
                icon: Icon(isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, size: 16),
                label: const Text('Flash LED', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isOledBlackScreen ? const Color(0xFF10B981) : Colors.white70,
                  side: BorderSide(color: isOledBlackScreen ? const Color(0xFF10B981) : const Color(0xFF2D3345)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: onToggleOledBlackScreen,
                icon: const Icon(Icons.nights_stay_rounded, size: 16),
                label: const Text('OLED Cold', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
