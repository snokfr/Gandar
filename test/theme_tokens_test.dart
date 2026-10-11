import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/theme/theme_codec.dart';
import 'package:gandar/core/theme/theme_presets.dart';
import 'package:gandar/core/theme/theme_tokens.dart';

void main() {
  const tokens = ThemePresets.spotifyClassic;

  group('colour keys', () {
    test('every key the editor shows is readable and writable', () {
      for (final key in ThemeTokens.colorKeys) {
        expect(tokens.colorFor(key), isNotNull, reason: 'reading $key');
        // The round-trip is what the editor does on every pick: read the
        // current value, replace it, expect the new value back.
        final changed = tokens.withColor(key, 0xFF123456);
        expect(changed.colorFor(key), const Color(0xFF123456), reason: key);
      }
    });

    test('replacing one colour leaves the others alone', () {
      final changed = tokens.withColor('accent', 0xFFABCDEF);

      expect(changed.accent, 0xFFABCDEF);
      expect(changed.backgroundPrimary, tokens.backgroundPrimary);
      expect(changed.textPrimary, tokens.textPrimary);
      expect(changed.radiusMd, tokens.radiusMd);
    });

    test('an unknown key changes nothing rather than corrupting the theme', () {
      expect(tokens.withColor('notAKey', 0xFF000000), tokens);
      expect(tokens.colorFor('notAKey'), isNull);
    });

    test('the key list matches what the codec requires', () {
      // If these ever drift, a theme saved by the editor fails to load.
      final encoded = ThemeCodec.toMap(tokens);
      final colors = encoded['colors'] as Map<String, dynamic>;
      expect(colors.keys.toSet(), ThemeTokens.colorKeys.toSet());
    });

    test('every key has a label that is not the raw key', () {
      for (final key in ThemeTokens.colorKeys) {
        expect(ThemeTokens.labelFor(key), isNot(key));
      }
    });
  });

  group('built-in detection', () {
    test('the shipped presets are built in', () {
      for (final preset in ThemePresets.all) {
        expect(preset.isBuiltIn, isTrue, reason: preset.id);
      }
    });

    test('an edited copy and a saved theme are not', () {
      expect(tokens.copyWith(id: 'spotify_classic_custom').isBuiltIn, isFalse);
      expect(tokens.copyWith(id: 'theme-1234').isBuiltIn, isFalse);
    });
  });

  group('accent legibility', () {
    test('a very dark accent is lightened on a dark theme', () {
      final dark = tokens.copyWith(accent: 0xFF050505);
      expect(
        dark.onSurfaceAccent.computeLuminance(),
        greaterThan(Color(0xFF050505).computeLuminance()),
      );
    });

    test('a very light accent is darkened on a light theme', () {
      final light = tokens.copyWith(
        brightness: Brightness.light,
        accent: 0xFFFEFEFE,
      );
      expect(
        light.onSurfaceAccent.computeLuminance(),
        lessThan(Color(0xFFFEFEFE).computeLuminance()),
      );
    });

    test('an ordinary accent is left as it is', () {
      expect(tokens.onSurfaceAccent, tokens.accentColor);
    });
  });
}
