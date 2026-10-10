import 'playback_settings.dart';

/// A named equalizer preset: a set of gains applied to [PlaybackSettings.defaultBands].
class EqPreset {
  const EqPreset(this.id, this.label, this.gains);

  final String id;
  final String label;

  /// Gain in dB per band, in the same order as [PlaybackSettings.defaultBands].
  final List<double> gains;

  /// Materializes this preset into concrete [EqBand]s.
  List<EqBand> apply() {
    return <EqBand>[
      for (var i = 0; i < PlaybackSettings.defaultBands.length; i++)
        PlaybackSettings.defaultBands[i].copyWith(
          gain: i < gains.length ? gains[i] : 0.0,
        ),
    ];
  }
}

/// Built-in presets, ordered as they appear in the picker.
class EqPresets {
  const EqPresets._();

  static const List<EqPreset> all = <EqPreset>[
    EqPreset('flat', 'Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    EqPreset('bass_boost', 'Bass Boost', [8, 7, 5, 3, 1, 0, 0, 0, 0, 0]),
    EqPreset('bass_reducer', 'Bass Reducer', [
      -8,
      -7,
      -5,
      -3,
      -1,
      0,
      0,
      0,
      0,
      0,
    ]),
    EqPreset('acoustic', 'Acoustic', [3, 2, 1, 1, 1, 1, 2, 2, 3, 3]),
    EqPreset('classical', 'Classical', [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]),
    EqPreset('dance', 'Dance', [6, 5, 2, 0, 0, -2, -1, 1, 4, 5]),
    EqPreset('electronic', 'Electronic', [5, 4, 2, 0, -1, -2, 0, 2, 4, 5]),
    EqPreset('hip_hop', 'Hip-Hop', [7, 6, 3, 1, -1, -1, 1, 2, 3, 3]),
    EqPreset('jazz', 'Jazz', [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
    EqPreset('loudness', 'Loudness', [6, 5, 2, 0, -1, 0, 1, 3, 5, 6]),
    EqPreset('pop', 'Pop', [-1, 0, 1, 3, 4, 4, 2, 0, -1, -1]),
    EqPreset('rock', 'Rock', [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]),
    EqPreset('vocal', 'Vocal Boost', [-2, -1, 0, 2, 3, 3, 2, 1, 0, -1]),
  ];

  static EqPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
