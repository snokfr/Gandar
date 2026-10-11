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
}
