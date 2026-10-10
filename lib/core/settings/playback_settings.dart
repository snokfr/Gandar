import 'dart:math' as math;

/// Volume-normalization target levels (Spotify-style: Quiet/Normal/Loud).
enum NormalizationLevel { quiet, normal, loud }

/// Shuffle behaviours.
enum ShuffleMode {
  /// Pure Fisher-Yates; may repeat adjacent tracks.
  standard,

  /// Weighted shuffle that actively avoids recent repeats. Best for large
  /// libraries where "random" feels repetitive.
  smart,

  off,
}

/// A single equalizer band.
class EqBand {
  const EqBand({required this.frequency, this.gain = 0.0});

  /// Center frequency in Hz.
  final double frequency;

  /// Gain in decibels, typically -12..+12.
  final double gain;

  EqBand copyWith({double? frequency, double? gain}) =>
      EqBand(frequency: frequency ?? this.frequency, gain: gain ?? this.gain);

  Map<String, dynamic> toJson() => {'f': frequency, 'g': gain};

  static EqBand fromJson(Map<String, dynamic> j) => EqBand(
    frequency: (j['f'] as num).toDouble(),
    gain: (j['g'] as num?)?.toDouble() ?? 0.0,
  );
}

/// The full playback-configuration surface, modeled after Spotify's playback
/// settings menu plus the extra controls Gandar exposes.
class PlaybackSettings {
  const PlaybackSettings({
    this.eqEnabled = false,
    this.eqPreset = 'flat',
    this.eqBands = defaultBands,
    this.crossfadeSeconds = 0.0,
    this.normalizationEnabled = false,
    this.normalizationLevel = NormalizationLevel.normal,
    this.monoAudio = false,
    this.gaplessPlayback = true,
    this.automixEnabled = false,
    this.shuffleMode = ShuffleMode.standard,
    this.prefetchNextTrack = true,
    this.cacheMaxMegabytes = 2048,
    this.cacheMaxIdleDays = 30,
  });

  /// 10-band ISO center frequencies.
  static const List<EqBand> defaultBands = <EqBand>[
    EqBand(frequency: 31),
    EqBand(frequency: 62),
    EqBand(frequency: 125),
    EqBand(frequency: 250),
    EqBand(frequency: 500),
    EqBand(frequency: 1000),
    EqBand(frequency: 2000),
    EqBand(frequency: 4000),
    EqBand(frequency: 8000),
    EqBand(frequency: 16000),
  ];

  final bool eqEnabled;
  final String eqPreset;
  final List<EqBand> eqBands;

  /// 0 disables crossfade. Range 0..12 seconds, per Spotify.
  final double crossfadeSeconds;

  final bool normalizationEnabled;
  final NormalizationLevel normalizationLevel;
  final bool monoAudio;
  final bool gaplessPlayback;
  final bool automixEnabled;
  final ShuffleMode shuffleMode;

  /// Pre-fetch the next track's audio stream while the current one plays.
  final bool prefetchNextTrack;

  final int cacheMaxMegabytes;
  final int cacheMaxIdleDays;

  PlaybackSettings copyWith({
    bool? eqEnabled,
    String? eqPreset,
    List<EqBand>? eqBands,
    double? crossfadeSeconds,
    bool? normalizationEnabled,
    NormalizationLevel? normalizationLevel,
    bool? monoAudio,
    bool? gaplessPlayback,
    bool? automixEnabled,
    ShuffleMode? shuffleMode,
    bool? prefetchNextTrack,
    int? cacheMaxMegabytes,
    int? cacheMaxIdleDays,
  }) {
    return PlaybackSettings(
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqPreset: eqPreset ?? this.eqPreset,
      eqBands: eqBands ?? this.eqBands,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      normalizationEnabled: normalizationEnabled ?? this.normalizationEnabled,
      normalizationLevel: normalizationLevel ?? this.normalizationLevel,
      monoAudio: monoAudio ?? this.monoAudio,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      automixEnabled: automixEnabled ?? this.automixEnabled,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      prefetchNextTrack: prefetchNextTrack ?? this.prefetchNextTrack,
      cacheMaxMegabytes: cacheMaxMegabytes ?? this.cacheMaxMegabytes,
      cacheMaxIdleDays: cacheMaxIdleDays ?? this.cacheMaxIdleDays,
    );
  }

