import 'package:flutter/material.dart';

/// A serializable, user-customizable design token set that fully describes
/// Gandar's visual theme (colors + shape scale).
///
/// Colors are stored as ARGB ints so they round-trip losslessly through
/// JSON/YAML. Use [ThemeCodec] to import/export.
@immutable
class ThemeTokens {
  const ThemeTokens({
    required this.id,
    required this.name,
    this.brightness = Brightness.dark,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentAlt,
    required this.border,
    this.radiusSm = 6,
    this.radiusMd = 12,
    this.radiusLg = 20,
  });

  /// Stable, machine-readable identifier (e.g. `spotify_classic`).
  final String id;

  /// Human-readable label shown in the theme picker.
  final String name;

  final Brightness brightness;

  final int backgroundPrimary;
  final int backgroundSecondary;
  final int surface;
  final int surfaceElevated;
  final int textPrimary;
  final int textSecondary;
  final int accent;
  final int accentAlt;
  final int border;

  final double radiusSm;
  final double radiusMd;
  final double radiusLg;

  Color get backgroundPrimaryColor => Color(backgroundPrimary);
  Color get backgroundSecondaryColor => Color(backgroundSecondary);
  Color get surfaceColor => Color(surface);
  Color get surfaceElevatedColor => Color(surfaceElevated);
  Color get textPrimaryColor => Color(textPrimary);
  Color get textSecondaryColor => Color(textSecondary);
  Color get accentColor => Color(accent);
  Color get accentAltColor => Color(accentAlt);
  Color get borderColor => Color(border);

  /// Accent adjusted to be legible as a foreground on [surface].
  ///
  /// On dark surfaces we lighten a very dark accent; on light surfaces we
  /// darken a very light accent. This keeps imported third-party themes usable
  /// instead of producing invisible text.
  Color get onSurfaceAccent {
    final c = accentColor;
    final lum = c.computeLuminance();
    final hsl = HSLColor.fromColor(c);
    if (brightness == Brightness.dark && lum < 0.12) {
      return hsl
          .withLightness((hsl.lightness + 0.35).clamp(0.0, 1.0).toDouble())
          .toColor();
    }
    if (brightness == Brightness.light && lum > 0.75) {
      return hsl
          .withLightness((hsl.lightness - 0.35).clamp(0.0, 1.0).toDouble())
          .toColor();
    }
    return c;
  }

  ThemeTokens copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    int? backgroundPrimary,
    int? backgroundSecondary,
    int? surface,
    int? surfaceElevated,
    int? textPrimary,
    int? textSecondary,
    int? accent,
    int? accentAlt,
    int? border,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
  }) {
    return ThemeTokens(
      id: id ?? this.id,
      name: name ?? this.name,
      brightness: brightness ?? this.brightness,
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      accentAlt: accentAlt ?? this.accentAlt,
      border: border ?? this.border,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeTokens &&
          other.id == id &&
          other.name == name &&
          other.brightness == brightness &&
          other.backgroundPrimary == backgroundPrimary &&
          other.backgroundSecondary == backgroundSecondary &&
          other.surface == surface &&
          other.surfaceElevated == surfaceElevated &&
          other.textPrimary == textPrimary &&
          other.textSecondary == textSecondary &&
          other.accent == accent &&
          other.accentAlt == accentAlt &&
          other.border == border &&
          other.radiusSm == radiusSm &&
          other.radiusMd == radiusMd &&
          other.radiusLg == radiusLg;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    brightness,
    backgroundPrimary,
    backgroundSecondary,
    surface,
    surfaceElevated,
    textPrimary,
    textSecondary,
    accent,
    accentAlt,
    border,
    radiusSm,
    radiusMd,
    radiusLg,
  );
}
