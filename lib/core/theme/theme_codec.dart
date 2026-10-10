import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import 'theme_tokens.dart';

/// Raised when a theme file cannot be parsed into a valid [ThemeTokens].
class ThemeFormatException implements Exception {
  ThemeFormatException(this.message);
  final String message;
  @override
  String toString() => 'ThemeFormatException: $message';
}

/// Encodes/decodes [ThemeTokens] to and from JSON and YAML.
///
/// The on-disk shape is intentionally flat and human-editable so users can
/// hand-write or tweak themes:
///
/// ```json
/// {
///   "format": "gandar.theme",
///   "version": 1,
///   "id": "spotify_classic",
///   "name": "Spotify Classic",
///   "brightness": "dark",
///   "colors": { "backgroundPrimary": "#121212", ... },
///   "radius": { "sm": 6, "md": 12, "lg": 20 }
/// }
/// ```
class ThemeCodec {
  static const String formatTag = 'gandar.theme';
  static const int currentVersion = 1;

  /// Required color keys; used for validation with helpful errors.
  static const List<String> _colorKeys = <String>[
    'backgroundPrimary',
    'backgroundSecondary',
    'surface',
    'surfaceElevated',
    'textPrimary',
    'textSecondary',
    'accent',
    'accentAlt',
    'border',
  ];

  static Map<String, dynamic> toMap(ThemeTokens t) {
    return <String, dynamic>{
      'format': formatTag,
      'version': currentVersion,
      'id': t.id,
      'name': t.name,
      'brightness': t.brightness == Brightness.light ? 'light' : 'dark',
      'colors': <String, dynamic>{
        'backgroundPrimary': _hex(t.backgroundPrimary),
        'backgroundSecondary': _hex(t.backgroundSecondary),
        'surface': _hex(t.surface),
        'surfaceElevated': _hex(t.surfaceElevated),
        'textPrimary': _hex(t.textPrimary),
        'textSecondary': _hex(t.textSecondary),
        'accent': _hex(t.accent),
        'accentAlt': _hex(t.accentAlt),
        'border': _hex(t.border),
      },
      'radius': <String, dynamic>{
        'sm': t.radiusSm,
        'md': t.radiusMd,
        'lg': t.radiusLg,
      },
    };
  }

  static String toJson(ThemeTokens t, {bool pretty = true}) {
    final map = toMap(t);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(map)
        : jsonEncode(map);
  }

  static String toYaml(ThemeTokens t) {
    final StringBuffer b = StringBuffer();
    final map = toMap(t);
    b.writeln('format: ${map['format']}');
    b.writeln('version: ${map['version']}');
    b.writeln('id: ${map['id']}');
    b.writeln('name: ${_yamlString(map['name'] as String)}');
    b.writeln('brightness: ${map['brightness']}');
    b.writeln('colors:');
    final colors = map['colors'] as Map<String, dynamic>;
    for (final key in _colorKeys) {
      b.writeln('  $key: "${colors[key]}"');
    }
    b.writeln('radius:');
    final radius = map['radius'] as Map<String, dynamic>;
    b.writeln('  sm: ${radius['sm']}');
    b.writeln('  md: ${radius['md']}');
    b.writeln('  lg: ${radius['lg']}');
    return b.toString();
  }

  /// Decodes either format. Detection is content-based (YAML is a JSON
  /// superset, so we try JSON first, then YAML).
  static ThemeTokens decode(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw ThemeFormatException('Theme file is empty.');
    }
    dynamic parsed;
    try {
      parsed = jsonDecode(trimmed);
    } catch (_) {
      try {
        parsed = loadYaml(trimmed);
      } catch (e) {
        throw ThemeFormatException('Not valid JSON or YAML: $e');
      }
    }
    final normalized = _normalize(parsed);
    if (normalized is! Map<String, dynamic>) {
      throw ThemeFormatException('Theme root must be a mapping/object.');
    }
    return fromMap(normalized);
  }

  static ThemeTokens fromMap(Map<String, dynamic> map) {
    final format = map['format'];
    if (format != null && format != formatTag) {
      throw ThemeFormatException(
        'Unknown format "$format" (expected "$formatTag").',
      );
    }
    final colors = map['colors'];
    if (colors is! Map) {
      throw ThemeFormatException('Missing "colors" mapping.');
    }
    final missing = _colorKeys.where((k) => colors[k] == null).toList();
    if (missing.isNotEmpty) {
      throw ThemeFormatException('Missing color(s): ${missing.join(', ')}.');
    }

    final radius = map['radius'] is Map
        ? map['radius'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return ThemeTokens(
      id: _asString(map['id']) ?? 'custom',
      name: _asString(map['name']) ?? 'Custom Theme',
      brightness: _asString(map['brightness']) == 'light'
          ? Brightness.light
          : Brightness.dark,
      backgroundPrimary: _parseColor(
        colors['backgroundPrimary'],
        'backgroundPrimary',
      ),
      backgroundSecondary: _parseColor(
        colors['backgroundSecondary'],
        'backgroundSecondary',
      ),
      surface: _parseColor(colors['surface'], 'surface'),
      surfaceElevated: _parseColor(
        colors['surfaceElevated'],
        'surfaceElevated',
      ),
      textPrimary: _parseColor(colors['textPrimary'], 'textPrimary'),
      textSecondary: _parseColor(colors['textSecondary'], 'textSecondary'),
      accent: _parseColor(colors['accent'], 'accent'),
      accentAlt: _parseColor(colors['accentAlt'], 'accentAlt'),
      border: _parseColor(colors['border'], 'border'),
      radiusSm: _asDouble(radius['sm']) ?? 6,
      radiusMd: _asDouble(radius['md']) ?? 12,
      radiusLg: _asDouble(radius['lg']) ?? 20,
    );
  }

  /// Accepts `#RRGGBB`, `#AARRGGBB`, `RRGGBB`, or a raw int.
  static int _parseColor(dynamic value, String key) {
    if (value is int) {
      return value <= 0xFFFFFF ? 0xFF000000 | value : value;
    }
    if (value is String) {
      var s = value.trim();
      if (s.startsWith('#')) s = s.substring(1);
      if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
      if (s.length == 6) s = 'FF$s';
      if (s.length != 8) {
        throw ThemeFormatException(
          'Color "$key" must be 6 or 8 hex digits, got "$value".',
        );
      }
      final parsed = int.tryParse(s, radix: 16);
      if (parsed == null) {
        throw ThemeFormatException('Color "$key" is not valid hex: "$value".');
      }
      return parsed;
    }
    throw ThemeFormatException('Color "$key" must be a string or int.');
  }

  static String _hex(int argb) =>
      '#${(argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';

  static String? _asString(dynamic v) => v?.toString();

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static String _yamlString(String s) {
    if (s.contains(RegExp(r'[:#{}[\],&*?|<>=!%@`]')) || s.trim() != s) {
      return '"${s.replaceAll('"', r'\"')}"';
    }
    return s;
  }

  /// YAML maps come back as `YamlMap`/`Map<dynamic, dynamic>`; normalize so the
  /// rest of the code can rely on `Map<String, dynamic>` while leaving scalar
  /// values untouched.
  static dynamic _normalize(Object? node) {
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((k, v) => out[k.toString()] = _normalize(v));
      return out;
    }
    if (node is List) return node.map(_normalize).toList();
    return node;
  }
}
