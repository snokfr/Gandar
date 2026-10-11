import 'dart:async';
import 'dart:io';

/// What a resolved stream URL turned out to be worth.
enum StreamVerdict {
  /// The URL served bytes from deep inside the file: a player can stream it.
  serves,

  /// The URL refused the request. Handing this to a player gives a track that
  /// never starts, or starts and dies — and to plain end-of-track it looks
  /// identical, which is how the queue used to race through a whole library in
  /// silence.
  refused,

  /// The check itself did not complete — a flaky network, a timeout. This is
  /// not a verdict on the stream, so callers should let the player try.
  unknown,
}

/// Asks a stream URL the cheapest question that only a real stream can answer.
///
/// Every cheaper check passes for a URL YouTube is not really serving: the
/// manifest resolved, the URL parses, and a small range at the start returns
/// `206`. What separates the two is a range *inside* the file, past the first
/// megabyte — YouTube's crippled URLs answer that with `403`, and a healthy URL
/// answers `206`. A kilobyte is enough, so the probe costs almost nothing.
class StreamHealth {
  const StreamHealth({
    this.from = defaultFrom,
    this.length = defaultLength,
    this.timeout = const Duration(seconds: 8),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  /// Where the probe asks for bytes from: one megabyte in, past the limit a
  /// URL without a PO token refuses at.
  static const int defaultFrom = 1024 * 1024;

  /// How many bytes the probe asks for. One kilobyte is plenty.
  static const int defaultLength = 1024;

  final int from;
  final int length;
  final Duration timeout;

  final HttpClient Function() _clientFactory;

  /// The verdict for [url].
  ///
  /// Never throws: a check that fails is [StreamVerdict.unknown], because a
  /// network hiccup must not be mistaken for a dead stream.
  Future<StreamVerdict> check(String url) async {
    final client = _clientFactory();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=$from-${from + length - 1}',
      );
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      return _verdictOf(response.statusCode);
    } catch (_) {
      return StreamVerdict.unknown;
    } finally {
      client.close(force: true);
    }
  }

  static StreamVerdict _verdictOf(int statusCode) {
    switch (statusCode) {
      case 200:
      // The server ignored the range and has started sending the file, which is
      // a stream this player can use.
      case 206:
        return StreamVerdict.serves;
      // Not satisfiable: the whole file is smaller than the probe offset, so
      // there is nothing beyond the first megabyte to be refused.
      case 416:
        return StreamVerdict.serves;
      case 401:
      case 403:
      case 404:
      case 410:
        return StreamVerdict.refused;
      default:
        // 5xx and anything unfamiliar: unknown rather than a refusal, so a bad
        // moment does not get a client marked dead.
        return StreamVerdict.unknown;
    }
  }
}
