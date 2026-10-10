import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Spotify OAuth tokens.
class SpotifyTokens {
  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.scope = '',
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String scope;

  /// Treats the token as expired 60s early so in-flight requests never race
  /// the expiry boundary.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'scope': scope,
  };

  static SpotifyTokens fromJson(Map<String, dynamic> j) => SpotifyTokens(
    accessToken: j['accessToken'] as String,
    refreshToken: j['refreshToken'] as String,
    expiresAt: DateTime.parse(j['expiresAt'] as String),
    scope: j['scope'] as String? ?? '',
  );
}

/// Persists tokens outside the app bundle.
abstract class TokenStore {
  Future<SpotifyTokens?> read();
  Future<void> write(SpotifyTokens tokens);
  Future<void> clear();
}

/// Production store backed by the platform keychain/credential vault.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _key = 'gandar.spotify.tokens';

  @override
  Future<SpotifyTokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SpotifyTokens.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      // A corrupt/unreadable blob is treated as "not signed in".
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(SpotifyTokens tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// In-memory store for tests and ephemeral sessions.
class InMemoryTokenStore implements TokenStore {
  SpotifyTokens? _tokens;

  @override
  Future<SpotifyTokens?> read() async => _tokens;

  @override
  Future<void> write(SpotifyTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
