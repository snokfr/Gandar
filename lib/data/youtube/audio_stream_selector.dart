import '../../core/settings/playback_settings.dart';

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

/// Chooses the best playable audio stream for the requested quality.
///
/// Rules that hold at every quality:
///  1. Never prefer a live stream (no seekable duration).
///  2. Break exact ties by the smaller file, then deterministically by URL so
///     selection is reproducible in tests.
///
/// Then, per [AudioQuality]:
///  * **balanced** prefers the `mp4`/m4a container — broadly decodable, and
///    what Spotify-sourced tracks expect — and the highest bitrate within it.
///  * **best** ignores the container and takes the highest bitrate outright,
///    which is how the Opus streams that beat the m4a ones get chosen.
///  * **data saver** takes the *smallest* stream that is still above
///    [minimumDataSaverBitrate], falling back to the largest available when
///    every stream is below it.
class AudioStreamSelector {
  const AudioStreamSelector();

  /// Below this, YouTube's own encodes start sounding like a phone call. Used
  /// as a floor for data saver rather than a target.
  static const int minimumDataSaverBitrate = 64000;

  AudioOption? selectBest(
    List<AudioOption> options, {
    AudioQuality quality = AudioQuality.balanced,
  }) {
    if (options.isEmpty) return null;

    if (quality == AudioQuality.dataSaver) return _smallestPlayable(options);

    final sorted = List<AudioOption>.of(options)
      ..sort(
        quality == AudioQuality.best ? _compareByQuality : _compareBalanced,
      );
    return sorted.first;
  }

  /// The lightest stream that is still worth listening to.
  ///
  /// Live streams are kept only as a last resort, matching the other two
  /// levels: dropping them entirely here would make "all that exists is a live
  /// stream" mean a silent failure at one quality and a playing track at
  /// another.
  AudioOption? _smallestPlayable(List<AudioOption> options) {
    final sorted = List<AudioOption>.of(options)..sort(_compareSmaller);
    final playable = sorted.where((o) => !o.isLive).toList();
    final pool = playable.isEmpty ? sorted : playable;

    final adequate = pool
        .where((o) => o.bitrateBitsPerSecond >= minimumDataSaverBitrate)
        .toList();
    if (adequate.isNotEmpty) return adequate.first;

    // Everything is below the floor: take the best of what there is rather
    // than the worst, because "smallest" was only ever a means to an end.
    final best = List<AudioOption>.of(pool)..sort(_compareByQuality);
    return best.first;
  }

  /// Highest bitrate first, container irrelevant.
  int _compareByQuality(AudioOption a, AudioOption b) {
    if (a.isLive != b.isLive) return a.isLive ? 1 : -1;
    if (a.bitrateBitsPerSecond != b.bitrateBitsPerSecond) {
      return b.bitrateBitsPerSecond.compareTo(a.bitrateBitsPerSecond);
    }
    return _breakTie(a, b);
  }

  /// Lowest bitrate first, then the smaller file.
  int _compareSmaller(AudioOption a, AudioOption b) {
    if (a.isLive != b.isLive) return a.isLive ? 1 : -1;
    if (a.bitrateBitsPerSecond != b.bitrateBitsPerSecond) {
      return a.bitrateBitsPerSecond.compareTo(b.bitrateBitsPerSecond);
    }
    return _breakTie(a, b);
  }

  /// A known file size beats an unknown one, then the smaller file wins, then
  /// the URL, so the answer never depends on the order the streams arrived in.
  int _breakTie(AudioOption a, AudioOption b) {
    final aKnown = a.sizeBytes > 0;
    final bKnown = b.sizeBytes > 0;
    if (aKnown != bKnown) return aKnown ? -1 : 1;
    if (a.sizeBytes != b.sizeBytes) return a.sizeBytes.compareTo(b.sizeBytes);
    return a.url.compareTo(b.url);
  }

  int _compareBalanced(AudioOption a, AudioOption b) {
    if (a.isLive != b.isLive) return a.isLive ? 1 : -1;

    final aMp4 = a.container == 'mp4';
    final bMp4 = b.container == 'mp4';
    if (aMp4 != bMp4) return aMp4 ? -1 : 1;

    if (a.bitrateBitsPerSecond != b.bitrateBitsPerSecond) {
      return b.bitrateBitsPerSecond.compareTo(a.bitrateBitsPerSecond);
    }
    return _breakTie(a, b);
  }
}
