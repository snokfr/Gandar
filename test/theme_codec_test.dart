import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/theme/theme_codec.dart';
import 'package:gandar/core/theme/theme_engine.dart';
import 'package:gandar/core/theme/theme_presets.dart';
import 'package:gandar/core/theme/theme_tokens.dart';

void main() {
  group('ThemePresets', () {
    test('ships the two required built-in themes', () {
      expect(ThemePresets.all.length, 2);
      expect(ThemePresets.spotifyClassic.accent, 0xFF1DB954);
      expect(ThemePresets.spotifyClassic.name, 'Spotify Classic');
      expect(ThemePresets.earthyBrown.name, 'Earthy Brown');
      // Earthy theme is warm (red channel dominant over blue) and dark.
      const earthy = ThemePresets.earthyBrown;
      final bg = earthy.backgroundPrimaryColor;
      expect(bg.r, greaterThan(bg.b));
      expect(bg.g, greaterThan(bg.b), reason: 'warm brown, not neutral grey');
      expect(earthy.brightness, Brightness.dark);
    });

    test('lookup by id works and is null-safe', () {
      expect(ThemePresets.byId('spotify_classic'), ThemePresets.spotifyClassic);
      expect(ThemePresets.byId('nope'), isNull);
    });
  });

  group('ThemeCodec JSON', () {
    test('round-trips every preset without loss', () {
      for (final preset in ThemePresets.all) {
        final decoded = ThemeCodec.decode(ThemeCodec.toJson(preset));
        expect(decoded, preset, reason: 'preset ${preset.id} must round-trip');
      }
    });

    test('emits the documented shape', () {
      final map = ThemeCodec.toMap(ThemePresets.spotifyClassic);
      expect(map['format'], 'gandar.theme');
      expect(map['version'], 1);
      expect(map['brightness'], 'dark');
      expect((map['colors'] as Map<String, dynamic>)['accent'], '#1DB954');
      expect(map['radius'], isA<Map<String, dynamic>>());
    });

    test('accepts 6-digit hex, 8-digit hex, ints and bare hex', () {
      final tokens = ThemeCodec.decode(
        jsonEncode({
          'format': 'gandar.theme',
          'id': 'x',
          'name': 'X',
          'colors': {
            'backgroundPrimary': '#121212',
            'backgroundSecondary': 'FF181818',
            'surface': 0xFF181818,
            'surfaceElevated': '#FF282828',
            'textPrimary': '#FFFFFF',
            'textSecondary': '#B3B3B3',
            'accent': '#1DB954',
            'accentAlt': '#1ED760',
            'border': '#2A2A2A',
          },
        }),
      );
      expect(tokens.backgroundPrimary, 0xFF121212);
      expect(tokens.backgroundSecondary, 0xFF181818);
      expect(tokens.surface, 0xFF181818);
    });

    test('reports missing colors clearly', () {
      expect(
        () => ThemeCodec.decode(
          jsonEncode({
            'colors': {'accent': '#1DB954'},
          }),
        ),
        throwsA(isA<ThemeFormatException>()),
      );
    });

    test('rejects bad hex and unknown formats', () {
      expect(
        () => ThemeCodec.fromMap({
          'format': 'someone-else',
          'colors': const <String, dynamic>{},
        }),
        throwsA(isA<ThemeFormatException>()),
      );
      expect(
        () => ThemeCodec.fromMap({
          'colors': {
            'backgroundPrimary': '#12',
            'backgroundSecondary': '#181818',
            'surface': '#181818',
            'surfaceElevated': '#282828',
            'textPrimary': '#FFFFFF',
            'textSecondary': '#B3B3B3',
            'accent': '#1DB954',
            'accentAlt': '#1ED760',
            'border': '#2A2A2A',
          },
        }),
        throwsA(isA<ThemeFormatException>()),
      );
    });

    test('rejects an empty file', () {
      expect(
        () => ThemeCodec.decode('   '),
        throwsA(isA<ThemeFormatException>()),
      );
    });
  });

  group('ThemeCodec YAML', () {
    test('YAML export decodes back to the same theme', () {
      final yaml = ThemeCodec.toYaml(ThemePresets.earthyBrown);
      final decoded = ThemeCodec.decode(yaml);
      expect(decoded, ThemePresets.earthyBrown);
    });

    test('decodes a hand-written YAML theme', () {
      const source = '''
format: gandar.theme
version: 1
id: handwritten
name: Handwritten
brightness: dark
colors:
  backgroundPrimary: "#101010"
  backgroundSecondary: "#181818"
  surface: "#202020"
  surfaceElevated: "#2A2A2A"
  textPrimary: "#F5F5F5"
  textSecondary: "#AAAAAA"
  accent: "#00AAFF"
  accentAlt: "#0088CC"
  border: "#333333"
radius:
  sm: 4
  md: 10
  lg: 18
''';
      final tokens = ThemeCodec.decode(source);
      expect(tokens.id, 'handwritten');
      expect(tokens.accent, 0xFF00AAFF);
      expect(tokens.radiusMd, 10);
    });
  });

  group('ThemeEngine', () {
    testWidgets('builds a dark Material 3 theme wired to the tokens', (
      tester,
    ) async {
      final data = ThemeEngine.build(ThemePresets.earthyBrown);
      expect(data.useMaterial3, isTrue);
      expect(data.brightness, Brightness.dark);
      expect(
        data.scaffoldBackgroundColor,
        ThemePresets.earthyBrown.backgroundPrimaryColor,
      );
      expect(data.colorScheme.primary, ThemePresets.earthyBrown.accentColor);
      expect(data.extension<GandarTokens>()?.tokens, ThemePresets.earthyBrown);
    });

    test('onSurfaceAccent lifts accents that would be invisible', () {
      const nearlyBlack = ThemeTokens(
        id: 'x',
        name: 'x',
        backgroundPrimary: 0xFF000000,
        backgroundSecondary: 0xFF000000,
        surface: 0xFF000000,
        surfaceElevated: 0xFF000000,
        textPrimary: 0xFFFFFFFF,
        textSecondary: 0xFF999999,
        accent: 0xFF050505,
        accentAlt: 0xFF050505,
        border: 0xFF111111,
      );
      expect(
        nearlyBlack.onSurfaceAccent.computeLuminance(),
        greaterThan(nearlyBlack.accentColor.computeLuminance()),
      );
    });
  });
}
