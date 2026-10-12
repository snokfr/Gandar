import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/data/cache/audio_cache.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/domain/models/cache_entry.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

/// Writes bytes to the destination, the way a download does, and counts what it
/// was asked for so a test can prove nothing was fetched twice.
class _FakeDownloader implements AudioDownloader {
  _FakeDownloader({this.fail = false, this.bytes = 2048});

  final bool fail;
  final int bytes;
  final List<String> urls = <String>[];

  @override
  Future<void> download(
    String url,
    Map<String, String> headers,
    File destination,
  ) async {
    urls.add(url);
    if (fail) throw const SocketException('the CDN refused it');
    await destination.writeAsBytes(List<int>.filled(bytes, 7));
  }
}

/// A store that already knows which video a track resolved to on an earlier
/// play, which is what makes a cached file reachable.
class _Mappings implements MappingRepository {
  _Mappings([Map<String, String>? entries])
    : _entries = entries ?? <String, String>{};

  final Map<String, String> _entries;

  @override
  Future<String?> findVideoId(String spotifyTrackId) async =>
      _entries[spotifyTrackId];

  @override
  Future<void> saveMapping(String spotifyTrackId, String videoId) async =>
      _entries[spotifyTrackId] = videoId;

  @override
  Future<void> clearMapping(String spotifyTrackId) async =>
      _entries.remove(spotifyTrackId);
}

/// Counts resolutions and hands back whatever the test scripted, so a test can
/// say "the network was not touched this time" without a network.
class _ScriptedResolver implements AudioResolver {
  _ScriptedResolver(this.videoId);

  final String videoId;
  int calls = 0;

  @override
  Future<ResolvedStream> resolve(Track track) async {
    calls++;
    return ResolvedStream(
      url: 'https://cdn.example/$videoId',
      videoId: videoId,
      container: 'm4a',
      sizeBytes: 1024,
    );
  }

  @override
  void setAudioQuality(AudioQuality quality) {}
}

ResolvedStream _stream(String videoId) => ResolvedStream(
  url: 'https://cdn.example/$videoId',
  videoId: videoId,
  container: 'm4a',
  headers: const <String, String>{'referer': 'https://youtube.com'},
);

