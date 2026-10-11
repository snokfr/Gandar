import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/lyrics/lyrics_source.dart';

/// A tiny LRC document covering the shapes a real one mixes together.
const String _lrc = '''
[ar:Someone]
[ti:A Title]
[00:00.00]
[00:12.34] first line
[00:15.10] second line
[01:02.50] a minute in
''';

void main() {
  group('linesFromLrc', () {
    test('parses timestamps into times and words', () {
      final lines = Lyrics.linesFromLrc(_lrc);

      expect(lines, hasLength(4));
      expect(lines[0].at, Duration.zero);
      expect(lines[0].isBlank, isTrue);
      expect(lines[1].at, const Duration(seconds: 12, milliseconds: 340));
      expect(lines[1].text, 'first line');
      expect(
        lines[3].at,
        const Duration(minutes: 1, seconds: 2, milliseconds: 500),
      );
      expect(lines[3].text, 'a minute in');
    });

    test('metadata tags are not lines', () {
      final lines = Lyrics.linesFromLrc('[ar:Someone]\n[ti:A Title]\n');
      expect(lines, isEmpty);
    });

    test('a fraction of one, two or three digits all mean the same time', () {
      // `.5` is half a second, not five milliseconds. Reading the digits as a
      // plain integer puts the line two beats early, which is exactly the kind
      // of bug that looks like "the sync is slightly off".
      final centis = Lyrics.linesFromLrc('[00:01.5] half').single;
      final hundredths = Lyrics.linesFromLrc('[00:01.50] half').single;
      final millis = Lyrics.linesFromLrc('[00:01.500] half').single;

      expect(centis.at, const Duration(seconds: 1, milliseconds: 500));
      expect(hundredths.at, centis.at);
      expect(millis.at, centis.at);
    });

    test('a timestamp with no fraction is whole seconds', () {
      expect(
        Lyrics.linesFromLrc('[00:07] words').single.at,
        const Duration(seconds: 7),
      );
    });

    test('the colon spelling of the fraction is accepted too', () {
      expect(
        Lyrics.linesFromLrc('[00:07:25] words').single.at,
        const Duration(seconds: 7, milliseconds: 250),
      );
    });

    test('one line with several timestamps becomes several lines', () {
      // The chorus, repeated: LRC writes the words once and stamps them where
      // they recur. Dropping the extra stamps would leave one chorus with no
      // highlight anywhere else.
      final lines = Lyrics.linesFromLrc(
        '[00:10.00][00:40.00][01:10.00] chorus',
      );

      expect(lines, hasLength(3));
      expect(lines.map((l) => l.text).toSet(), <String>{'chorus'});
      expect(lines.map((l) => l.at).toList(), <Duration>[
        const Duration(seconds: 10),
        const Duration(seconds: 40),
        const Duration(minutes: 1, seconds: 10),
      ]);
    });

    test('out-of-order timestamps come back sorted', () {
      final lines = Lyrics.linesFromLrc(
        '[00:30.00] later\n[00:10.00] earlier\n',
      );
      expect(lines.map((l) => l.text), <String>['earlier', 'later']);
    });

    test('lines with no timestamp at all are ignored', () {
      final lines = Lyrics.linesFromLrc('just some words\n\n[00:05.00] real\n');
      expect(lines, hasLength(1));
      expect(lines.single.text, 'real');
    });

    test('minutes past 99 are accepted, because some tracks are that long', () {
      expect(
        Lyrics.linesFromLrc('[123:45.67] long').single.at,
        const Duration(minutes: 123, seconds: 45, milliseconds: 670),
      );
    });
  });

  group('activeLineIndex', () {
    final lines = Lyrics.linesFromLrc(_lrc);

    test('nothing is highlighted before the first line', () {
      expect(activeLineIndex(lines, Duration.zero), 0);
      // The first line here is the blank marker at 0:00, so a line that starts
      // later is what proves nothing is highlighted early.
      final offset = Lyrics.linesFromLrc('[00:30.00] late\n');
      expect(activeLineIndex(offset, const Duration(seconds: 20)), -1);
    });

    test('the last line at or before the position wins', () {
      expect(
        activeLineIndex(lines, const Duration(seconds: 13)),
        1,
        reason: 'between "first line" at 12.34 and "second line" at 15.10',
      );
      expect(
        activeLineIndex(lines, const Duration(seconds: 12, milliseconds: 340)),
        1,
      );
      expect(
        activeLineIndex(lines, const Duration(seconds: 15, milliseconds: 99)),
        1,
      );
      expect(
        activeLineIndex(lines, const Duration(seconds: 15, milliseconds: 100)),
        2,
      );
    });

    test('the exact moment a line starts highlights that line', () {
      expect(
        activeLineIndex(
          lines,
          const Duration(minutes: 1, seconds: 2, milliseconds: 500),
        ),
        3,
      );
    });

    test('past the end of the lyrics, the last line stays highlighted', () {
      expect(activeLineIndex(lines, const Duration(minutes: 10)), 3);
    });

    test('an empty lyric list has nothing to highlight', () {
      expect(
        activeLineIndex(const <LyricLine>[], const Duration(seconds: 5)),
        -1,
      );
    });

    test('it agrees with a linear scan over many positions', () {
      // The binary search is the implementation; a straight scan is the
      // definition. They must not disagree anywhere in the range.
      for (var second = 0; second < 90; second++) {
        final position = Duration(seconds: second, milliseconds: 500);
        var expected = -1;
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].at <= position) expected = i;
        }
        expect(
          activeLineIndex(lines, position),
          expected,
          reason: 'at $position',
        );
      }
    });
  });

  group('Lyrics.timedLines', () {
    test('is empty when the source had only plain words', () {
      const lyrics = Lyrics(plain: 'one\ntwo');
      expect(lyrics.timedLines, isEmpty);
      expect(lyrics.hasSynced, isFalse);
    });

    test('is parsed from the synced text when there is one', () {
      const lyrics = Lyrics(
        plain: 'first line',
        synced: '[00:12.34] first line',
      );
      expect(lyrics.hasSynced, isTrue);
      expect(lyrics.timedLines.single.text, 'first line');
    });
  });
}
