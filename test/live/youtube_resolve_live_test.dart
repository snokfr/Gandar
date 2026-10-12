import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/youtube/youtube_explode_resolver.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';

/// Live check that a real track still resolves to a playable stream.
///
/// Skipped by default — YouTube extraction is the most fragile part of the app,
/// and a suite that depends on it would fail for reasons outside the project.
///
/// ```bash
/// flutter test --dart-define=LIVE=true test/live/youtube_resolve_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('LIVE');

/// Stands in for the drift mapping table.
class _MemoryMappings implements MappingRepository {
  _MemoryMappings([String? stored]) {
    if (stored != null) _map['*'] = stored;
  }

  final Map<String, String> _map = <String, String>{};
  final List<String> saved = <String>[];

  String? get stored => _map['*'];

  @override
  Future<String?> findVideoId(String spotifyTrackId) async =>
      _map[spotifyTrackId] ?? _map['*'];

  @override
  Future<void> saveMapping(String spotifyTrackId, String videoId) async {
    saved.add(videoId);
    _map[spotifyTrackId] = videoId;
  }

  @override
  Future<void> clearMapping(String spotifyTrackId) async =>
      _map.remove(spotifyTrackId);
}

void main() {
  test(
    'resolves a track to a direct audio stream',
    () async {
      final resolver = YoutubeExplodeResolver(mappings: _MemoryMappings());
      addTearDown(resolver.dispose);

      const track = Track(
        id: '3zOYmiNOuyDL0ClxJcEJ0T',
        title: 'Stop The Wedding!',
        artists: <String>['Ashe'],
      );

      try {
        final stream = await resolver.resolve(track);
        // ignore: avoid_print
        print(
          'LIVE: ${track.searchQuery} -> ${stream.container} '
          '${stream.bitrate}bps ${stream.sizeBytes} bytes\n      ${stream.url.substring(0, 90)}…',
        );
        expect(stream.url, startsWith('http'));
      } on AudioResolutionException catch (e) {
        // ignore: avoid_print
        print('LIVE FAILURE: ${e.message} (cause: ${e.cause})');
        rethrow;
      }
    },
    skip: _live ? false : 'live network test; run with --dart-define=LIVE=true',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a stored mapping to a dead video does not stop the track playing',
    () async {
      // Eleven characters, the length of a YouTube id, and not one that has
      // ever existed — so YouTube reports it unavailable, which is the same
      // answer a video gets when it is taken down or age-gated after its
      // mapping was written.
      final mappings = _MemoryMappings('zzzzzzzzzzz');
      final resolver = YoutubeExplodeResolver(mappings: mappings);
      addTearDown(resolver.dispose);

      final track = Track(
        id: '7eZXAeqqdLDrAp2MvrPzWn',
        title: 'stranger',
        artists: const <String>['Jhené Aiko'],
      );

      try {
        final stream = await resolver.resolve(track);
        // ignore: avoid_print
        print(
          'LIVE: played anyway -> ${mappings.stored} '
          '(${stream.container} ${stream.sizeBytes} bytes), '
          'searched after zzzzzzzzzzz: ${mappings.saved.isNotEmpty}',
        );
        expect(stream.url, startsWith('http'));
        expect(
          mappings.saved,
          isNot(contains('zzzzzzzzzzz')),
          reason: 'the dead id must not be saved back over the good one',
        );
      } on AudioResolutionException catch (e) {
        // ignore: avoid_print
        print('LIVE FAILURE: ${e.message} (cause: ${e.cause})');
        rethrow;
      }
    },
    skip: _live ? false : 'live network test; run with --dart-define=LIVE=true',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