  /// Clamps user input into the documented ranges.
  PlaybackSettings sanitized() {
    return copyWith(
      crossfadeSeconds: crossfadeSeconds.clamp(0.0, 12.0).toDouble(),
      cacheMaxMegabytes: math.max(128, cacheMaxMegabytes),
      cacheMaxIdleDays: math.max(1, cacheMaxIdleDays),
      eqBands: _normalizeBands(eqBands),
    );
  }

  static List<EqBand> _normalizeBands(List<EqBand> bands) {
    if (bands.isEmpty) return defaultBands;
    return bands
        .map((b) => b.copyWith(gain: b.gain.clamp(-12.0, 12.0).toDouble()))
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() => {
    'eqEnabled': eqEnabled,
    'eqPreset': eqPreset,
    'eqBands': eqBands.map((b) => b.toJson()).toList(),
    'crossfadeSeconds': crossfadeSeconds,
    'normalizationEnabled': normalizationEnabled,
    'normalizationLevel': normalizationLevel.name,
    'monoAudio': monoAudio,
    'gaplessPlayback': gaplessPlayback,
    'automixEnabled': automixEnabled,
    'shuffleMode': shuffleMode.name,
    'prefetchNextTrack': prefetchNextTrack,
    'cacheMaxMegabytes': cacheMaxMegabytes,
    'cacheMaxIdleDays': cacheMaxIdleDays,
  };

  static PlaybackSettings fromJson(Map<String, dynamic> j) {
    final rawBands = j['eqBands'];
    return PlaybackSettings(
      eqEnabled: j['eqEnabled'] as bool? ?? false,
      eqPreset: j['eqPreset'] as String? ?? 'flat',
      eqBands: rawBands is List && rawBands.isNotEmpty
          ? rawBands
                .map(
                  (b) => EqBand.fromJson(Map<String, dynamic>.from(b as Map)),
                )
                .toList(growable: false)
          : defaultBands,
      crossfadeSeconds: (j['crossfadeSeconds'] as num?)?.toDouble() ?? 0.0,
      normalizationEnabled: j['normalizationEnabled'] as bool? ?? false,
      normalizationLevel: NormalizationLevel.values.firstWhere(
        (v) => v.name == j['normalizationLevel'],
        orElse: () => NormalizationLevel.normal,
      ),
      monoAudio: j['monoAudio'] as bool? ?? false,
      gaplessPlayback: j['gaplessPlayback'] as bool? ?? true,
      automixEnabled: j['automixEnabled'] as bool? ?? false,
      shuffleMode: ShuffleMode.values.firstWhere(
        (v) => v.name == j['shuffleMode'],
        orElse: () => ShuffleMode.standard,
      ),
      prefetchNextTrack: j['prefetchNextTrack'] as bool? ?? true,
      cacheMaxMegabytes: (j['cacheMaxMegabytes'] as num?)?.toInt() ?? 2048,
      cacheMaxIdleDays: (j['cacheMaxIdleDays'] as num?)?.toInt() ?? 30,
    ).sanitized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSettings &&
          other.eqEnabled == eqEnabled &&
          other.eqPreset == eqPreset &&
          other.crossfadeSeconds == crossfadeSeconds &&
          other.normalizationEnabled == normalizationEnabled &&
          other.normalizationLevel == normalizationLevel &&
          other.monoAudio == monoAudio &&
          other.gaplessPlayback == gaplessPlayback &&
          other.automixEnabled == automixEnabled &&
          other.shuffleMode == shuffleMode &&
          other.prefetchNextTrack == prefetchNextTrack &&
          other.cacheMaxMegabytes == cacheMaxMegabytes &&
          other.cacheMaxIdleDays == cacheMaxIdleDays &&
          _bandsEqual(other.eqBands, eqBands);

  static bool _bandsEqual(List<EqBand> a, List<EqBand> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].frequency != b[i].frequency || a[i].gain != b[i].gain) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    eqEnabled,
    eqPreset,
    eqBands.length,
    crossfadeSeconds,
    normalizationEnabled,
    normalizationLevel,
    monoAudio,
    gaplessPlayback,
    automixEnabled,
    shuffleMode,
    prefetchNextTrack,
    cacheMaxMegabytes,
    cacheMaxIdleDays,
  );
}
