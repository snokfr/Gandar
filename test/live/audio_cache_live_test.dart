import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/cache/audio_cache.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/data/youtube/youtube_explode_resolver.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:path/path.dart' as p;

/// Live check that a track really lands on disk, and that playing it again
/// comes off the disk instead of the network.
///
/// Skipped by default: it needs YouTube, a real audio file and a few megabytes
/// of download, none of which belong in a suite that has to pass offline.
///
/// ```bash
/// flutter test --dart-define=LIVE=true test/live/audio_cache_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('LIVE');

/// Stands in for the drift mapping table, recording what the resolver saves so
/// the second resolve knows which video the cached file belongs to — exactly
/// the state the app is in on a second play.
class _MemoryMappings implements MappingRepository {
  final Map<String, String> _map = <String, String>{};

  @override
  Future<String?> findVideoId(String spotifyTrackId) async =>
      _map[spotifyTrackId];

  @override
  Future<void> saveMapping(String spotifyTrackId, String videoId) async =>
      _map[spotifyTrackId] = videoId;

  @override
  Future<void> clearMapping(String spotifyTrackId) async =>
      _map.remove(spotifyTrackId);
}

void main() {
  test(
    'a played track is written to disk, and plays from it next time',
    () async {
      final database = AppDatabase.withExecutor(NativeDatabase.memory());
      final cacheDirectory = Directory.systemTemp.createTempSync(
        'gandar-cache-live',
      );
      addTearDown(() async {
        await database.close();
        if (cacheDirectory.existsSync()) {
          cacheDirectory.deleteSync(recursive: true);
        }
      });

      final cacheRepository = DriftCacheRepository(database);
      final cache = AudioCache(
        repository: cacheRepository,
        downloader: DioAudioDownloader(),
        directory: () async => cacheDirectory,
      );
      // One set of mappings for both halves: the resolver saves the video it
      // used here, and the cache asks the same place which file belongs to
      // this track — which is how the app is wired.
      final mappings = _MemoryMappings();
      final resolver = CachedAudioResolver(
        inner: YoutubeExplodeResolver(mappings: mappings),
        cache: cache,
        mappings: mappings,
      );

      const track = Track(
        id: '3zOYmiNOuyDL0ClxJcEJ0T',
        title: 'Stop The Wedding!',
        artists: <String>['Ashe'],
      );

      try {
        final stream = await resolver.resolve(track);
        // ignore: avoid_print
        print('LIVE: resolved ${stream.videoId} (${stream.container})');

        // Bounded, because a CDN URL that stops delivering part way is a
        // thing YouTube does: the health check sees a range request answered,
        // and the download then stalls. The app survives that (the partial
        // file is thrown away and the track still plays); here it should be a
        // failure that says so rather than a hang.
        await cache.idle.timeout(
          const Duration(seconds: 90),
          onTimeout: () => fail(
            'the download never finished; the CDN URL ${stream.url.substring(0, 40)}… '
            'stalled before the whole file arrived',
          ),
        );

        final files = cacheDirectory
            .listSync()
            .map((entity) => p.basename(entity.path))
            .toList(growable: false);
        final entries = await cacheRepository.all();
        // ignore: avoid_print
        print('LIVE: files $files');
        // ignore: avoid_print
        print(
          'LIVE: entries '
          '${entries.map((e) => '${e.videoId}=${e.sizeBytes}').toList()}',
        );

        expect(entries, hasLength(1), reason: 'the write half must record it');
        expect(files, hasLength(1));
        expect(
          files.single.endsWith('.part'),
          isFalse,
          reason: 'a part file must never be the one left behind',
        );
        expect(entries.single.sizeBytes, greaterThan(1000000));
        expect(File(entries.single.filePath).existsSync(), isTrue);

        // The point of it all: the next play is local.
        final again = await resolver.resolve(track);
        // ignore: avoid_print
        print('LIVE: second play url ${again.url}');
        expect(again.url, isNot(startsWith('http')));
        expect(resolver.hits, 1);
      } on AudioResolutionException catch (e) {
        // ignore: avoid_print
        print('LIVE FAILURE: ${e.message} (cause: ${e.cause})');
        rethrow;
      }
    },
    skip: _live ? false : 'live network test; run with --dart-define=LIVE=true',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
