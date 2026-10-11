import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/artwork/artwork_enricher.dart';
import 'package:gandar/data/artwork/artwork_lookup.dart';
import 'package:gandar/data/net/request_gate.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/domain/models/track.dart';

/// Live check of the artwork pass: real lookups, real database, no stubs.
///
/// ```bash
/// flutter test --dart-define=LIVE=true test/live/artwork_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('LIVE');

const List<Track> _tracks = <Track>[
  Track(
    id: '3zOYmiNOuyDL0ClxJcEJ0T',
    title: 'Stop The Wedding!',
    artists: <String>['Ashe'],
  ),
  Track(
    id: '70cHKK8bHAfJrOGVnfRG9J',
    title: 'Nicole Kidman',
    artists: <String>['ADÉLA'],
  ),
  Track(
    id: '4cOdK2wGLETKBW3PvgPWqT',
    title: 'Never Gonna Give You Up',
    artists: <String>['Rick Astley'],
  ),
];

void main() {
  test(
    'finds covers for real tracks and stores them',
    () async {
      final database = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(database.close);
      final library = DriftLibraryRepository(database);
      await library.upsertTracks(_tracks);

      final pendingBefore = await library.tracksMissingArtwork();
      expect(pendingBefore, hasLength(3));

      final sw = Stopwatch()..start();
      final result = await ArtworkEnricher(
        library: library,
        source: ITunesArtwork(
          gate: RequestGate(defaultRefillPerSecond: 1, defaultBurst: 3),
        ),
      ).run();
      // ignore: avoid_print
      print(
        'LIVE: ${result.updated}/3 covers in ${sw.elapsedMilliseconds} ms '
        '(${result.missing} not found)',
      );
      for (final track in await library.cachedLikedTracks()) {
        // ignore: avoid_print
        print('      ${track.title} -> ${track.artworkUrl}');
      }

      expect(result.updated, greaterThan(0));
      expect(await library.tracksMissingArtwork(), isEmpty);
      expect(
        (await library.cachedLikedTracks()).every(
          (t) => t.artworkUrl!.startsWith('https://'),
        ),
        isTrue,
      );
    },
    skip: _live ? false : 'live network test; run with --dart-define=LIVE=true',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
