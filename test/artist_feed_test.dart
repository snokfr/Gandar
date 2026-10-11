import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/feed/artist_feed.dart';

/// A channel Atom feed shaped the way YouTube actually serves one, including
/// the namespace prefixes, an escaped ampersand and a metadata block.
const String _feed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
      xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
  <link rel="self" href="http://www.youtube.com/feeds/videos.xml?channel_id=UCabc"/>
  <title>An Artist - Topic</title>
  <entry>
    <id>yt:video:AAAA1111AAA</id>
    <yt:videoId>AAAA1111AAA</yt:videoId>
    <yt:channelId>UCabc</yt:channelId>
    <title>New Song &amp; a Feature</title>
    <link rel="alternate" href="https://www.youtube.com/watch?v=AAAA1111AAA"/>
    <author><name>An Artist</name><uri>https://www.youtube.com/channel/UCabc</uri></author>
    <published>2026-09-30T12:00:00+00:00</published>
    <media:group>
      <media:thumbnail url="https://i4.ytimg.com/vi/AAAA1111AAA/hqdefault.jpg" width="480" height="360"/>
    </media:group>
  </entry>
  <entry>
    <id>yt:video:BBBB2222BBB</id>
    <yt:videoId>BBBB2222BBB</yt:videoId>
    <title>Older Track</title>
    <author><name>An Artist</name></author>
    <published>2026-08-01T09:30:00+00:00</published>
  </entry>
</feed>
''';

void main() {
  group('reading a channel feed', () {
    test('pulls out the video id, title, date and thumbnail', () {
      final videos = YouTubeFeedParser.parse(_feed);

      expect(videos, hasLength(2));
      final first = videos.first;
      expect(first.videoId, 'AAAA1111AAA');
      expect(first.title, 'New Song & a Feature');
      expect(first.channelTitle, 'An Artist');
      expect(first.publishedAt, DateTime.utc(2026, 9, 30, 12));
      expect(
        first.thumbnailUrl,
        'https://i4.ytimg.com/vi/AAAA1111AAA/hqdefault.jpg',
      );
      // Tapping a feed entry has to play that exact video, not search for it.
      expect(first.trackId, 'youtube:AAAA1111AAA');
      expect(first.url, 'https://www.youtube.com/watch?v=AAAA1111AAA');
    });

    test('the feed name comes from the channel, not an entry', () {
      expect(YouTubeFeedParser.feedTitle(_feed), 'An Artist - Topic');
    });

    test('an entry with no thumbnail or author is still usable', () {
      final second = YouTubeFeedParser.parse(_feed)[1];
      expect(second.title, 'Older Track');
      expect(second.thumbnailUrl, isNull);
      expect(second.channelTitle, 'An Artist');
    });

    test('an entry without a video id is skipped, not guessed at', () {
      const broken = '''
<feed>
  <entry><title>No Id Here</title><published>2026-01-01T00:00:00+00:00</published></entry>
  <entry><yt:videoId>GOODVIDEOID</yt:videoId><title>Fine</title></entry>
</feed>
''';
      final videos = YouTubeFeedParser.parse(broken);
      expect(videos.map((v) => v.videoId).toList(), ['GOODVIDEOID']);
    });

    test('an empty or non-feed body produces no entries', () {
      expect(YouTubeFeedParser.parse(''), isEmpty);
      expect(YouTubeFeedParser.parse('<html>blocked</html>'), isEmpty);
    });

    test('entities are decoded, including numeric ones', () {
      expect(YouTubeFeedParser.unescape('Troy &amp; Abed'), 'Troy & Abed');
      expect(YouTubeFeedParser.unescape('&lt;live&gt;'), '<live>');
      expect(YouTubeFeedParser.unescape('don&#39;t'), "don't");
      expect(YouTubeFeedParser.unescape('caf&#xe9;'), 'café');
      // A plain string is returned untouched, which the fast path relies on.
      expect(YouTubeFeedParser.unescape('Nothing to do'), 'Nothing to do');
    });
  });

  group('merging per-artist feeds', () {
    FeedVideo video(String id, {DateTime? at, String artist = 'A'}) =>
        FeedVideo(
          videoId: id,
          title: 'Title $id',
          channelTitle: 'Channel $artist',
          publishedAt: at,
          artist: artist,
        );

    test('is newest first across every artist', () {
      final merged = ArtistFeed.merge(<List<FeedVideo>>[
        <FeedVideo>[
          video('old', at: DateTime(2026, 1, 1), artist: 'A'),
          video('new', at: DateTime(2026, 6, 1), artist: 'A'),
        ],
        <FeedVideo>[video('middle', at: DateTime(2026, 3, 1), artist: 'B')],
      ]);

      expect(merged.map((v) => v.videoId).toList(), <String>[
        'new',
        'middle',
        'old',
      ]);
    });

    test('the same video posted under two names appears once', () {
      final merged = ArtistFeed.merge(<List<FeedVideo>>[
        <FeedVideo>[video('shared', at: DateTime(2026, 1, 1))],
        <FeedVideo>[video('shared', at: DateTime(2026, 1, 2), artist: 'B')],
      ]);

      expect(merged, hasLength(1));
    });

    test('undated entries sort last rather than jumping the queue', () {
      final merged = ArtistFeed.merge(<List<FeedVideo>>[
        <FeedVideo>[video('undated'), video('dated', at: DateTime(2026, 1, 1))],
      ]);

      expect(merged.map((v) => v.videoId).toList(), <String>[
        'dated',
        'undated',
      ]);
    });

    test('an empty merge is empty, and does not throw', () {
      expect(ArtistFeed.merge(<List<FeedVideo>>[]), isEmpty);
      expect(ArtistFeed.merge(<List<FeedVideo>>[<FeedVideo>[]]), isEmpty);
    });
  });
}
