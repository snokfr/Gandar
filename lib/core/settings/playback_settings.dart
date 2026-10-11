import 'dart:math' as math;

/// Volume-normalization target levels (Spotify-style: Quiet/Normal/Loud).
enum NormalizationLevel { quiet, normal, loud }

/// How much bandwidth the resolver may spend on one track's audio.
///
/// YouTube publishes each video's audio as several independent streams, so this
/// is a real choice rather than a wish: it decides which one is downloaded.
enum AudioQuality {
  /// The smallest stream that is still music. For metered connections.
  dataSaver,

  /// The default: the best m4a stream. Broadly decodable, without chasing the
  /// very largest encode of the same audio.
  balanced,

  /// The highest-bitrate stream available, whatever container or size.
  best,
}

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

/// A saved, user-made equalizer preset.
///
/// Lives in the settings blob rather than a table of its own: a preset is a
/// handful of numbers that only mean anything alongside the EQ settings they
/// modify, and keeping them together means one write and one read.
class CustomEqPreset {
  const CustomEqPreset({
    required this.id,
    required this.name,
    required this.gains,
  });

  final String id;
  final String name;

  /// Gain in dB per band, in [PlaybackSettings.defaultBands] order.
  final List<double> gains;

  CustomEqPreset copyWith({String? name, List<double>? gains}) => CustomEqPreset(
    id: id,
    name: name ?? this.name,
    gains: gains ?? this.gains,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'gains': gains,
  };

  static CustomEqPreset fromJson(Map<String, dynamic> j) => CustomEqPreset(
    id: j['id']?.toString() ?? 'custom',
    name: j['name']?.toString() ?? 'Custom',
    gains: <double>[
      for (final g in (j['gains'] as List? ?? const <dynamic>[]))
        (g as num).toDouble(),
    ],
  );
}

