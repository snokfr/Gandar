import 'dart:io';

import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/theme/theme_codec.dart';
import 'package:gandar/core/theme/theme_presets.dart';

/// Keeps the documentation honest.
///
/// `docs/styling.md` is the guide for authoring custom theme files, and it
/// points readers at concrete files in `examples/themes/`. If those files stop
/// decoding, or a documented filename disappears, the docs are lying — so the
/// examples are verified here with the shipped codec.
void main() {
  const examplesDir = 'examples/themes';

  /// The three files named explicitly by docs/styling.md §6.
  const documentedFileNames = <String>[
    'midnight_amber.gandar-theme.yaml',
    'paper_light.gandar-theme.json',
    'forest_deep.gandar-theme.yaml',
  ];

  List<File> exampleFiles() {
    final dir = Directory(examplesDir);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => !f.uri.pathSegments.last.startsWith('.'))
        .toList();
  }

  test('the documented example files all ship', () {
    final names = exampleFiles().map((f) => f.uri.pathSegments.last).toSet();
    expect(
      names,
      isNotEmpty,
      reason: '$examplesDir should ship example themes',
    );

    for (final name in documentedFileNames) {
      expect(
        names,
        contains(name),
        reason: 'docs/styling.md §6 links to $examplesDir/$name',
      );
    }
  });

  test('every shipped example decodes, round-trips and is a valid theme', () {
    final files = exampleFiles();
    expect(files, hasLength(greaterThanOrEqualTo(documentedFileNames.length)));

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final tokens = ThemeCodec.decode(file.readAsStringSync());

      // Documented required shape (docs/styling.md §3).
      expect(tokens.id, isNotEmpty, reason: '$name: id');
      expect(
        tokens.id,
        matches(RegExp(r'^[a-z0-9_]+$')),
        reason: '$name: id should be lowercase words joined by underscores',
      );
      expect(tokens.name, isNotEmpty, reason: '$name: name');

      // Round trips must be lossless in both formats (§3).
      expect(
        ThemeCodec.decode(ThemeCodec.toJson(tokens)),
        tokens,
        reason: '$name: JSON round trip',
      );
      expect(
        ThemeCodec.decode(ThemeCodec.toYaml(tokens)),
        tokens,
        reason: '$name: YAML round trip',
      );

      // 6-digit hex must be treated as opaque (§4).
      for (final value in [
        tokens.backgroundPrimary,
        tokens.backgroundSecondary,
        tokens.surface,
        tokens.surfaceElevated,
        tokens.textPrimary,
        tokens.textSecondary,
        tokens.accent,
        tokens.accentAlt,
        tokens.border,
      ]) {
        expect(
          (value >> 24) & 0xFF,
          0xFF,
          reason: '$name: every colour must be opaque to be used as a surface',
        );
      }

      // A sensible, monotonically growing radius scale (§3).
      expect(tokens.radiusSm, greaterThan(0), reason: '$name: radius.sm');
      expect(
        tokens.radiusMd,
        greaterThanOrEqualTo(tokens.radiusSm),
        reason: '$name: radius scale should grow',
      );
      expect(
        tokens.radiusLg,
        greaterThanOrEqualTo(tokens.radiusMd),
        reason: '$name: radius scale should grow',
      );

      // Never shadow a built-in id (§3, §9).
      expect(
        ThemePresets.byId(tokens.id),
        isNull,
        reason: '$name: id "${tokens.id}" collides with a built-in theme',
      );
    }
  });

  test('example ids are unique', () {
    final ids = exampleFiles().map(
      (f) => ThemeCodec.decode(f.readAsStringSync()).id,
    );
    final list = ids.toList();
    expect(list.toSet().length, list.length, reason: 'duplicate theme ids');
  });

  test('dark examples keep surfaceElevated lighter than surface (depth)', () {
    var darkChecked = 0;
    for (final file in exampleFiles()) {
      final tokens = ThemeCodec.decode(file.readAsStringSync());
      if (tokens.brightness != Brightness.dark) continue;
      darkChecked++;
      expect(
        tokens.surfaceElevatedColor.computeLuminance(),
        greaterThan(tokens.surfaceColor.computeLuminance()),
        reason:
            '${tokens.id}: docs/styling.md §9 requires elevated surfaces to read '
            'as a distinct, lighter layer on a dark theme',
      );
    }
    expect(
      darkChecked,
      greaterThan(0),
      reason: 'expected dark examples to ship',
    );
  });

  test('light examples keep text darker than the surface it sits on', () {
    var lightChecked = 0;
    for (final file in exampleFiles()) {
      final tokens = ThemeCodec.decode(file.readAsStringSync());
      if (tokens.brightness != Brightness.light) continue;
      lightChecked++;
      expect(
        tokens.textPrimaryColor.computeLuminance(),
        lessThan(tokens.surfaceColor.computeLuminance()),
        reason: '${tokens.id}: a light theme needs dark text (§7)',
      );
      expect(
        tokens.textSecondaryColor.computeLuminance(),
        greaterThan(tokens.textPrimaryColor.computeLuminance()),
        reason:
            '${tokens.id}: secondary text should recede — on a light theme that '
            'means lighter, not darker',
      );
    }
    expect(lightChecked, greaterThan(0), reason: 'expected a light example');
  });
}
