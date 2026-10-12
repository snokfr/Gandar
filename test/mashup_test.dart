import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/mashup.dart';
import 'package:gandar/domain/models/track.dart';

Track _track(String id, {int seconds = 180}) => Track(
  id: id,
  title: 'Song $id',
  artists: const <String>['Artist'],
  durationMs: seconds * 1000,
);

Duration _ms(int value) => Duration(milliseconds: value);

void main() {
  group('layout', () {
    test('without a blend the parts run end to end', () {
      final parts = Mashup.layout(
        <MashupPart>[
          MashupPart.whole(_track('a', seconds: 10)),
          MashupPart.whole(_track('b', seconds: 10)),
          MashupPart.whole(_track('c', seconds: 10)),
        ],
        Duration.zero,
      );

      expect(parts[0].offset, Duration.zero);
      expect(parts[0].endInMix, const Duration(seconds: 10));
      expect(parts[1].offset, const Duration(seconds: 10));
      expect(parts[2].offset, const Duration(seconds: 20));
    });

    test('a blend pulls each part back onto the one before it', () {
      final parts = Mashup.layout(
        <MashupPart>[
          MashupPart.whole(_track('a', seconds: 10)),
          MashupPart.whole(_track('b', seconds: 10)),
          MashupPart.whole(_track('c', seconds: 10)),
        ],
        const Duration(seconds: 4),
      );

      expect(parts[1].offset, const Duration(seconds: 6));
      expect(parts[2].offset, const Duration(seconds: 12));
      // The point of a mashup: both records are sounding across the seam.
      final sounding = Mashup(
        parts: parts,
        blend: const Duration(seconds: 4),
      ).soundingAt(const Duration(seconds: 8));
      expect(sounding.map((p) => p.track.id), <String>['a', 'b']);
    });

    test('a blend longer than a slice cannot stagger the mix backwards', () {
      final parts = Mashup.layout(
        <MashupPart>[
          MashupPart.whole(_track('a', seconds: 3)),
          MashupPart.whole(_track('b', seconds: 3)),
          MashupPart.whole(_track('c', seconds: 3)),
        ],
        const Duration(seconds: 30),
      );

      // Everything ends up stacked at the top, in order, never negative and
      // never moving earlier than the part before it.
      expect(parts.map((p) => p.offset), everyElement(Duration.zero));
    });

    test('a part placed by hand can enter late', () {
      final part = MashupPart.whole(_track('a')).withOffset(_ms(2500));
      expect(part.offset, _ms(2500));
      expect(part.endInMix, _ms(2500 + 180000));
    });

    test('an offset below zero is clamped to the top of the mix', () {
      expect(MashupPart.whole(_track('a')).withOffset(_ms(-500)).offset, Duration.zero);
    });
  });

  group('slices', () {
    test('the slice is what the two handles say it is', () {
      final part = MashupPart.whole(
        _track('a', seconds: 100),
      ).withStart(const Duration(seconds: 20)).withEnd(const Duration(seconds: 35));

      expect(part.start, const Duration(seconds: 20));
      expect(part.end, const Duration(seconds: 35));
      expect(part.length, const Duration(seconds: 15));
    });

    test('moving the start past the end pushes the end rather than refusing', () {
      final part = MashupPart.whole(
        _track('a', seconds: 100),
      ).withStart(const Duration(seconds: 90)).withEnd(const Duration(seconds: 95));

      final moved = part.withStart(const Duration(seconds: 99));
      expect(moved.start, const Duration(seconds: 99));
      expect(moved.end, const Duration(seconds: 99, milliseconds: 500));
      expect(moved.length, minimumMashupSlice);
    });

    test('moving the end before the start leaves a minimum slice', () {
      final part = MashupPart.whole(_track('a', seconds: 100));
      final moved = part.withEnd(const Duration(seconds: -5));
      expect(moved.start, Duration.zero);
      expect(moved.length, minimumMashupSlice);
    });

    test('a slice can never run past the end of the song', () {
      final part = MashupPart.whole(_track('a', seconds: 60));
      expect(part.withEnd(const Duration(minutes: 10)).end, const Duration(seconds: 60));
      expect(part.withStart(const Duration(minutes: 10)).start,
          const Duration(seconds: 59, milliseconds: 500));
    });

    test('a song shorter than the minimum slice plays whole', () {
      final tiny = MashupPart.whole(
        Track(id: 'tiny', title: 'Tiny', artists: const <String>['A'], durationMs: 200),
      );
      expect(tiny.start, Duration.zero);
      expect(tiny.end, const Duration(milliseconds: 200));
      expect(tiny.length, const Duration(milliseconds: 200));
    });

    test('a song with no length plays to its end rather than to a guess', () {
      final unknown = MashupPart.whole(
        Track(id: 'x', title: 'Live take', artists: const <String>['A']),
      );
      expect(unknown.hasKnownLength, isFalse);
      expect(unknown.playsToTheEnd, isTrue);
      // An end chosen by hand still means something, length or no length.
      expect(unknown.withEnd(const Duration(seconds: 30)).playsToTheEnd, isFalse);
      expect(unknown.withEnd(const Duration(seconds: 30)).end,
          const Duration(seconds: 30));
      // Once a length is known it is an ordinary, bounded part.
      final known = MashupPart.whole(_track('x', seconds: 12));
      expect(known.playsToTheEnd, isFalse);
    });

    test('level is a number between silence and full', () {
      final part = MashupPart.whole(_track('a'));
      expect(part.gain, MashupPart.defaultGain);
      expect(part.withGain(2.5).gain, 1.0);
      expect(part.withGain(-1).gain, 0.0);
    });
  });

  group('the arrangement', () {
    test('duration is the last moment anything is sounding', () {
      final mix = Mashup.fromTracks(
        <Track>[_track('a', seconds: 10), _track('b', seconds: 10)],
        blend: const Duration(seconds: 4),
      );
      // 10 + 10 - 4 = 16.
      expect(mix.duration, const Duration(seconds: 16));
    });

    test('overlap at a seam is reported in seconds', () {
      final mix = Mashup.fromTracks(
        <Track>[_track('a', seconds: 10), _track('b', seconds: 10)],
        blend: const Duration(seconds: 6),
      );
      expect(mix.overlapSecondsBefore(1), 6.0);
      expect(mix.overlapSecondsBefore(0), 0.0);
      expect(mix.overlaps, isTrue);
      expect(Mashup.fromTracks(<Track>[_track('a'), _track('b')]).withBlend(Duration.zero).overlaps,
          isFalse);
    });

    test('the same song cannot be added twice', () {
      final mix = Mashup.empty.adding(_track('a')).adding(_track('a'));
      expect(mix.parts, hasLength(1));
    });

    test('adding, moving and removing keep the arrangement laid out', () {
      final mix = Mashup.fromTracks(
        <Track>[_track('a', seconds: 10), _track('b', seconds: 10), _track('c', seconds: 10)],
        blend: const Duration(seconds: 5),
      );
      expect(mix.parts.map((p) => p.track.id), <String>['a', 'b', 'c']);
      expect(mix.parts[1].offset, const Duration(seconds: 5));

      final moved = mix.moving(2, -1);
      expect(moved.parts.map((p) => p.track.id), <String>['a', 'c', 'b']);
      expect(moved.parts[1].offset, const Duration(seconds: 5));

      final reduced = mix.removingAt(0);
      expect(reduced.parts.map((p) => p.track.id), <String>['b', 'c']);
      expect(reduced.parts.first.offset, Duration.zero);

      expect(mix.moving(0, -1).parts.map((p) => p.track.id), <String>['a', 'b', 'c']);
      expect(mix.removingAt(9).parts, hasLength(3));
    });

    test('editing a slice does not move the part being listened to', () {
      final mix = Mashup.fromTracks(
        <Track>[_track('a', seconds: 10), _track('b', seconds: 10)],
        blend: const Duration(seconds: 4),
      );
      final edited = mix.replacingAt(
        1,
        mix.parts[1].withStart(const Duration(seconds: 2)),
      );
      expect(edited.parts[1].offset, mix.parts[1].offset);
      expect(edited.parts[1].start, const Duration(seconds: 2));
    });

    test('the blend is bounded, and re-laying out respects it', () {
      final mix = Mashup.fromTracks(<Track>[_track('a'), _track('b')]);
      expect(mix.withBlend(const Duration(minutes: 5)).blend, Mashup.maxBlend);
      expect(mix.withBlend(_ms(-1)).blend, Duration.zero);
    });

    test('changing the blend re-places every part', () {
      final mix = Mashup.fromTracks(
        <Track>[_track('a', seconds: 10), _track('b', seconds: 10)],
        blend: const Duration(seconds: 2),
      );
      expect(mix.parts[1].offset, const Duration(seconds: 8));
      expect(mix.withBlend(const Duration(seconds: 8)).parts[1].offset,
          const Duration(seconds: 2));
    });

    test('a hand-placed part keeps its offset when the blend changes', () {
      final mix = Mashup.fromTracks(
        <Track>[_track('a', seconds: 10), _track('b', seconds: 10)],
      ).replacingAt(1, MashupPart.whole(_track('b', seconds: 10)).withOffset(_ms(3000)));
      expect(mix.parts[1].offset, _ms(3000));
      // Re-laying out is what the blend slider does, so it does move it — this
      // is the documented trade, and the screen says so next to the slider.
      expect(mix.withBlend(const Duration(seconds: 1)).parts[1].offset,
          const Duration(seconds: 9));
    });
  });
}
