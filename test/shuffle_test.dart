import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/playback/queue/playback_queue.dart';
import 'package:gandar/playback/queue/shuffle.dart';

Track t(String id) => Track(id: id, title: id, artists: const ['A']);

void main() {
  group('ShuffleService', () {
    test('off mode preserves the original order exactly', () {
      final items = [for (var i = 0; i < 8; i++) t('$i')];
      final ordered = ShuffleService().order(items, mode: ShuffleMode.off);
      expect(
        ordered.map((e) => e.id).toList(),
        items.map((e) => e.id).toList(),
      );
    });

    test('standard shuffle is a permutation with no lost items', () {
      final items = [for (var i = 0; i < 50; i++) t('$i')];
      final ordered = ShuffleService(random: Random(1))
          .order(items, mode: ShuffleMode.standard);
      expect(ordered.length, items.length);
      expect(ordered.map((e) => e.id).toSet(), items.map((e) => e.id).toSet());
    });

    test('standard shuffle actually reorders a large list', () {
      final items = [for (var i = 0; i < 50; i++) t('$i')];
      final ordered = ShuffleService(random: Random(7))
          .order(items, mode: ShuffleMode.standard);
      const sameOrder = [
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', //
        '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', //
        '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', //
        '30', '31', '32', '33', '34', '35', '36', '37', '38', '39', //
        '40', '41', '42', '43', '44', '45', '46', '47', '48', '49', //
      ];
      expect(ordered.map((e) => e.id).toList(), isNot(sameOrder));
    });

    test(
      'smart shuffle keeps recently played tracks out of the first slots',
      () {
        final items = [for (var i = 0; i < 30; i++) t('$i')];
        final recent = ['0', '1', '2', '3', '4'];

        final ordered = ShuffleService(random: Random(3)).order(
          items,
          mode: ShuffleMode.smart,
          recent: recent,
          idOf: (item) => item.id,
        );

        expect(ordered.length, items.length);
        expect(
          ordered.map((e) => e.id).toSet(),
          items.map((e) => e.id).toSet(),
        );

        const guardDepth = ShuffleService.recentGuardDepth;
        final leading = ordered.take(guardDepth).map((e) => e.id).toSet();
        expect(
          leading.intersection(recent.toSet()),
          isEmpty,
          reason: 'smart shuffle should not lead with recently played tracks',
        );
      },
    );

    test('smart shuffle still returns a valid permutation when everything is'
        ' recent', () {
      final items = [for (var i = 0; i < 4; i++) t('$i')];
      final recent = items.map((e) => e.id).toList();
      final ordered = ShuffleService(random: Random(5)).order(
        items,
        mode: ShuffleMode.smart,
        recent: recent,
        idOf: (item) => item.id,
      );
      expect(ordered.map((e) => e.id).toSet(), items.map((e) => e.id).toSet());
    });
  });

  group('RecentTracker', () {
    test('keeps most-recent-first and caps at capacity', () {
      final tracker = RecentTracker<String>(capacity: 3);
      tracker.record('a');
      tracker.record('b');
      tracker.record('c');
      tracker.record('d');
      expect(tracker.items, ['d', 'c', 'b']);
    });

    test('re-recording moves an id to the front without duplicating', () {
      final tracker = RecentTracker<String>(capacity: 5);
      tracker.record('a');
      tracker.record('b');
      tracker.record('a');
      expect(tracker.items, ['a', 'b']);
    });
  });

  group('PlaybackQueue', () {
    final tracks = [for (var i = 0; i < 5; i++) t('$i')];

    test('empty by default', () {
      final queue = PlaybackQueue();
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
      expect(queue.advance(), isNull);
      expect(queue.rewind(), isNull);
    });

    test('setTracks positions the cursor on the requested track', () {
      final queue = PlaybackQueue()..setTracks(tracks, startTrackId: '3');
      expect(queue.current!.id, '3');
      expect(queue.index, 3);
      expect(queue.next!.id, '4');
      expect(queue.previous!.id, '2');
    });

    test('advance and rewind stop at the ends', () {
      final queue = PlaybackQueue()..setTracks(tracks);
      expect(queue.current!.id, '0');
      expect(queue.rewind(), isNull);
      expect(queue.advance()!.id, '1');
      queue.jumpTo('4');
      expect(queue.advance(), isNull);
    });

    test('jumpTo reports whether the track exists', () {
      final queue = PlaybackQueue()..setTracks(tracks);
      expect(queue.jumpTo('2'), isTrue);
      expect(queue.current!.id, '2');
      expect(queue.jumpTo('nope'), isFalse);
      expect(queue.current!.id, '2');
    });

    test('applyShuffle keeps the currently playing track current', () {
      final queue = PlaybackQueue()..setTracks(tracks);
      queue.jumpTo('2');
      queue.applyShuffle(ShuffleMode.standard);
      expect(queue.current!.id, '2');
      expect(queue.length, tracks.length);
    });

    test('shuffle modes other than off still produce the full track set', () {
      final queue = PlaybackQueue()
        ..setTracks(
          tracks,
          mode: ShuffleMode.smart,
          recentTrackIds: ['0', '1'],
        );
      expect(queue.order.length, tracks.length);
      expect(queue.order.map((e) => e.id).toSet(), {'0', '1', '2', '3', '4'});
    });

    test('clear empties the queue', () {
      final queue = PlaybackQueue()..setTracks(tracks);
      queue.clear();
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
    });
  });
}
