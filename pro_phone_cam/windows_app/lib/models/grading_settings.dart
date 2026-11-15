import 'dart:convert';

class GradingSettings {
  double brightness;
  double contrast;
  double saturation;
  double warmth;
  double tint;
  double sharpness;
  bool flipHorizontal;
  bool flipVertical;
  int rotation;

  GradingSettings({
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

  Map<String, dynamic> toJson() => {
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

  factory GradingSettings.fromJson(Map<String, dynamic> json) => GradingSettings(
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

  static Map<String, GradingSettings> defaultPresets = {
    'Default Natural': GradingSettings(),
    'Studio Warm': GradingSettings(brightness: 5.0, contrast: 1.1, saturation: 1.15, warmth: 12.0),
    'Cool Clean': GradingSettings(brightness: 3.0, contrast: 1.05, saturation: 0.95, warmth: -10.0),
    'Vibrant Streamer': GradingSettings(brightness: 8.0, contrast: 1.2, saturation: 1.35, sharpness: 1.2),
  };
}