void main() {
  group('the audio cache', skip: sqliteSkipReason, () {
    late Directory directory;
    late AppDatabase database;
    late DriftCacheRepository repository;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('gandar-audio-cache');
      database = AppDatabase.withExecutor(NativeDatabase.memory());
      repository = DriftCacheRepository(database);
    });

    tearDown(() async {
      await database.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    AudioCache cacheWith(AudioDownloader downloader) => AudioCache(
      repository: repository,
      downloader: downloader,
      directory: () async => directory,
    );

    List<FileSystemEntity> leftovers() => directory
        .listSync()
        .where((entity) => entity.path.endsWith('.part'))
        .toList(growable: false);

    test(
      'a stored stream becomes a file, a row, and a playable path',
      () async {
        final downloader = _FakeDownloader(bytes: 4096);
        final cache = cacheWith(downloader);

        cache.store('vid1', _stream('vid1'));
        await cache.idle;

        expect(downloader.urls, <String>['https://cdn.example/vid1']);
        final entry = await repository.find('vid1');
        expect(entry, isNotNull);
        expect(entry!.sizeBytes, 4096);
        expect(entry.filePath, endsWith('vid1.m4a'));
        expect(File(entry.filePath).existsSync(), isTrue);
        expect(
          leftovers(),
          isEmpty,
          reason: 'the .part file must be gone once the real one is in place',
        );

        // What playback actually consumes: a local path, no expiry, and the
        // container read back off the filename.
        final hit = await cache.find('vid1', title: 'A song');
        expect(hit, isNotNull);
        expect(hit!.url, entry.filePath);
        expect(hit.videoId, 'vid1');
        expect(hit.container, 'm4a');
        expect(hit.sizeBytes, 4096);
        expect(
          hit.isExpired,
          isFalse,
          reason: 'a file on disk does not expire',
        );
      },
    );

    test('a row whose file has gone is forgotten, not served', () async {
      await repository.put(
        CacheEntry(
          videoId: 'gone',
          filePath: p.join(directory.path, 'gone.m4a'),
          sizeBytes: 10,
          lastPlayedAt: DateTime(2026, 1, 1),
        ),
      );

      final cache = cacheWith(_FakeDownloader());

      expect(await cache.find('gone'), isNull);
      expect(
        await repository.find('gone'),
        isNull,
        reason: 'a cache that points at nothing should not be believed twice',
      );
    });

    test('a failed download leaves nothing behind', () async {
      final cache = cacheWith(_FakeDownloader(fail: true));

      cache.store('vid2', _stream('vid2'));
      await cache.idle;

      expect(await repository.find('vid2'), isNull);
      expect(directory.listSync(), isEmpty);
    });

    test('the same video is not downloaded twice at once', () async {
      final downloader = _FakeDownloader();
      final cache = cacheWith(downloader);

      cache.store('vid3', _stream('vid3'));
      cache.store('vid3', _stream('vid3'));
      await cache.idle;

      expect(downloader.urls.length, 1);
    });

    test('storing is skipped when the file is already cached', () async {
      final downloader = _FakeDownloader();
      final cache = cacheWith(downloader);

      cache.store('vid4', _stream('vid4'));
      await cache.idle;
      cache.store('vid4', _stream('vid4'));
      await cache.idle;

      expect(downloader.urls.length, 1);
      expect((await repository.all()).length, 1, reason: 'one file, one row');
    });
  });

  group('the cache-first resolver', skip: sqliteSkipReason, () {
    late Directory directory;
    late AppDatabase database;
    late DriftCacheRepository repository;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('gandar-cached-resolver');
      database = AppDatabase.withExecutor(NativeDatabase.memory());
      repository = DriftCacheRepository(database);
    });

    tearDown(() async {
      await database.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('the second play comes off the disk, not the network', () async {
      final inner = _ScriptedResolver('vid9');
      final cache = AudioCache(
        repository: repository,
        downloader: _FakeDownloader(),
        directory: () async => directory,
      );
      final resolver = CachedAudioResolver(
        inner: inner,
        cache: cache,
        mappings: _Mappings(<String, String>{'spotify1': 'vid9'}),
      );

      final track = Track(
        id: 'spotify1',
        title: 'Song',
        artists: const <String>['Artist'],
      );

      final first = await resolver.resolve(track);
      await cache.idle; // the download the first play started
      final second = await resolver.resolve(track);

      expect(first.url, startsWith('https://'));
      expect(second.url, endsWith('vid9.m4a'));
      expect(second.url, isNot(startsWith('https://')));
      expect(
        inner.calls,
        1,
        reason: 'the cached play must not resolve anything',
      );
      expect(resolver.hits, 1);
    });

    test('a track nothing is known about still resolves normally', () async {
      final inner = _ScriptedResolver('vid10');
      final cache = AudioCache(
        repository: repository,
        downloader: _FakeDownloader(),
        directory: () async => directory,
      );
      final resolver = CachedAudioResolver(
        inner: inner,
        cache: cache,
        mappings: _Mappings(),
      );

      final track = Track(
        id: 'spotify2',
        title: 'Never played',
        artists: const <String>['Artist'],
      );

      await resolver.resolve(track);
      await resolver.resolve(track);

      expect(
        inner.calls,
        2,
        reason:
            'with no mapping there is nothing to look up, so each play is a '
            'fresh resolution rather than a silent failure',
      );
      expect(resolver.hits, 0);

      // Both plays started a download; let it finish before the temporary
      // directory goes away, or the failure it logs is this test's own doing.
      await cache.idle;
    });

    test('a YouTube track finds its own cached file', () async {
      // The resemblance between a YouTube id in the track id and a cached file
      // is the whole lookup for these: no mapping table involved.
      final inner = _ScriptedResolver('abc12345678');
      final cache = AudioCache(
        repository: repository,
        downloader: _FakeDownloader(),
        directory: () async => directory,
      );
      final resolver = CachedAudioResolver(
        inner: inner,
        cache: cache,
        mappings: _Mappings(),
      );

      const track = Track(
        id: 'youtube:abc12345678',
        title: 'From search',
        artists: <String>['Someone'],
      );

      await resolver.resolve(track);
      await cache.idle;
      final again = await resolver.resolve(track);

      expect(again.url, endsWith('abc12345678.m4a'));
      expect(inner.calls, 1);
    });
  });
}
