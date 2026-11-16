class GradingSettings {
  final double brightness;    // -100 to +100 (0 default)
  final double contrast;      // 0.5 to 2.0 (1.0 default)
  final double saturation;    // 0.0 to 2.0 (1.0 default)
  final double warmth;        // -50 to +50 (0 default)
  final double tint;          // -50 to +50 (0 default)
  final double sharpness;     // 0.0 to 5.0 (0 default)

  final bool flipHorizontal;  // True-View Anti-Mirror for WhatsApp / Telegram
  final bool flipVertical;    // Upside down mounting
  final int rotation;         // 0, 90, 180, 270 degrees

  const GradingSettings({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.warmth = 0.0,
    this.tint = 0.0,
    this.sharpness = 0.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.rotation = 0,
  });

  static final Map<String, GradingSettings> defaultPresets = {
    'Default Natural': const GradingSettings(
      brightness: 0.0,
      contrast: 1.0,
      saturation: 1.0,
      warmth: 0.0,
      tint: 0.0,
      sharpness: 0.0,
    ),
    'Studio Warm': const GradingSettings(
      brightness: 5.0,
      contrast: 1.1,
      saturation: 1.15,
      warmth: 12.0,
      tint: -2.0,
      sharpness: 0.5,
    ),
    'Cool Daylight': const GradingSettings(
      brightness: 2.0,
      contrast: 1.05,
      saturation: 0.95,
      warmth: -15.0,
      tint: 4.0,
      sharpness: 0.3,
    ),
    'High Contrast': const GradingSettings(
      brightness: 0.0,
      contrast: 1.35,
      saturation: 1.2,
      warmth: 2.0,
      tint: 0.0,
      sharpness: 1.0,
    ),
  };

  GradingSettings copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? tint,
    double? sharpness,
    bool? flipHorizontal,
    bool? flipVertical,
    int? rotation,
  }) {
    return GradingSettings(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      warmth: warmth ?? this.warmth,
      tint: tint ?? this.tint,
      sharpness: sharpness ?? this.sharpness,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'warmth': warmth,
      'tint': tint,
      'sharpness': sharpness,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'rotation': rotation,
    };
  }

  factory GradingSettings.fromJson(Map<String, dynamic> json) {
    return GradingSettings(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
      warmth: (json['warmth'] as num?)?.toDouble() ?? 0.0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0.0,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      rotation: json['rotation'] as int? ?? 0,
    );
  }
}