/// The full playback-configuration surface, modeled after Spotify's playback
/// settings menu plus the extra controls Gandar exposes.
class PlaybackSettings {
  const PlaybackSettings({
    this.eqEnabled = false,
    this.eqPreset = 'flat',
    this.eqBands = defaultBands,
    this.customEqPresets = const <CustomEqPreset>[],
    this.audioQuality = AudioQuality.balanced,
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
    this.showYouTubeInSearch = true,
    this.savingsPremiumMonthlyCost = 12.99,
    this.savingsAdBreakMinutes = 12.0,
    this.savingsAdSeconds = 30.0,
    this.savingsAdsPerBreak = 1.0,
    this.savingsAdsCpm = 20.0,
    this.savingsArtistPayoutPerStream = 0.004,
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

  /// Presets the user saved themselves, newest last. Applied on top of the
  /// built-in ones in the picker.
  final List<CustomEqPreset> customEqPresets;

  /// How much bandwidth the resolver is allowed to spend on a stream.
  final AudioQuality audioQuality;

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

  /// Show YouTube results on the search screen.
  final bool showYouTubeInSearch;

  // ---- The savings model's assumptions --------------------------------
  //
  // Every one of these is an assumption the user can change, and the savings
  // card says so. They are modeled on measured behaviour rather than invented:
  // an ad break every 10-15 minutes, ads up to 30 seconds, and a roughly
  // $15-$25 CPM for audio inventory. The defaults sit in the middle.

  /// Monthly price of the subscription being compared against.
  ///
  /// Defaults to Spotify's US Individual price after the January 2026 increase.
  final double savingsPremiumMonthlyCost;

  /// Minutes of listening between ad breaks on a free, ad-supported service.
  final double savingsAdBreakMinutes;

  /// Length of a single ad spot, in seconds.
  final double savingsAdSeconds;

  /// How many ads are played in one break.
  final double savingsAdsPerBreak;

  /// Gross advertiser cost per thousand impressions, in US dollars. This is
  /// what the *advertiser* pays, which is the number that describes how much
  /// the free tier earns from a listener.
  final double savingsAdsCpm;

  /// Estimated rights-holder payout per stream, in US dollars.
  final double savingsArtistPayoutPerStream;

  PlaybackSettings copyWith({
    bool? eqEnabled,
    String? eqPreset,
    List<EqBand>? eqBands,
    List<CustomEqPreset>? customEqPresets,
    AudioQuality? audioQuality,
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
    bool? showYouTubeInSearch,
    double? savingsPremiumMonthlyCost,
    double? savingsAdBreakMinutes,
    double? savingsAdSeconds,
    double? savingsAdsPerBreak,
    double? savingsAdsCpm,
    double? savingsArtistPayoutPerStream,
  }) {
    return PlaybackSettings(
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqPreset: eqPreset ?? this.eqPreset,
      eqBands: eqBands ?? this.eqBands,
      customEqPresets: customEqPresets ?? this.customEqPresets,
      audioQuality: audioQuality ?? this.audioQuality,
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
      showYouTubeInSearch: showYouTubeInSearch ?? this.showYouTubeInSearch,
      savingsPremiumMonthlyCost:
          savingsPremiumMonthlyCost ?? this.savingsPremiumMonthlyCost,
      savingsAdBreakMinutes:
          savingsAdBreakMinutes ?? this.savingsAdBreakMinutes,
      savingsAdSeconds: savingsAdSeconds ?? this.savingsAdSeconds,
      savingsAdsPerBreak: savingsAdsPerBreak ?? this.savingsAdsPerBreak,
      savingsAdsCpm: savingsAdsCpm ?? this.savingsAdsCpm,
      savingsArtistPayoutPerStream:
          savingsArtistPayoutPerStream ?? this.savingsArtistPayoutPerStream,
    );
  }

  /// Clamps user input into the documented ranges.
  PlaybackSettings sanitized() {
    return copyWith(
      crossfadeSeconds: crossfadeSeconds.clamp(0.0, 12.0).toDouble(),
      cacheMaxMegabytes: math.max(128, cacheMaxMegabytes),
      cacheMaxIdleDays: math.max(1, cacheMaxIdleDays),
      savingsPremiumMonthlyCost: savingsPremiumMonthlyCost.clamp(0.0, 100.0),
      savingsAdBreakMinutes: savingsAdBreakMinutes.clamp(0.5, 120.0),
      savingsAdSeconds: savingsAdSeconds.clamp(0.0, 600.0),
      savingsAdsPerBreak: savingsAdsPerBreak.clamp(0.0, 10.0),
      savingsAdsCpm: savingsAdsCpm.clamp(0.0, 200.0),
      savingsArtistPayoutPerStream:
          savingsArtistPayoutPerStream.clamp(0.0, 1.0),
      eqBands: _normalizeBands(eqBands),
      customEqPresets: _normalizeCustomPresets(customEqPresets),
    );
  }

  /// Keeps saved presets usable: bounded count, unique ids, clamped gains.
  ///
  /// A hand-edited settings file, or one written by an older build, must not be
  /// able to hand the EQ a preset with forty bands of 900 dB.
  static List<CustomEqPreset> _normalizeCustomPresets(
    List<CustomEqPreset> presets,
  ) {
    final seen = <String>{};
    final out = <CustomEqPreset>[];
    for (final preset in presets) {
      if (preset.id.isEmpty || !seen.add(preset.id)) continue;
      final gains = <double>[
        for (var i = 0; i < defaultBands.length; i++)
          i < preset.gains.length
              ? preset.gains[i].clamp(-12.0, 12.0).toDouble()
              : 0.0,
      ];
      out.add(
        CustomEqPreset(
          id: preset.id,
          name: preset.name.trim().isEmpty
              ? 'Custom'
              : preset.name.trim(),
          gains: gains,
        ),
      );
      if (out.length >= 50) break;
    }
    return List<CustomEqPreset>.unmodifiable(out);
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
    'customEqPresets': customEqPresets.map((p) => p.toJson()).toList(),
    'audioQuality': audioQuality.name,
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
    'showYouTubeInSearch': showYouTubeInSearch,
    'savingsPremiumMonthlyCost': savingsPremiumMonthlyCost,
    'savingsAdBreakMinutes': savingsAdBreakMinutes,
    'savingsAdSeconds': savingsAdSeconds,
    'savingsAdsPerBreak': savingsAdsPerBreak,
    'savingsAdsCpm': savingsAdsCpm,
    'savingsArtistPayoutPerStream': savingsArtistPayoutPerStream,
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
      customEqPresets: <CustomEqPreset>[
        for (final p in (j['customEqPresets'] as List? ?? const <dynamic>[]))
          if (p is Map) CustomEqPreset.fromJson(Map<String, dynamic>.from(p)),
      ],
      audioQuality: AudioQuality.values.firstWhere(
        (v) => v.name == j['audioQuality'],
        orElse: () => AudioQuality.balanced,
      ),
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
      showYouTubeInSearch: j['showYouTubeInSearch'] as bool? ?? true,
      savingsPremiumMonthlyCost:
          (j['savingsPremiumMonthlyCost'] as num?)?.toDouble() ?? 12.99,
      savingsAdBreakMinutes:
          (j['savingsAdBreakMinutes'] as num?)?.toDouble() ?? 12.0,
      savingsAdSeconds: (j['savingsAdSeconds'] as num?)?.toDouble() ?? 30.0,
      savingsAdsPerBreak: (j['savingsAdsPerBreak'] as num?)?.toDouble() ?? 1.0,
      savingsAdsCpm: (j['savingsAdsCpm'] as num?)?.toDouble() ?? 20.0,
      savingsArtistPayoutPerStream:
          (j['savingsArtistPayoutPerStream'] as num?)?.toDouble() ?? 0.004,
    ).sanitized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSettings &&
          other.eqEnabled == eqEnabled &&
          other.eqPreset == eqPreset &&
          other.audioQuality == audioQuality &&
          _customPresetsEqual(other.customEqPresets, customEqPresets) &&
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
          other.showYouTubeInSearch == showYouTubeInSearch &&
          other.savingsPremiumMonthlyCost == savingsPremiumMonthlyCost &&
          other.savingsAdBreakMinutes == savingsAdBreakMinutes &&
          other.savingsAdSeconds == savingsAdSeconds &&
          other.savingsAdsPerBreak == savingsAdsPerBreak &&
          other.savingsAdsCpm == savingsAdsCpm &&
          other.savingsArtistPayoutPerStream ==
              savingsArtistPayoutPerStream &&
          _bandsEqual(other.eqBands, eqBands);

  static bool _customPresetsEqual(
    List<CustomEqPreset> a,
    List<CustomEqPreset> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].name != b[i].name) return false;
      if (a[i].gains.join(',') != b[i].gains.join(',')) return false;
    }
    return true;
  }

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
  int get hashCode => Object.hashAll(<Object?>[
    eqEnabled,
    eqPreset,
    eqBands.length,
    customEqPresets.length,
    audioQuality,
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
    showYouTubeInSearch,
    savingsPremiumMonthlyCost,
    savingsAdBreakMinutes,
    savingsAdSeconds,
    savingsAdsPerBreak,
    savingsAdsCpm,
    savingsArtistPayoutPerStream,
  ]);
}
