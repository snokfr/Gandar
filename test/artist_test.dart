import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/artist.dart';
import 'package:gandar/domain/models/track.dart';

Track _track({
  required String id,
  required String title,
  required List<String> artists,
  String? album,
  int durationMs = 0,
  String? artworkUrl,
}) => Track(
  id: id,
  title: title,
  artists: artists,
  album: album,
  durationMs: durationMs,
  artworkUrl: artworkUrl,
);

/// What an artist page is allowed to show, and what it must not.
///
/// The library stores every artist of a track in one newline-separated field,
/// so the two ways to get this wrong are cheap to make and easy to miss: a
/// substring test puts the wrong songs on a page, and a whole-field test hides
/// the ones where a guest is named first.
void main() {
  final library = <Track>[
    _track(
      id: 'a',
      title: 'One',
      artists: const <String>['Ariana Grande'],
      album: 'Sweetener',
      durationMs: 180000,
      artworkUrl: 'https://art/a.jpg',
    ),
    _track(
      id: 'b',
      title: 'Two',
      artists: const <String>['Ariana Grande', 'The Weeknd'],
      album: 'Sweetener',
      durationMs: 200000,
    ),
    _track(
      id: 'c',
      title: 'Three',
      artists: const <String>['The Weeknd'],
      album: 'After Hours',
      durationMs: 240000,
      artworkUrl: 'https://art/c.jpg',
    ),
    _track(
      id: 'd',
      title: 'Four',
      artists: const <String>['Ari'],
      album: 'Something Else',
      durationMs: 100000,
    ),
  ];

  test('finds every track that credits the artist, in library order', () {
    final artist = Artist.of(library, 'Ariana Grande');

    expect(artist.tracks.map((t) => t.id), <String>['a', 'b']);
    expect(artist.trackCount, 2);
  });

  test('does not match a name that is only a substring of one', () {
    final artist = Artist.of(library, 'Ari');

    expect(
      artist.tracks.map((t) => t.id),
      <String>['d'],
      reason: 'a page for Ari must not claim Ariana Grande\'s songs',
    );
    expect(artist.trackCount, 1);
  });

  test('finds a track that names a guest before the artist', () {
    final artist = Artist.of(library, 'The Weeknd');

    expect(
      artist.tracks.map((t) => t.id),
      <String>['b', 'c'],
      reason: 'being second on a track still counts as being on it',
    );
  });

  test('matches whatever case the route carried', () {
    expect(
      Artist.of(library, 'ariana grande').tracks.map((t) => t.id),
      <String>['a', 'b'],
    );
  });

  test('shows the name the way the library spells it', () {
    final artist = Artist.of(library, 'the weeknd');
    expect(artist.name, 'The Weeknd');
  });

  test('lists each album once, in the order the tracks appear', () {
    final artist = Artist.of(library, 'The Weeknd');
    expect(artist.albums, <String>['Sweetener', 'After Hours']);
  });

  test('totals the playing time it actually has', () {
    final artist = Artist.of(library, 'Ariana Grande');
    expect(artist.duration, const Duration(milliseconds: 380000));
  });

  test('takes artwork from the first track that has any', () {
    expect(Artist.of(library, 'Ariana Grande').artworkUrl, 'https://art/a.jpg');
    expect(Artist.of(library, 'Ari').artworkUrl, isNull);
  });

  test('an artist the library has never heard of is empty, not an error', () {
    final artist = Artist.of(library, 'Nobody At All');

    expect(artist.tracks, isEmpty);
    expect(artist.albums, isEmpty);
    expect(artist.duration, Duration.zero);
    expect(artist.name, 'Nobody At All');
  });

  test('a blank name matches nothing rather than everybody', () {
    for (final name in <String>['', '   ']) {
      expect(
        Artist.of(library, name).tracks,
        isEmpty,
        reason: 'an empty route must not list the whole library',
      );
    }
  });
}
