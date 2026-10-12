import 'dart:convert';
import 'dart:io';

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
/// process can open Discord's pipe at all, whether Discord accepts the activity,
/// and whether the art assets resolve — cannot be checked by reading the code.
/// `dart:io` cannot open a named pipe (`File.open` asks for `OPEN_ALWAYS`, which
/// a pipe rejects with error 31), so the transport goes through `dart:ffi`, and
/// this is what proves that path works.
///
/// What it prints is the *answers*, not a frame count. Discord replies to every
/// command with the activity it accepted, and that echo is where an image key
/// either comes back resolved to an id or is silently missing because the asset
/// was never uploaded. Those replies are matched to the command that asked for
/// them, so they never appear on [DiscordIpc.messages]; a test that only counted
/// messages would report an empty list against a perfectly working connection.
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

      // Frames that are *not* the answer to a command. READY arrives during
      // connect and is consumed there, so anything that lands here is a ping or
      // a push.
      final unsolicited = <String>[];
      final sub = client.messages.listen(
        (m) => unsolicited.add('${m.event ?? m.command ?? m.opcode}'),
      );
      addTearDown(sub.cancel);

      expect(client.isOpen, isTrue);

      final track = Track(
        id: 'live',
        title: 'Posed 2',
        artists: const <String>['sxprano'],
        album: 'Topic',
      );

      // A playing track, with a real timer.
      final playing = DiscordPresence.build(
        enabled: true,
        showTrack: true,
        showAppTime: true,
        track: track,
        isPlaying: true,
        position: const Duration(seconds: 13),
        duration: const Duration(minutes: 2, seconds: 32),
        lifetime: const Duration(hours: 12, minutes: 30),
      );

      // Sent through [DiscordIpc.send] rather than [setActivity] because the
      // reply *is* the check. An answer that never arrives is the signature of a
      // Discord client that accepted the connection and then stopped talking —
      // one sitting on an error screen does exactly that — and that is a
      // different problem from a protocol bug, which is what this test is for.
      final answer = await client.send('SET_ACTIVITY', <String, Object?>{
        'pid': pid,
        'activity': playing,
      });

      expect(
        answer,
        isNotNull,
        reason:
            'Discord took the connection but never answered SET_ACTIVITY. The '
            'activity may not be showing. A Discord client on an error screen '
            'behaves exactly like this.',
      );
      expect(
        answer!.event,
        isNot('ERROR'),
        reason: 'Discord rejected the activity: ${jsonEncode(answer.payload)}',
      );

      final data = answer.payload['data'] as Map?;
      final assets = data?['assets'] as Map?;
      final largeImage = assets?['large_image'];
      final smallImage = assets?['small_image'];

      // ignore: avoid_print
      print('LIVE: accepted as ${data?['name']} (${data?['application_id']})');
      // ignore: avoid_print
      print('LIVE: asset keys Discord kept: ${assets?.keys.toList()}');
      // ignore: avoid_print
      print('LIVE: resolved large_image=$largeImage small_image=$smallImage');

      // Discord replaces each known key with the asset's id, so an id here means
      // that file is uploaded and matching. A missing key means Discord did not
      // recognise it and is drawing the activity without a picture.
      expect(
        largeImage,
        isNotNull,
        reason:
            'Discord dropped large_image "${DiscordPresence.appAsset}": that '
            'asset is not uploaded to the application (Art Assets), or is '
            'named differently. See docs/discord.md.',
      );
      expect(smallImage, isNotNull, reason: 'Discord dropped small_image.');

      // Give Discord a moment to render it before the state changes.
      await Future<void>.delayed(const Duration(seconds: 6));

      // Paused, which must drop the timer rather than leave it counting. Sent
      // through the real API, so the production path is exercised too.
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

      // Cleared, the way closing the app or switching the toggle off does: a
      // null activity, which Discord acknowledges with a null in return.
      final cleared = await client.send('SET_ACTIVITY', <String, Object?>{
        'pid': pid,
        'activity': null,
      });
      expect(cleared, isNotNull, reason: 'Discord did not answer the clear');
      expect(
        cleared!.payload['data'],
        isNull,
        reason: 'the activity should be gone: ${jsonEncode(cleared.payload)}',
      );

      expect(
        client.isOpen,
        isTrue,
        reason: 'Discord should still be connected',
      );
      // ignore: avoid_print
      print('LIVE: unsolicited frames: ${unsolicited.join(', ')}');
    },
    skip: _live
        ? false
        : 'needs a running Discord client; run with --dart-define=LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
