import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/import/library_file_import.dart';

/// An Exportify CSV, trimmed to the columns the app reads.
const String _exportify =
    '''Track URI,Track Name,Album Name,Artist Name(s),Added At,Duration (ms)
spotify:track:4cOdK2wGLETKBW3PvgPWqT,Never Gonna Give You Up,Whenever You Need Somebody,Rick Astley,2026-01-02T03:04:05Z,213573
spotify:track:3zOYmiNOuyDL0ClxJcEJ0T,Stop The Wedding!,,Ashe;Someone Else,2026-01-03T00:00:00Z,198840
''';

void main() {
  group('Exportify CSV', () {
    test('reads ids, titles, artists, albums and durations', () {
      final imported = parseLibraryFile('liked.csv', _exportify);

      expect(imported.tracks, hasLength(2));
      final first = imported.tracks.first;
      expect(first.id, '4cOdK2wGLETKBW3PvgPWqT');
      expect(first.title, 'Never Gonna Give You Up');
      expect(first.artists, <String>['Rick Astley']);
      expect(first.album, 'Whenever You Need Somebody');
      expect(first.durationMs, 213573);
      expect(first.addedAt, DateTime.parse('2026-01-02T03:04:05Z'));
      expect(imported.source, contains('Spotify ids'));
    });

    test('splits a multi-artist cell', () {
      final imported = parseLibraryFile('liked.csv', _exportify);
      expect(imported.tracks[1].artists, <String>['Ashe', 'Someone Else']);
      expect(imported.tracks[1].album, isNull);
    });

    test('skips rows with no title or artist and counts them', () {
      const csv = '''Track Name,Artist Name(s)
Good Song,An Artist
,An Artist
Another Song,
''';
      final imported = parseLibraryFile('x.csv', csv);
      expect(imported.tracks.map((t) => t.title), <String>['Good Song']);
      expect(imported.problems, hasLength(2));
    });

    test('refuses a file with no recognisable columns, with advice', () {
      expect(
        () => parseLibraryFile('notes.csv', 'a,b\n1,2\n'),
        throwsA(
          isA<LibraryFileException>().having(
            (e) => e.message,
            'message',
            contains('Exportify'),
          ),
        ),
      );
    });

    test('copes with a byte order mark and quoted commas', () {
      const csv = 'Track Name,Artist Name(s)\n"Hello, Goodbye",The Beatles\n';
      final imported = parseLibraryFile('x.csv', '\ufeff$csv');
      expect(imported.tracks.single.title, 'Hello, Goodbye');
      expect(imported.tracks.single.artists, <String>['The Beatles']);
    });

    test('tolerates unquoted column names and extra columns', () {
      const csv =
          'song title ; artist ; mood\n'
          'Blue Monday;New Order;spiky\n';
      final imported = parseLibraryFile('x.csv', csv);
      expect(imported.tracks.single.title, 'Blue Monday');
      expect(imported.tracks.single.artists, <String>['New Order']);
    });
  });

  group('ids', () {
    test('keeps the Spotify id so a later sync recognises the track', () {
      final imported = parseLibraryFile('liked.csv', _exportify);
      expect(imported.tracks.first.id, '4cOdK2wGLETKBW3PvgPWqT');
    });

    test('without ids, the same track gets the same id every time', () {
      const csv = 'Track Name,Artist Name(s)\nBlue Monday,New Order\n';
      final a = parseLibraryFile('x.csv', csv).tracks.single;
      final b = parseLibraryFile('x.csv', csv).tracks.single;
      expect(a.id, b.id);
      expect(a.id, startsWith('file-'));
      // Different track, different id.
      const other = 'Track Name,Artist Name(s)\nTrue Faith,New Order\n';
      expect(parseLibraryFile('x.csv', other).tracks.single.id, isNot(a.id));
    });
  });

  group('Spotify account export', () {
    test('reads YourLibrary.json', () {
      const json = '''
{"tracks":[
  {"artist":"Rick Astley","album":"Whenever You Need Somebody","track":"Never Gonna Give You Up","uri":"spotify:track:4cOdK2wGLETKBW3PvgPWqT"},
  {"artist":"Ashe","album":"","track":"Stop The Wedding!","uri":"spotify:track:3zOYmiNOuyDL0ClxJcEJ0T"}
]}''';
      final imported = parseLibraryFile('YourLibrary.json', json);
      expect(imported.tracks, hasLength(2));
      expect(imported.tracks.first.title, 'Never Gonna Give You Up');
      expect(imported.tracks.first.artists, <String>['Rick Astley']);
      expect(imported.tracks.first.id, '4cOdK2wGLETKBW3PvgPWqT');
    });

    test('reads Playlist1.json, falling back to the playlist name', () {
      const json = '''
{"playlists":[{"name":"Road Trip","items":[
  {"track":{"trackName":"Blue Monday","artistName":"New Order","trackUri":"spotify:track:abc"}},
  {"track":{"trackName":"Unknown Artist Song","trackUri":"spotify:track:def"}}
]}]}''';
      final imported = parseLibraryFile('Playlist1.json', json);
      expect(imported.tracks.first.title, 'Blue Monday');
      expect(imported.tracks.first.artists, <String>['New Order']);
      expect(imported.tracks[1].artists, <String>['Road Trip']);
    });

    test('explains itself on JSON it cannot use', () {
      expect(
        () => parseLibraryFile('weird.json', '{"hello":"world"}'),
        throwsA(
          isA<LibraryFileException>().having(
            (e) => e.message,
            'message',
            contains('YourLibrary.json'),
          ),
        ),
      );
      expect(
        () => parseLibraryFile('broken.json', '{"tracks": ['),
        throwsA(isA<LibraryFileException>()),
      );
    });

    test('rejects an empty file', () {
      expect(
        () => parseLibraryFile('empty.csv', '   \n'),
        throwsA(isA<LibraryFileException>()),
      );
    });
  });

  group('parseCsv', () {
    test('handles quotes, escaped quotes and embedded newlines', () {
      const csv = 'a,b\n"one,two","he said ""hi""\nsecond line"\n';
      final rows = parseCsv(csv);
      expect(rows, hasLength(2));
      expect(rows[1][0], 'one,two');
      expect(rows[1][1], 'he said "hi"\nsecond line');
    });

    test('ignores a trailing newline and CRLF line endings', () {
      final rows = parseCsv('a,b\r\n1,2\r\n');
      expect(rows, hasLength(2));
      expect(rows.last, <String>['1', '2']);
    });
  });
}
