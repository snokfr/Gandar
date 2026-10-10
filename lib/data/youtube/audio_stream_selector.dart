/// A provider-neutral description of one available audio stream.
class AudioOption {
  const AudioOption({
    required this.url,
    required this.container,
    required this.bitrateBitsPerSecond,
    required this.sizeBytes,
    this.audioCodec = '',
    this.isLive = false,
  });

  final String url;

  /// `mp4`, `webm`, ...
  final String container;
  final int bitrateBitsPerSecond;
  final int sizeBytes;
  final String audioCodec;
  final bool isLive;

  /// Preferred file extension for the cached file.
  String get extension => container == 'mp4' ? 'm4a' : container;
}

/// Chooses the best playable audio stream.
///
/// Rules, in priority order:
///  1. Never prefer a live stream (no seekable duration).
///  2. Prefer the `mp4`/m4a container: it is broadly decodable and is what
///     Spotify-sourced tracks expect.
///  3. Among equally-ranked containers, take the highest bitrate.
///  4. Break exact ties by the smaller file, then deterministically by URL so
///     selection is reproducible in tests.
class AudioStreamSelector {
  const AudioStreamSelector();

  AudioOption? selectBest(List<AudioOption> options) {
    if (options.isEmpty) return null;
    final sorted = List<AudioOption>.of(options)..sort(_compare);
    return sorted.first;
  }

  int _compare(AudioOption a, AudioOption b) {
    if (a.isLive != b.isLive) return a.isLive ? 1 : -1;

    final aMp4 = a.container == 'mp4';
    final bMp4 = b.container == 'mp4';
    if (aMp4 != bMp4) return aMp4 ? -1 : 1;

    if (a.bitrateBitsPerSecond != b.bitrateBitsPerSecond) {
      return b.bitrateBitsPerSecond.compareTo(a.bitrateBitsPerSecond);
    }
    // Prefer a known file size over an unknown (0) one, then the smaller file.
    final aKnown = a.sizeBytes > 0;
    final bKnown = b.sizeBytes > 0;
    if (aKnown != bKnown) return aKnown ? -1 : 1;
    if (a.sizeBytes != b.sizeBytes) return a.sizeBytes.compareTo(b.sizeBytes);
    return a.url.compareTo(b.url);
  }
}
