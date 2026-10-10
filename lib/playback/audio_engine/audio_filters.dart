import '../../core/settings/playback_settings.dart';

/// Pure builders for mpv (`media_kit`) audio-filter chains.
///
/// Kept free of any player dependency so the exact filter strings can be unit
/// tested without an audio device.
class AudioFilters {
  const AudioFilters._();

  /// EBU R128 integrated loudness target (LUFS) per normalization level.
  static double loudnessTarget(NormalizationLevel level) {
    switch (level) {
      case NormalizationLevel.quiet:
        return -20.0;
      case NormalizationLevel.normal:
        return -16.0;
      case NormalizationLevel.loud:
        return -12.0;
    }
  }

  /// A band equalizer filter for one band, in mpv's `equalizer` syntax.
  static String eqBand(EqBand band) {
    final g = band.gain;
    final f = band.frequency.toStringAsFixed(band.frequency % 1 == 0 ? 0 : 1);
    return 'equalizer=f=$f:t=q:w=1.0:g=${g.toStringAsFixed(1)}';
  }

  /// The full mpv `af` filter chain for the given settings, or `null` when no
  /// filters are required (which lets the caller clear `af` entirely).
  static String? buildAf(PlaybackSettings s) {
    final parts = <String>[];

    if (s.eqEnabled) {
      // Only emit bands with meaningful gain; a chain of all-zero bands is
      // wasted work.
      for (final b in s.eqBands) {
        if (b.gain.abs() >= 0.05) parts.add(eqBand(b));
      }
    }

    if (s.normalizationEnabled) {
      final i = loudnessTarget(s.normalizationLevel);
      parts.add('loudnorm=I=${i.toStringAsFixed(1)}:TP=-1.5:LRA=11');
    }

    if (s.monoAudio) {
      // Sum L+R into a single channel at equal weight.
      parts.add('pan=mono|c0=0.5*c0+0.5*c1');
    }

    if (parts.isEmpty) return null;
    return parts.join(',');
  }
}
