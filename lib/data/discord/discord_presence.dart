import '../../core/settings/playback_settings.dart';
import '../../domain/models/track.dart';
import '../usage/app_usage.dart';

/// What the presence layer should do next.
///
/// Kept separate from the code that does it because these three answers are the
/// whole of the feature's *policy* — and a policy expressed as a function can
/// be tested without Discord, a socket, or a timer, none of which a unit test
/// has.
enum DiscordIntent {
  /// The feature is off: clear anything shown and drop the connection.
  clear,

  /// On, but with no Application ID, so there is nothing to connect with.
  needClientId,

  /// Make sure there is a connection, then publish the current state.
  publish,
}

/// The rules the presence follows, as pure functions.
abstract final class DiscordPolicy {
  /// First retry delay after Discord cannot be reached.
  static const Duration initialBackoff = Duration(seconds: 5);

  /// Ceiling for the retry delay: a machine with no Discord at all should not
  /// keep asking every five seconds forever.
  static const Duration maxBackoff = Duration(minutes: 5);

  /// What [settings] ask for.
  static DiscordIntent intentFor(PlaybackSettings settings) {
    if (!settings.discordEnabled) return DiscordIntent.clear;
    if (settings.discordClientId.isEmpty) return DiscordIntent.needClientId;
    return DiscordIntent.publish;
  }

  /// The next retry delay: doubled, up to [maxBackoff].
  static Duration nextBackoff(Duration current) {
    final doubled = current * 2;
    return doubled > maxBackoff ? maxBackoff : doubled;
  }
}

/// The activity Gandar shows on a Discord profile.
///
/// Pure, and separated from the socket on purpose: the payload is the part that
/// has rules worth testing — which fields Discord accepts, what an idle client
/// says, and what happens when a toggle is off — while the socket is the part
/// that cannot be tested without Discord running.
///
/// Discord gives an activity exactly four places to put text, so the mapping is
/// a decision rather than a detail:
///
/// | Slot | What goes there |
/// | --- | --- |
/// | `details` | the song |
/// | `state` | the artist |
/// | `assets.large_text` | the album, or `Gandar` when there is none |
/// | `assets.small_text` | time spent in Gandar |
class DiscordPresence {
  const DiscordPresence._();

  /// The asset keys the Discord application must define, in order of
  /// importance. Uploaded on the Developer Portal under Rich Presence → Art
  /// Assets; see `docs/discord.md`.
  static const String appAsset = 'gandar';
  static const String playingAsset = 'playing';
  static const String pausedAsset = 'paused';

  /// The name shown when nothing is playing.
  static const String idleText = 'In Gandar';

  /// Builds the activity payload, or null when nothing should be sent.
  ///
  /// [position] and [duration] drive the progress timer: Discord is told when
  /// the track started, and it counts the elapsed time itself, so a paused
  /// player and a paused song agree without further traffic. [lifetime] is
  /// total time the app has been open, which is the number the user asked to
  /// see on the profile.
  static Map<String, Object?>? build({
    required bool enabled,
    required bool showTrack,
    required bool showAppTime,
    Track? track,
    required bool isPlaying,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    Duration lifetime = Duration.zero,
    DateTime? now,
  }) {
    if (!enabled) return null;

    final hasTrack = showTrack && track != null;
    final details = hasTrack
        ? _text(track.title)
        : (isPlaying ? 'Playing' : idleText);
    final state = hasTrack
        ? _text(
            track.artists.isEmpty ? 'Unknown artist' : track.artists.join(', '),
          )
        : null;

    final largeText = hasTrack ? _text(track.album ?? 'Gandar') : 'Gandar';

    final smallText = showAppTime && lifetime.inMinutes >= 1
        ? _text('${describeDuration(lifetime)} in Gandar')
        : null;

    final activity = <String, Object?>{
      'details': details,
      'state': ?state,
      'assets': <String, Object?>{
        'large_image': appAsset,
        'large_text': largeText,
        if (isPlaying || hasTrack)
          'small_image': isPlaying ? playingAsset : pausedAsset,
        'small_text': ?smallText,
      },
    };

    // A start timestamp without an end is "counting up"; with an end it is a
    // progress bar. Both only make sense while something is playing, because
    // Discord keeps counting on its own and a paused track would drift.
    final timestamps = _timestamps(
      isPlaying: isPlaying,
      hasTrack: hasTrack,
      position: position,
      duration: duration,
      now: now ?? DateTime.now(),
    );
    if (timestamps != null) activity['timestamps'] = timestamps;

    return activity;
  }

  static Map<String, Object?>? _timestamps({
    required bool isPlaying,
    required bool hasTrack,
    required Duration position,
    required Duration duration,
    required DateTime now,
  }) {
    if (!isPlaying || !hasTrack) return null;
    final start = now.subtract(position);
    final timestamps = <String, Object?>{'start': start.millisecondsSinceEpoch};
    if (duration > Duration.zero) {
      timestamps['end'] = start.add(duration).millisecondsSinceEpoch;
    }
    return timestamps;
  }

  /// A string Discord will accept in one of the four text slots.
  ///
  /// Discord truncates long strings, so a 300-character title would be cut
  /// mid-word by the client rather than by us — and Discord's current field
  /// rules say these are **2 to 128 characters**, not "up to 128": a track
  /// called `X` is one character and would have its activity rejected. So a
  /// short value is padded rather than sent as it is, which shows as one extra
  /// space on the profile and keeps the presence working.
  static String _text(String value, {int max = 128, int min = 2}) {
    final trimmed = value.trim();
    final clipped = trimmed.length <= max
        ? trimmed
        : '${trimmed.substring(0, max - 1)}…';
    return clipped.length >= min ? clipped : clipped.padRight(min);
  }

  /// `2 h 14 m`, `45 min`, `30 s`.
  static String describeDuration(Duration d) => describeShortDuration(d);
}
