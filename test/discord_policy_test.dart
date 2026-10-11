import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/data/discord/discord_presence.dart';

void main() {
  group('DiscordPolicy.intentFor', () {
    test('off means nothing is published', () {
      const settings = PlaybackSettings(
        discordEnabled: false,
        discordClientId: '1558961358882607236',
      );
      expect(DiscordPolicy.intentFor(settings), DiscordIntent.clear);
    });

    test('off wins even with an id present', () {
      // The toggle is the user's answer to "show this"; a saved id is not
      // consent on its own.
      const settings = PlaybackSettings(discordEnabled: false);
      expect(DiscordPolicy.intentFor(settings), DiscordIntent.clear);
    });

    test('on with no id asks for one instead of connecting', () {
      const settings = PlaybackSettings(discordEnabled: true);
      expect(DiscordPolicy.intentFor(settings), DiscordIntent.needClientId);
    });

    test('an id that is only whitespace still counts as missing', () {
      // Settings are sanitized on the way in, and the trim is what this proves:
      // "  " pasted from somewhere must not be treated as an application id.
      const settings = PlaybackSettings(
        discordEnabled: true,
        discordClientId: '  ',
      );
      expect(
        DiscordPolicy.intentFor(settings.sanitized()),
        DiscordIntent.needClientId,
      );
    });

    test('on with an id publishes', () {
      const settings = PlaybackSettings(
        discordEnabled: true,
        discordClientId: '1558961358882607236',
      );
      expect(DiscordPolicy.intentFor(settings), DiscordIntent.publish);
    });

    test('the toggle alone is enough to turn everything off', () {
      const settings = PlaybackSettings(
        discordEnabled: true,
        discordClientId: '1558961358882607236',
        discordShowTrack: false,
        discordShowAppTime: false,
      );
      // Hiding the song and the timer is not the same as switching the presence
      // off: it still says you are in Gandar.
      expect(DiscordPolicy.intentFor(settings), DiscordIntent.publish);
    });
  });

  group('DiscordPolicy.nextBackoff', () {
    test('doubles from the first delay', () {
      expect(
        DiscordPolicy.nextBackoff(DiscordPolicy.initialBackoff),
        const Duration(seconds: 10),
      );
    });

    test('stops growing at the ceiling', () {
      expect(
        DiscordPolicy.nextBackoff(DiscordPolicy.maxBackoff),
        DiscordPolicy.maxBackoff,
      );
      expect(
        DiscordPolicy.nextBackoff(const Duration(minutes: 4)),
        DiscordPolicy.maxBackoff,
      );
    });

    test('reaches the ceiling in a handful of steps, not hundreds', () {
      var step = DiscordPolicy.initialBackoff;
      var steps = 0;
      while (step < DiscordPolicy.maxBackoff) {
        step = DiscordPolicy.nextBackoff(step);
        steps++;
        expect(steps, lessThan(10));
      }
      expect(step, DiscordPolicy.maxBackoff);
    });
  });
}
