import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models/track.dart';

/// What a library file turned out to contain.
class LibraryFileImport {
  const LibraryFileImport({
    required this.source,
    required this.tracks,
    this.problems = const <String>[],
  });

  /// Human-readable description of where the tracks came from, e.g.
  /// `Exportify CSV` or `YourLibrary.json`.
  final String source;
  final List<Track> tracks;

  /// Rows that could not be used, and why. A partial import is better than a
  /// failed one, but the count is never hidden from the user.
  final List<String> problems;
}

/// Raised when a file is recognised but unusable.
class LibraryFileException implements Exception {
  LibraryFileException(this.message);
  final String message;
  @override
  String toString() => 'LibraryFileException: $message';
}

/// Reads the library files people actually have.
///
/// Three formats, in the order they are most likely to be handed to Gandar:
///
/// * **Exportify CSV** — a header row with `Track URI`, `Track Name`,
///   `Artist Name(s)`, `Album Name`, `Duration (ms)`. Works for liked songs and
///   for a single playlist.
/// * **Spotify account export** — `YourLibrary.json` (`{"tracks": [...]}`) or
///   `Playlist1.json` (`{"playlists": [{"items": [...]}]}`) from Spotify's own
///   "Download your data" page.
/// * **Any plain CSV** — as long as it has a name column and an artist column,
///   the column names are matched loosely.
///
/// A track's Spotify id is kept when the file has one, so a later successful
/// Web API sync recognises the same tracks instead of duplicating them. Files
/// without ids get a deterministic id derived from artist and title, which
/// keeps re-imports idempotent and lets the audio mapping cache survive.
LibraryFileImport parseLibraryFile(String fileName, String contents) {
  final text = _stripByteOrderMark(contents);
  if (text.trim().isEmpty) {
    throw LibraryFileException('$fileName is empty.');
  }

  final looksJson =
      text.trimLeft().startsWith('{') || text.trimLeft().startsWith('[');
  if (looksJson) return _parseJson(fileName, text);
  return _parseCsv(fileName, text);
}

/// Picks the delimiter from the header line.
///
/// Exportify writes commas, but a spreadsheet saved in a comma-decimal locale
/// writes semicolons, and a copied table can arrive tab-separated. Guessing
/// once from the header is cheaper than failing on a file that is fine.
String _sniffDelimiter(String text) {
  final headerLine = text.split(RegExp(r'\r?\n')).first;
  final candidates = <String>[',', ';', '\t'];
  var best = ',';
  var bestCount = 0;
  for (final candidate in candidates) {
    final count = candidate.allMatches(headerLine).length;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return bestCount == 0 ? ',' : best;
}

/// Parses an Exportify/plain CSV.
LibraryFileImport _parseCsv(String fileName, String text) {
  final rows = parseCsv(text, delimiter: _sniffDelimiter(text));
  if (rows.isEmpty) throw LibraryFileException('$fileName has no rows.');

  final header = rows.first;
  final columns = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    columns[_normalize(header[i])] = i;
  }

  int? of(List<String> names) {
    for (final name in names) {
      final index = columns[name];
      if (index != null) return index;
    }
    return null;
  }

  final idAt = of(<String>['trackuri', 'uri', 'spotifyuri', 'trackid']);
  final titleAt = of(<String>[
    'trackname',
    'songtitle',
    'songname',
    'name',
    'title',
    'track',
  ]);
  final artistAt = of(<String>[
    'artistnames',
    'artistname',
    'artists',
    'artist',
  ]);
  if (titleAt == null || artistAt == null) {
    throw LibraryFileException(
      '$fileName does not look like a track list: no "Track Name"/"Artist" '
      'columns. Export your library with Exportify, or use Spotify\'s '
      '"Download your data".',
    );
  }
  final albumAt = of(<String>['albumname', 'album']);
  final durationAt = of(<String>['durationms', 'duration', 'lengthms']);
  final durationSecAt = of(<String>['durationsec', 'durationseconds']);
  final isrcAt = of(<String>['isrc']);
  final addedAt = of(<String>['addedat', 'addeddate', 'added']);

  final tracks = <Track>[];
  final problems = <String>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.every((cell) => cell.trim().isEmpty)) continue;
    final title = _cell(row, titleAt).trim();
    final artist = _cell(row, artistAt).trim();
    if (title.isEmpty || artist.isEmpty) {
      problems.add('row ${r + 1}: missing title or artist');
      continue;
    }
    final rawId = _cell(row, idAt);
    final durationMs = durationSecAt != null
        ? (int.tryParse(_cell(row, durationSecAt)) ?? 0) * 1000
        : int.tryParse(_cell(row, durationAt)) ?? 0;
    tracks.add(
      Track(
        id: _trackId(rawId, artist: artist, title: title),
        title: title,
        artists: _splitArtists(artist),
        album: albumAt == null ? null : _emptyToNull(_cell(row, albumAt)),
        durationMs: durationMs,
        isrc: isrcAt == null ? null : _emptyToNull(_cell(row, isrcAt)),
        addedAt: addedAt == null
            ? null
            : DateTime.tryParse(_cell(row, addedAt)),
      ),
    );
  }

  if (tracks.isEmpty) {
    throw LibraryFileException('No usable track rows in $fileName.');
  }
  return LibraryFileImport(
    source: idAt == null ? 'CSV' : 'CSV with Spotify ids',
    tracks: tracks,
    problems: problems,
  );
}

