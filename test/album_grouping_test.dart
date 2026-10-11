import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/album.dart';
import 'package:gandar/domain/models/track.dart';

Track _track({
  required String id,
  required String title,
  String artist = 'Artist',
  String? album,
  int durationMs = 180000,
  String? artworkUrl,
}) => Track(
  id: id,
  title: title,
  artists: <String>[artist],
  album: album,
  durationMs: durationMs,
  artworkUrl: artworkUrl,
);

void main() {
  group('Album.group', () {
    test('files tracks under the album printed on them', () {
      final albums = Album.group(<Track>[
        _track(id: '1', title: 'One', album: 'Blue', artworkUrl: 'a.jpg'),
        _track(id: '2', title: 'Two', album: 'Blue'),
        _track(id: '3', title: 'Three', album: 'Red'),
      ]);

      expect(albums.map((a) => a.name), <String>['Blue', 'Red']);
      expect(albums.first.trackCount, 2);
      expect(albums.first.tracks.map((t) => t.title), <String>['One', 'Two']);
      expect(albums.first.duration, const Duration(milliseconds: 360000));
    });

    test('names the album after the artist most of its tracks credit', () {
      final albums = Album.group(<Track>[
        _track(id: '1', title: 'One', artist: 'Guests', album: 'Split'),
        _track(id: '2', title: 'Two', artist: 'The Band', album: 'Split'),
        _track(id: '3', title: 'Three', artist: 'The Band', album: 'Split'),
      ]);

      expect(
        albums.single.artist,
        'The Band',
        reason:
            'a record with guests should not be renamed by whichever track '
            'happens to come first',
      );
    });

    test('takes the first cover any of its tracks has', () {
      final albums = Album.group(<Track>[
        _track(id: '1', title: 'One', album: 'Blue'),
        _track(id: '2', title: 'Two', album: 'Blue', artworkUrl: 'cover.jpg'),
      ]);

      expect(albums.single.artworkUrl, 'cover.jpg');
    });

    test('leaves out tracks that name no album', () {
      final albums = Album.group(<Track>[
        _track(id: '1', title: 'One', album: 'Blue'),
        _track(id: '2', title: 'Two'),
        _track(id: '3', title: 'Three'),
      ]);

      expect(albums, hasLength(1));
      expect(
        albums.single.tracks.map((t) => t.title),
        <String>['One'],
        reason:
            'an import without album names should not produce an album '
            'called Unknown',
      );
    });

    test('ignores an empty album name that is not null', () {
      final albums = Album.group(<Track>[
        _track(id: '1', title: 'One', album: '   '),
      ]);

      expect(albums, isEmpty);
    });

    test('orders the shelf by artist, then album, ignoring case', () {
      final albums = Album.group(<Track>[
        _track(id: '1', title: 'One', artist: 'zebra', album: 'Later'),
        _track(id: '2', title: 'Two', artist: 'Apple', album: 'Second'),
        _track(id: '3', title: 'Three', artist: 'apple', album: 'First'),
      ]);

      expect(
        albums.map((a) => '${a.artist}/${a.name}'),
        // 'Apple' and 'apple' are the same artist as far as the shelf is
        // concerned, so those two are ordered by album name, and each album
        // keeps the spelling it was imported with.
        <String>['apple/First', 'Apple/Second', 'zebra/Later'],
      );
    });

    test('is not affected by the order tracks arrive in', () {
      final tracks = <Track>[
        _track(id: '1', title: 'One', artist: 'A', album: 'X'),
        _track(id: '2', title: 'Two', artist: 'A', album: 'Y'),
        _track(id: '3', title: 'Three', artist: 'B', album: 'Z'),
      ];

      final forwards = Album.group(tracks).map((a) => a.id).toList();
      final backwards = Album.group(tracks.reversed.toList(growable: false))
          .map((a) => a.id)
          .toList();

      expect(forwards, backwards);
    });

    test('is empty for an empty library', () {
      expect(Album.group(const <Track>[]), isEmpty);
    });
  });
}
