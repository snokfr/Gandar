import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/discord/discord_ipc.dart';
import 'package:gandar/data/discord/discord_presence.dart';
import 'package:gandar/domain/models/track.dart';

Track _track({
  String title = 'Posed 2',
  List<String> artists = const <String>['sxprano'],
  String? album = 'Topic',
}) => Track(id: 'abc', title: title, artists: artists, album: album);

void main() {
  group('frame codec', () {
    test('writes an 8-byte little-endian header before the JSON', () {
      final frame = encodeDiscordFrame(
        DiscordOpcode.handshake,
        <String, Object?>{'v': 1, 'client_id': '123'},
      );

      final view = ByteData.view(frame.buffer);
      expect(view.getUint32(0, Endian.little), DiscordOpcode.handshake);
      expect(view.getUint32(4, Endian.little), frame.length - 8);

      final body = jsonDecode(utf8.decode(frame.sublist(8))) as Map;
      expect(body['v'], 1);
      expect(body['client_id'], '123');
    });

    test('the declared length is bytes, not characters', () {
      // A multi-byte payload is the case that catches a length written from
      // `String.length`: Discord reads the header literally and would cut the
      // JSON in half.
      const title = 'Café — déjà vu 🌙';
      final frame = encodeDiscordFrame(DiscordOpcode.frame, <String, Object?>{
        'details': title,
      });

      final declared = ByteData.view(frame.buffer).getUint32(4, Endian.little);
      expect(declared, frame.length - 8);
      expect(declared, greaterThan(title.length));
      expect(jsonDecode(utf8.decode(frame.sublist(8))), <String, Object?>{
        'details': title,
      });
    });

    test('reads back the header it wrote', () {
      final frame = encodeDiscordFrame(DiscordOpcode.ping, <String, Object?>{
        'x': 1,
      });
      final header = decodeDiscordHeader(frame);
      expect(header.opcode, DiscordOpcode.ping);
      expect(header.length, frame.length - 8);
    });

    test('a short header is rejected rather than misread', () {
      expect(
        () => decodeDiscordHeader(Uint8List.fromList(<int>[1, 0, 0])),
        throwsArgumentError,
      );
    });
  });

  group('presence payload', () {
    final now = DateTime(2026, 10, 11, 12);

    test('nothing is sent at all when the feature is off', () {
      final activity = DiscordPresence.build(
        enabled: false,
        showTrack: true,
        showAppTime: true,
        track: _track(),
        isPlaying: true,
      );
      expect(activity, isNull);
    });

    test('an idle client says so instead of showing a stale song', () {
      final activity = DiscordPresence.build(
        enabled: true,
        showTrack: true,
        showAppTime: false,
        isPlaying: false,
      )!;
      expect(activity['details'], DiscordPresence.idleText);
      expect(activity.containsKey('state'), isFalse);
      expect(activity.containsKey('timestamps'), isFalse);
      final assets = activity['assets']! as Map;
      expect(assets['large_image'], DiscordPresence.appAsset);
      expect(assets['large_text'], 'Gandar');
    });

    test('a playing track maps onto details, state and assets', () {
      final activity = DiscordPresence.build(
        enabled: true,
        showTrack: true,
        showAppTime: false,
        track: _track(),
        isPlaying: true,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 3, seconds: 30),
        now: now,
      )!;

      expect(activity['details'], 'Posed 2');
      expect(activity['state'], 'sxprano');
      final assets = activity['assets']! as Map;
      expect(assets['large_image'], DiscordPresence.appAsset);
      expect(assets['large_text'], 'Topic');
      expect(assets['small_image'], DiscordPresence.playingAsset);

      // The timer is anchored to when the track started, so Discord's own clock
      // lines up with ours without another message.
      final stamps = activity['timestamps']! as Map;
      expect(
        stamps['start'],
        now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
      expect(
        stamps['end'],
        now.add(const Duration(minutes: 2, seconds: 30)).millisecondsSinceEpoch,
      );
    });

    test(
      'a paused track shows no timer, because Discord would keep counting',
      () {
        final activity = DiscordPresence.build(
          enabled: true,
          showTrack: true,
          showAppTime: false,
          track: _track(),
          isPlaying: false,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 3),
          now: now,
        )!;
        expect(activity.containsKey('timestamps'), isFalse);
        final assets = activity['assets']! as Map;
        expect(assets['small_image'], DiscordPresence.pausedAsset);
      },
    );

    test('hiding the track keeps the profile anonymous', () {
      final activity = DiscordPresence.build(
        enabled: true,
        showTrack: false,
        showAppTime: true,
        track: _track(),
        isPlaying: true,
        lifetime: const Duration(hours: 3, minutes: 20),
      )!;
      expect(activity['details'], 'Playing');
      expect(activity.containsKey('state'), isFalse);
      final assets = activity['assets']! as Map;
      expect(assets['small_text'], '3 h 20 m in Gandar');
    });

    test('time in Gandar is only shown once there is some', () {
      String? smallTextFor(Duration lifetime) {
        final activity = DiscordPresence.build(
          enabled: true,
          showTrack: true,
          showAppTime: true,
          track: _track(),
          isPlaying: true,
          lifetime: lifetime,
        )!;
        return (activity['assets']! as Map)['small_text'] as String?;
      }

      expect(smallTextFor(const Duration(seconds: 30)), isNull);
      expect(smallTextFor(const Duration(minutes: 5)), '5 min in Gandar');
      expect(smallTextFor(const Duration(hours: 2)), '2 h in Gandar');
      expect(
        smallTextFor(const Duration(hours: 2, minutes: 5)),
        '2 h 5 m in Gandar',
      );
    });

    test('several artists are joined, and a missing album falls back', () {
      final activity = DiscordPresence.build(
        enabled: true,
        showTrack: true,
        showAppTime: false,
        track: _track(
          artists: const <String>['JACKBOYS', 'Travis Scott', 'Young Thug'],
          album: null,
        ),
        isPlaying: true,
      )!;
      expect(activity['state'], 'JACKBOYS, Travis Scott, Young Thug');
      expect((activity['assets']! as Map)['large_text'], 'Gandar');
    });

    test('an over-long title is clipped, not left to Discord', () {
      final activity = DiscordPresence.build(
        enabled: true,
        showTrack: true,
        showAppTime: false,
        track: _track(title: 'x' * 400),
        isPlaying: true,
      )!;
      final details = activity['details']! as String;
      expect(details.length, 128);
      expect(details.endsWith('…'), isTrue);
    });

    test('describeDuration covers the three shapes the profile shows', () {
      expect(
        DiscordPresence.describeDuration(const Duration(seconds: 42)),
        '42 s',
      );
      expect(
        DiscordPresence.describeDuration(const Duration(minutes: 42)),
        '42 min',
      );
      expect(
        DiscordPresence.describeDuration(const Duration(hours: 4, minutes: 7)),
        '4 h 7 m',
      );
    });
  });
}
