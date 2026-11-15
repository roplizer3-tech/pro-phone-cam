class CameraModel {
  final String id;
  final String facing;
  final String label;
  final double focalLengthMm;
  final double zoomMin;
  final double zoomMax;
  final bool supports60fps;
  final bool hasFlash;

  const CameraModel({
    required this.id,
    required this.facing,
    required this.label,
    required this.focalLengthMm,
    required this.zoomMin,
    required this.zoomMax,
    required this.supports60fps,
    required this.hasFlash,
  });

  factory CameraModel.fromJson(Map<String, dynamic> json) {
    return CameraModel(
      id: json['id']?.toString() ?? '0',
      facing: json['facing']?.toString() ?? 'back',
      label: json['label']?.toString() ?? 'Camera',
      focalLengthMm: (json['focal_length_mm'] as num?)?.toDouble() ?? 4.0,
      zoomMin: (json['zoom_min'] as num?)?.toDouble() ?? 1.0,
      zoomMax: (json['zoom_max'] as num?)?.toDouble() ?? 10.0,
      supports60fps: json['supports_60fps'] as bool? ?? true,
      hasFlash: json['has_flash'] as bool? ?? false,
    );
  }
}
