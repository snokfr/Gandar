import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_codec.dart';
import '../theme/theme_tokens.dart';
import 'playback_settings.dart';

/// Minimal key/value abstraction so the repository is unit-testable without
/// platform channels.
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// Production implementation backed by `shared_preferences`.
class SharedPrefsStore implements KeyValueStore {
  SharedPrefsStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<SharedPrefsStore> open() async =>
      SharedPrefsStore(await SharedPreferences.getInstance());

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) async => _prefs.remove(key);
}

/// In-memory store used by tests and as a safe fallback.
class InMemoryStore implements KeyValueStore {
  InMemoryStore([Map<String, String>? seed])
    : _data = Map<String, String>.from(seed ?? const {});

  final Map<String, String> _data;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);
}

/// Reads and writes user preferences.
class SettingsRepository {
  SettingsRepository(this._store);

  final KeyValueStore _store;

  /// The underlying store, for the few other things that need somewhere small
  /// and persistent to put a number — the app-usage counter, currently.
  KeyValueStore get store => _store;

  static const String _playbackKey = 'settings.playback.v1';
  static const String _activeThemeKey = 'settings.theme.active.v1';
  static const String _customThemesKey = 'settings.theme.custom.v1';
  static const String _logLevelKey = 'settings.log.level.v1';

  Future<PlaybackSettings> loadPlayback() async {
    final raw = await _store.getString(_playbackKey);
    if (raw == null || raw.isEmpty) return const PlaybackSettings();
    try {
      return PlaybackSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      ).sanitized();
    } catch (_) {
      // Corrupt payload: fall back to defaults rather than crashing the app.
      return const PlaybackSettings();
    }
  }

  Future<void> savePlayback(PlaybackSettings settings) =>
      _store.setString(_playbackKey, jsonEncode(settings.sanitized().toJson()));

  Future<String?> loadActiveThemeId() => _store.getString(_activeThemeKey);

  Future<void> saveActiveThemeId(String id) =>
      _store.setString(_activeThemeKey, id);

  /// Custom themes are stored as a JSON array of encoded theme maps.
  Future<List<ThemeTokens>> loadCustomThemes() async {
    final raw = await _store.getString(_customThemesKey);
    if (raw == null || raw.isEmpty) return const <ThemeTokens>[];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ThemeCodec.fromMap)
          .toList(growable: false);
    } catch (_) {
      return const <ThemeTokens>[];
    }
  }

  Future<void> saveCustomThemes(List<ThemeTokens> themes) => _store.setString(
    _customThemesKey,
    jsonEncode(themes.map(ThemeCodec.toMap).toList()),
  );

  /// Persisted log level name, or null to use the default for the build mode.
  Future<String?> loadLogLevelName() => _store.getString(_logLevelKey);

  Future<void> saveLogLevelName(String name) =>
      _store.setString(_logLevelKey, name);
}