/// Parses Spotify's account export, or a list of track objects.
LibraryFileImport _parseJson(String fileName, String text) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw LibraryFileException('$fileName is not valid JSON ($e).');
  }

  final tracks = <Track>[];
  final problems = <String>[];

  void addFromMap(Map<String, dynamic> json, String? fallbackArtist) {
    final title =
        (json['track'] ?? json['trackName'] ?? json['name'] ?? json['title'])
            ?.toString()
            .trim() ??
        '';
    final artist =
        (json['artist'] ?? json['artistName'] ?? json['artists'])?.toString() ??
        fallbackArtist ??
        '';
    if (title.isEmpty || artist.trim().isEmpty) {
      problems.add('a JSON entry has no title or artist');
      return;
    }
    final uri = json['uri']?.toString();
    final album = json['album']?.toString();
    tracks.add(
      Track(
        id: _trackId(uri, artist: artist, title: title),
        title: title,
        artists: _splitArtists(artist),
        album: album == null || album.isEmpty ? null : album,
        durationMs: _durationMs(json['duration_ms'] ?? json['durationMs']),
      ),
    );
  }

  if (decoded is List) {
    for (final item in decoded) {
      if (item is Map) addFromMap(Map<String, dynamic>.from(item), null);
    }
  } else if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    final list = map['tracks'] ?? map['items'];
    if (list is List) {
      for (final item in list) {
        if (item is Map) addFromMap(Map<String, dynamic>.from(item), null);
      }
    }
    // Playlist1.json: a list of playlists, each with its own items.
    final playlists = map['playlists'];
    if (playlists is List) {
      for (final playlist in playlists) {
        if (playlist is! Map) continue;
        final name = playlist['name']?.toString() ?? 'Imported playlist';
        final items = playlist['items'];
        if (items is! List) continue;
        for (final item in items) {
          if (item is! Map) continue;
          final track = item['track'] ?? item;
          if (track is Map) {
            addFromMap(
              Map<String, dynamic>.from(track),
              playlist['name']?.toString() ?? name,
            );
          }
        }
      }
    }
  }

  if (tracks.isEmpty) {
    throw LibraryFileException(
      '$fileName has no tracks Gandar recognises. Spotify\'s own export calls '
      'this file YourLibrary.json; Exportify CSV files are also accepted.',
    );
  }
  return LibraryFileImport(
    source: 'JSON (${fileName.split(RegExp(r'[/\\]')).last})',
    tracks: tracks,
    problems: problems,
  );
}

/// Splits a CSV into rows of cells, honouring quotes and embedded newlines.
///
/// Hand-written because the file sizes involved (a few hundred kilobytes) do
/// not justify a dependency, and the rules are short: a field is quoted when it
/// starts with a quote, doubled quotes inside mean one literal quote, and
/// everything else splits on the delimiter.
List<List<String>> parseCsv(String text, {String delimiter = ','}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var i = 0;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    // A trailing newline should not produce an empty final row.
    if (row.length == 1 && row.first.isEmpty) {
      row = <String>[];
      return;
    }
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        quoted = false;
        i++;
        continue;
      }
      cell.write(char);
      i++;
      continue;
    }
    if (char == '"' && cell.isEmpty) {
      quoted = true;
      i++;
      continue;
    }
    if (char == delimiter) {
      endCell();
      i++;
      continue;
    }
    if (char == '\r') {
      // Treat CRLF and lone CR as one line break.
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
      i++;
      continue;
    }
    if (char == '\n') {
      endRow();
      i++;
      continue;
    }
    cell.write(char);
    i++;
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

String _stripByteOrderMark(String text) =>
    text.startsWith('\ufeff') ? text.substring(1) : text;

String _normalize(String header) =>
    header.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

String _cell(List<String> row, int? index) =>
    index == null || index >= row.length ? '' : row[index];

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _durationMs(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// `spotify:track:<id>` and bare ids are kept as-is; anything else is hashed.
String _trackId(String? raw, {required String artist, required String title}) {
  final text = raw?.trim() ?? '';
  if (text.isNotEmpty) {
    final parts = text.split(':');
    final candidate = parts.last;
    if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(candidate)) return candidate;
  }
  final digest = sha1.convert(utf8.encode('${artist.trim()}|${title.trim()}'));
  return 'file-${digest.toString().substring(0, 22)}';
}

/// Exportify joins multiple artists with a semicolon; Spotify uses a comma.
List<String> _splitArtists(String artists) => artists
    .split(RegExp(';|,|/|&'))
    .map((a) => a.trim())
    .where((a) => a.isNotEmpty)
    .toList(growable: false);
