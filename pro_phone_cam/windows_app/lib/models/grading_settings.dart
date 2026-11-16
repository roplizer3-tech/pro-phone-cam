class GradingSettings {
  double brightness;    // -100 to +100 (0 default)
  double contrast;      // 0.5 to 2.0 (1.0 default)
  double saturation;    // 0.0 to 2.0 (1.0 default)
  double warmth;        // -50 to +50 (0 default)
  double tint;          // -50 to +50 (0 default)
  double sharpness;     // 0.0 to 5.0 (0 default)

  bool flipHorizontal;  // True-View Anti-Mirror for WhatsApp / Telegram
  bool flipVertical;    // Upside down mounting
  int rotation;         // 0, 90, 180, 270 degrees

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

  void reset() {
    brightness = 0.0;
    contrast = 1.0;
    saturation = 1.0;
    warmth = 0.0;
    tint = 0.0;
    sharpness = 0.0;
    flipHorizontal = false;
    flipVertical = false;
    rotation = 0;
  }
}
