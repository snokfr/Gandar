import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/lyrics/lyrics_source.dart';

void main() {
  group('LRCLIB payloads', () {
    test('reads plain lyrics', () {
      const body =
          '{"trackName":"x","plainLyrics":"line one\\nline two",'
          '"syncedLyrics":null,"instrumental":false}';
      final lyrics = Lyrics.fromJson(body);

      expect(lyrics, isNotNull);
      expect(lyrics!.plain, 'line one\nline two');
      expect(lyrics.hasSynced, isFalse);
      expect(lyrics.attribution, 'LRCLIB');
    });

    test('derives plain lyrics from synced ones, dropping the timestamps', () {
      const body =
          '{"plainLyrics":null,"instrumental":false,"syncedLyrics":'
          '"[00:12.34] first line\\n[00:15.10] second line\\n"}';
      final lyrics = Lyrics.fromJson(body);

      expect(lyrics!.plain, 'first line\nsecond line');
      expect(lyrics.hasSynced, isTrue);
    });

    test('a payload with neither kind of lyric is "no lyrics"', () {
      expect(
        Lyrics.fromJson('{"plainLyrics":null,"syncedLyrics":null,'
            '"instrumental":false}'),
        isNull,
      );
    });

    test('an instrumental is reported as such, not as a missing lyric', () {
      final lyrics = Lyrics.fromJson(
        '{"plainLyrics":null,"syncedLyrics":null,"instrumental":true}',
      );

      expect(lyrics, isNotNull);
      expect(lyrics!.instrumental, isTrue);
      expect(lyrics.isEmpty, isTrue);
    });

    test('anything that is not a matching JSON object is null, not a throw', () {
      expect(Lyrics.fromJson('<html>blocked'), isNull);
      expect(Lyrics.fromJson('[]'), isNull);
      expect(Lyrics.fromJson('123'), isNull);
    });

    test('LRC metadata tags are not mistaken for words', () {
      const lrc = '[ar:An Artist]\n[ti:A Title]\n[00:01.00] real words\n';
      expect(Lyrics.plainFromLrc(lrc), 'real words');
    });

    test('blank lines and bare timestamps are dropped', () {
      const lrc = '[00:01.00]\n\n[00:02.00] words\n   \n';
      expect(Lyrics.plainFromLrc(lrc), 'words');
    });
  });
}
