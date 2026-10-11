import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/track.dart';
import '../net/request_gate.dart';

/// One line of time-synced lyrics, and when it starts.
class LyricLine {
  const LyricLine({required this.at, required this.text});

  /// When the line begins, from the LRC timestamp.
  final Duration at;

  /// The words. Empty for a line the LRC marks as an instrumental gap: it
  /// still occupies a moment, and the highlight is expected to move through it
  /// rather than jump over it.
  final String text;

  bool get isBlank => text.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine && other.at == at && other.text == text;

  @override
  int get hashCode => Object.hash(at, text);

  @override
  String toString() => 'LyricLine($at, "$text")';
}

/// The line that should be highlighted when playback is at [position].
///
/// Returns -1 before the first line begins, which is what a track with a long
/// instrumental intro wants: nothing highlighted yet, rather than the first
/// line lit up from the start. Binary search, because this runs on every
/// position tick and a long lyric is a few hundred lines.
int activeLineIndex(List<LyricLine> lines, Duration position) {
  if (lines.isEmpty) return -1;
  if (position < lines.first.at) return -1;
  var low = 0;
  var high = lines.length - 1;
  var found = 0;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    if (lines[middle].at <= position) {
      found = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return found;
}

/// Lyrics for one track, plain and — when the source has them — time-synced.
class Lyrics {
  const Lyrics({
    required this.plain,
    this.synced,
    this.instrumental = false,
    this.attribution = '',
  });

  /// The words, with any timestamp markup removed.
  final String plain;

  /// The original LRC text (lines prefixed with `[mm:ss.xx]`), or null when the
  /// source only had plain lyrics.
  final String? synced;

  /// The source says this track has no words at all.
  final bool instrumental;

  /// Who to credit, e.g. `LRCLIB`.
  final String attribution;

  bool get hasSynced => synced != null && synced!.trim().isNotEmpty;
  bool get isEmpty => plain.trim().isEmpty;

  /// The time-synced lines, or empty when the source had only plain text.
  ///
  /// Parsed on demand rather than stored: [Lyrics] is a `const` value that is
  /// handed around whole, and the carriers of one track's lyrics are few. The
  /// view that displays them parses once per track and keeps the result.
  List<LyricLine> get timedLines =>
      hasSynced ? linesFromLrc(synced!) : const <LyricLine>[];

  static const Lyrics none = Lyrics(plain: '');

  /// Timestamps, in either LRC spelling: `[mm:ss.xx]` or `[mm:ss:xx]`.
  static final RegExp _timestamp = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]',
  );

  /// Parses LRC text into sorted, timed lines.
  ///
  /// Three details the format allows and this has to get right: a line may
  /// carry **several** timestamps (the same words repeated later, as in a
  /// chorus), the timestamp's fraction may be centiseconds or milliseconds, and
  /// metadata tags (`[ar:…]`) look like timestamps but are not.
  static List<LyricLine> linesFromLrc(String lrc) {
    final lines = <LyricLine>[];
    for (final raw in lrc.split('\n')) {
      final matches = _timestamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      // The words follow the last timestamp; every timestamp before it on the
      // same line refers to those same words.
      final text = raw.substring(matches.last.end).trim();
      for (final match in matches) {
        lines.add(LyricLine(at: _timeOf(match), text: text));
      }
    }
    lines.sort((a, b) => a.at.compareTo(b.at));
    return List<LyricLine>.unmodifiable(lines);
  }

  static Duration _timeOf(RegExpMatch match) {
    final fraction = match.group(3);
    var milliseconds = 0;
    if (fraction != null && fraction.isNotEmpty) {
      // `.5`, `.50` and `.500` all mean 500 ms: pad right, then take three
      // digits. Reading the fraction as a plain integer instead would turn
      // `.5` into 5 ms and put the line two beats early.
      milliseconds = int.parse(fraction.padRight(3, '0').substring(0, 3));
    }
    return Duration(
      minutes: int.parse(match.group(1)!),
      seconds: int.parse(match.group(2)!),
      milliseconds: milliseconds,
    );
  }

  /// Reads one LRCLIB response.
  ///
  /// Returns null for anything that is not a usable lyrics payload, so a
  /// changed response shape degrades to "no lyrics" rather than an exception in
  /// the middle of the player.
  static Lyrics? fromJson(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final instrumental = decoded['instrumental'] == true;
    final synced = decoded['syncedLyrics']?.toString();
    final plain = decoded['plainLyrics']?.toString();

    final words = (plain != null && plain.trim().isNotEmpty)
        ? plain
        : (synced != null ? plainFromLrc(synced) : '');

    if (words.trim().isEmpty && !instrumental) return null;
    return Lyrics(
      plain: words,
      synced: synced,
      instrumental: instrumental,
      attribution: 'LRCLIB',
    );
  }

  /// Strips `[mm:ss.xx]` timestamps from LRC text, leaving the words.
  ///
  /// Also drops LRC's metadata tags (`[ar:…]`, `[ti:…]`), which are not lyrics.
  static String plainFromLrc(String lrc) {
    final out = <String>[];
    for (final raw in lrc.split('\n')) {
      final line = raw.replaceAll(_timestamp, '');
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^\[[a-zA-Z#]+:.*\]$').hasMatch(trimmed)) continue;
      out.add(trimmed);
    }
    return out.join('\n');
  }
}

/// Where lyrics come from. Injectable so the player is testable offline.
abstract class LyricsSource {
  /// Lyrics for [track], or null when the source has none.
  Future<Lyrics?> lookup(Track track);
}

/// Lyrics from LRCLIB (lrclib.net).
///
/// Why this one: it is a free, open, documented API that needs no account, no
/// key and no OAuth, and it returns both plain and time-synced lyrics. Every
/// alternative either needs credentials (Genius, Musixmatch) or is a page
/// scrape that breaks whenever the site is redesigned. Its guide asks clients
/// to identify themselves, which the User-Agent below does.
///
/// Lookups are best-effort by design: lyrics are decoration on the player, so
/// a failure returns null and is logged rather than interrupting playback.
class LrcLibLyrics implements LyricsSource {
  LrcLibLyrics({Dio? http, RequestGate? gate})
    : _http =
          http ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
            ),
          ),
      _gate = gate ?? RequestGate(defaultRefillPerSecond: 1, defaultBurst: 2) {
    _governor = _gate.forHost('lrclib.net');
  }

  final Dio _http;
  final RequestGate _gate;
  late final HostGovernor _governor;

  /// Identifies the app, as LRCLIB's guidance asks.
  static const String userAgent =
      'Gandar/1.0 (https://github.com/snokfr/Gandar)';

  static const String _base = 'https://lrclib.net/api';

  @override
  Future<Lyrics?> lookup(Track track) async {
    final title = track.title.trim();
    if (title.isEmpty) return null;

    final exact = await _get('$_base/get', <String, String>{
      'track_name': title,
      'artist_name': track.primaryArtist,
      if ((track.album ?? '').isNotEmpty) 'album_name': track.album!,
      // LRCLIB matches on duration to tell a studio cut from a live one, but a
      // YouTube-sourced track may have no duration at all, so it is optional.
      if (track.durationMs > 0)
        'duration': (track.durationMs / 1000).round().toString(),
    });
    if (exact != null) return exact;

    // Nothing exact: fall back to a fuzzy search on "artist title", which is
    // what rescues a track whose Spotify title carries a feature suffix.
    final query = track.searchQuery;
    if (query.isEmpty) return null;
    final searched = await _get('$_base/search', <String, String>{
      'q': query,
    }, list: true);
    return searched;
  }

  /// One gated request. [list] reads the search endpoint's array shape.
  Future<Lyrics?> _get(
    String url,
    Map<String, String> query, {
    bool list = false,
  }) async {
    try {
      final response = await _governor.schedule(
        () => _http.get<dynamic>(
          url,
          queryParameters: query,
          options: Options(
            headers: <String, String>{'User-Agent': userAgent},
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 600,
          ),
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 404) return null;
      if (status != 200) {
        AppLogger.instance.debug('lyrics', '$url -> HTTP $status');
        return null;
      }
      final body = response.data?.toString() ?? '';
      if (!list) return Lyrics.fromJson(body);

      final decoded = jsonDecode(body);
      if (decoded is! List) return null;
      for (final item in decoded) {
        if (item is! Map) continue;
        final candidate = Lyrics.fromJson(jsonEncode(item));
        if (candidate != null && !candidate.isEmpty) return candidate;
      }
      return null;
    } on DioException catch (e) {
      AppLogger.instance.debug('lyrics', 'lookup failed: ${e.message}');
      return null;
    } on FormatException catch (e) {
      AppLogger.instance.debug('lyrics', 'response was not JSON: $e');
      return null;
    }
  }
}
