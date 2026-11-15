class PhysicalCamera {
  final String id;
  final String facing;
  final String label;
  final double focalLengthMm;
  final double zoomMin;
  final double zoomMax;
  final bool supports60fps;
  final bool hasFlash;

  const PhysicalCamera({
    required this.id,
    required this.facing,
    required this.label,
    required this.focalLengthMm,
    required this.zoomMin,
    required this.zoomMax,
    required this.supports60fps,
    required this.hasFlash,
  });

  factory PhysicalCamera.fromJson(Map<String, dynamic> json) {
    return PhysicalCamera(
      id: json['id'] as String,
      facing: json['facing'] as String,
      label: json['label'] as String,
      focalLengthMm: (json['focal_length_mm'] as num).toDouble(),
      zoomMin: (json['zoom_min'] as num).toDouble(),
      zoomMax: (json['zoom_max'] as num).toDouble(),
      supports60fps: json['supports_60fps'] as bool,
      hasFlash: json['has_flash'] as bool,
    );
  }
}
