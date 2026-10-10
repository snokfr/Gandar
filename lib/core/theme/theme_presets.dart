import 'theme_tokens.dart';

/// The themes Gandar ships with. Custom themes are loaded on top of these.
class ThemePresets {
  const ThemePresets._();

  /// Classic Spotify dark theme with signature green accents.
  static const ThemeTokens spotifyClassic = ThemeTokens(
    id: 'spotify_classic',
    name: 'Spotify Classic',
    backgroundPrimary: 0xFF121212,
    backgroundSecondary: 0xFF181818,
    surface: 0xFF181818,
    surfaceElevated: 0xFF282828,
    textPrimary: 0xFFFFFFFF,
    textSecondary: 0xFFB3B3B3,
    accent: 0xFF1DB954,
    accentAlt: 0xFF1ED760,
    border: 0xFF2A2A2A,
    radiusSm: 4,
    radiusMd: 8,
    radiusLg: 16,
  );

  /// Earthy brown theme: warm charcoal/black bases, espresso, mahogany and
  /// amber accents.
  static const ThemeTokens earthyBrown = ThemeTokens(
    id: 'earthy_brown',
    name: 'Earthy Brown',
    backgroundPrimary: 0xFF15100D,
    backgroundSecondary: 0xFF1E1611,
    surface: 0xFF241A14,
    surfaceElevated: 0xFF33241B,
    textPrimary: 0xFFF3E9DE,
    textSecondary: 0xFFB9A38E,
    accent: 0xFFC8763C,
    accentAlt: 0xFF8C4A2F,
    border: 0xFF3C2C21,
    radiusSm: 6,
    radiusMd: 12,
    radiusLg: 20,
  );

  static const List<ThemeTokens> all = <ThemeTokens>[
    spotifyClassic,
    earthyBrown,
  ];

  /// The theme used on a fresh install.
  static ThemeTokens get defaultTheme => spotifyClassic;

  static ThemeTokens? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
