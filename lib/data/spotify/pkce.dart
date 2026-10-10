import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636) helpers for the Authorization Code flow.
///
/// Desktop and mobile apps cannot keep a client secret, so Spotify's PKCE flow
/// (client id + code verifier only) is the correct choice here.
class Pkce {
  Pkce._();

  /// Characters permitted in a code verifier (unreserved set).
  static const String _verifierAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Generates a cryptographically random code verifier of [length] chars
  /// (RFC 7636 requires 43..128).
  static String generateVerifier({int length = 64, Random? random}) {
    assert(length >= 43 && length <= 128, 'verifier length must be 43..128');
    final rnd = random ?? Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(_verifierAlphabet[rnd.nextInt(_verifierAlphabet.length)]);
    }
    return sb.toString();
  }

  /// Derives the S256 code challenge for [verifier]:
  /// `BASE64URL(SHA256(ASCII(verifier)))` with padding removed.
  static String challengeFor(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// Generates the OAuth `state` parameter used to prevent CSRF.
  static String generateState({int length = 32, Random? random}) {
    final rnd = random ?? Random.secure();
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(alphabet[rnd.nextInt(alphabet.length)]);
    }
    return sb.toString();
  }
}
