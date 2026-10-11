import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/discord/discord_ipc.dart';
import 'package:gandar/data/discord/discord_presence.dart';
import 'package:gandar/domain/models/track.dart';

/// Live checks against a real, running Discord desktop client.
///
/// Skipped by default: it needs Discord open and signed in, which is true on
/// the developer's machine and false on a build server. Run it deliberately:
///
/// ```bash
/// flutter test --dart-define=LIVE=true \
///   --dart-define=DISCORD_CLIENT_ID=123456789012345678 \
///   test/live/discord_live_test.dart
/// ```
///
/// It exists because the interesting half of Rich Presence — whether a Dart
/// process can open Discord's pipe at all, and whether Discord accepts the
/// activity — cannot be checked by reading the code. `dart:io` cannot open a
/// named pipe (`File.open` asks for `OPEN_ALWAYS`, which a pipe rejects with
/// error 31), so the transport goes through `dart:ffi`, and this is what proves
/// that path works.
const bool _live = bool.fromEnvironment('LIVE');
const String _clientId = String.fromEnvironment('DISCORD_CLIENT_ID');

void main() {
  test(
    'connects to Discord, sets an activity, and clears it',
    () async {
      if (_clientId.isEmpty) {
        fail('pass --dart-define=DISCORD_CLIENT_ID=<application id>');
      }

      late DiscordIpc client;
      try {
        client = await DiscordIpc.connect(clientId: _clientId);
      } on DiscordUnavailable catch (e) {
        fail('could not reach Discord: $e');
      }
      addTearDown(client.close);

      final seen = <String>[];
      final sub = client.messages.listen((m) {
        seen.add('${m.event ?? m.command ?? m.opcode}');
      });
      addTearDown(sub.cancel);

      expect(client.isOpen, isTrue);

      final track = Track(
        id: 'live',
        title: 'Posed 2',
        artists: const <String>['sxprano'],
        album: 'Topic',
      );

      // A playing track, with a real timer.
      await client.setActivity(
        DiscordPresence.build(
          enabled: true,
          showTrack: true,
          showAppTime: true,
          track: track,
          isPlaying: true,
          position: const Duration(seconds: 13),
          duration: const Duration(minutes: 2, seconds: 32),
          lifetime: const Duration(hours: 12, minutes: 30),
        ),
      );

      // Give Discord a moment to render it before the state changes.
      await Future<void>.delayed(const Duration(seconds: 6));

      // Paused, which must drop the timer rather than leave it counting.
      await client.setActivity(
        DiscordPresence.build(
          enabled: true,
          showTrack: true,
          showAppTime: true,
          track: track,
          isPlaying: false,
          lifetime: const Duration(hours: 12, minutes: 30),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 3));

      // Cleared, the way closing the app or switching the toggle off does.
      await client.setActivity(null);
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(
        client.isOpen,
        isTrue,
        reason: 'Discord should still be connected',
      );
      // ignore: avoid_print
      print('LIVE: frames from Discord: ${seen.join(', ')}');
    },
    skip: _live
        ? false
        : 'needs a running Discord client; run with --dart-define=LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
