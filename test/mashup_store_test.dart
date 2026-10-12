import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/mashup/mashup_store.dart';
import 'package:gandar/domain/models/mashup.dart';
import 'package:gandar/domain/models/track.dart';

const Track _a = Track(
  id: 'a',
  title: 'One',
  artists: <String>['Artist'],
  album: 'Album',
  durationMs: 180000,
);

const Track _b = Track(
  id: 'b',
  title: 'Two',
  artists: <String>['Other'],
  durationMs: 240000,
);

/// The arrangement that only a mashup file can carry: two slices, their own
/// entry points, and different levels.
final Mashup _mix = Mashup(
  blend: const Duration(seconds: 6),
  parts: const <MashupPart>[
    MashupPart(
      track: _a,
      start: Duration(seconds: 35),
      end: Duration(seconds: 41),
      offset: Duration.zero,
      gain: 0.8,
    ),
    MashupPart(
      track: _b,
      start: Duration(minutes: 1, seconds: 5),
      end: Duration(minutes: 1, seconds: 25),
      offset: Duration(seconds: 5),
      gain: 0.55,
    ),
  ],
);

void main() {
  late Directory directory;
  late MashupStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('gandar-mashup-store');
    store = MashupStore(directory: directory);
  });
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('a saved mashup comes back slice for slice, not re-arranged', () async {
    await store.save('Late night', _mix);

    final saved = await store.list();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Late night');

    final reopened = saved.single.mashup;
    expect(reopened.blend, const Duration(seconds: 6));
    expect(reopened.parts, hasLength(2));

    final first = reopened.parts.first;
    expect(first.track.id, 'a');
    expect(first.track.title, 'One');
    expect(first.start, const Duration(seconds: 35));
    expect(first.end, const Duration(seconds: 41));
    expect(first.offset, Duration.zero);
    expect(first.gain, closeTo(0.8, 0.0001));

    final second = reopened.parts[1];
    expect(second.track.id, 'b');
    expect(second.offset, const Duration(seconds: 5));
    expect(second.gain, closeTo(0.55, 0.0001));
    expect(
      second.offset,
      const Duration(seconds: 5),
      reason: 'a part is put back where it was placed, not where a blend would '
          'have put it',
    );
  });

  test('a mashup written under a name replaces the one already there', () async {
    await store.save('Morning', _mix);
    await store.save('Morning', Mashup(parts: <MashupPart>[_mix.parts.first]));

    final saved = await store.list();
    expect(saved, hasLength(1));
    expect(saved.single.mashup.parts, hasLength(1));
  });

  test('two mashups are two files, and the newest is listed first', () async {
    await store.save('One mix', _mix);
    // The stored time is what orders the list, and two saves inside the same
    // millisecond would make that order a coin toss.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.save('Another mix', _mix);

    final saved = await store.list();
    expect(saved.map((s) => s.name), <String>['Another mix', 'One mix']);
  });

  test('deleting removes that mashup and leaves the others alone', () async {
    await store.save('Keep me', _mix);
    await store.save('Delete me', _mix);

    expect(await store.delete('Delete me'), isTrue);
    expect(await store.delete('Delete me'), isFalse);

    final saved = await store.list();
    expect(saved.map((s) => s.name), <String>['Keep me']);
  });

  test('a name that cannot be a file name is made into one', () async {
    expect(MashupStore.safeName('AC/DC vs. Queen'), 'AC-DC vs. Queen');
    expect(MashupStore.safeName('  spaced  out  '), 'spaced out');
    expect(MashupStore.safeName('trailing dots...'), 'trailing dots');
    expect(MashupStore.safeName('///'), '-');
    expect(MashupStore.safeName('   '), 'mashup');

    // And the round trip still finds it, because the file name is kept with
    // the file rather than recomputed on the way back in.
    await store.save('AC/DC vs. Queen', _mix);
    final saved = await store.list();
    expect(saved.single.name, 'AC/DC vs. Queen');
  });

  test('a file that is not a mashup is skipped, not thrown at the user', () async {
    await store.save('Good', _mix);
    File('${directory.path}${Platform.pathSeparator}broken.json')
        .writeAsStringSync('{ not json');
    File('${directory.path}${Platform.pathSeparator}empty.json')
        .writeAsStringSync('{"name":"Empty","parts":[]}');

    final saved = await store.list();
    expect(saved.map((s) => s.name), <String>['Good']);
  });

  test('an arrangement with no parts is not a mashup to reopen', () async {
    await store.save('Empty', Mashup.empty);

    expect(
      await store.list(),
      isEmpty,
      reason: 'a listing that opens an empty screen is worse than no listing',
    );
  });
}
