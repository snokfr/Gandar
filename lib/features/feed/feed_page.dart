import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/feed/artist_feed.dart';
import '../../domain/models/track.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Formats how long ago something was published.
String relativeTime(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final reference = now ?? DateTime.now();
  final difference = reference.difference(at);
  if (difference.isNegative || difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} h ago';
  if (difference.inDays < 7) return '${difference.inDays} d ago';
  if (difference.inDays < 35) return '${(difference.inDays / 7).floor()} w ago';
  final month = at.month.toString().padLeft(2, '0');
  final day = at.day.toString().padLeft(2, '0');
  return '${at.year}-$month-$day';
}

/// New uploads from the artists in your library.
///
/// Nothing here is imported or stored: it is read from each artist's public
/// YouTube channel feed, which needs no account, and rebuilt each time it is
/// opened. That is why there is nothing to keep in sync and nothing that can
/// drift out of date — the only state is which channel belongs to which artist,
/// and that is guessed once per session.
class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(topArtistsProvider);
    final feed = ref.watch(artistFeedProvider);
    final controller = ref.watch(playbackControllerProvider);
    final theme = Theme.of(context);

    final watching = artists.asData?.value ?? const <String>[];

    return Scaffold(
      body: feed.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Asking YouTube what your artists have posted…'),
            ],
          ),
        ),
        error: (error, _) => EmptyState(
          icon: Icons.dynamic_feed_outlined,
          title: 'Could not build your feed',
          message:
              '$error\n\nFeeds are read from YouTube, so this one needs a '
              'connection.',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(artistFeedProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
        data: (videos) {
          if (videos.isEmpty) {
            return EmptyState(
              icon: Icons.dynamic_feed_outlined,
              title: watching.isEmpty
                  ? 'Nothing to follow yet'
                  : 'No new uploads found',
              message: watching.isEmpty
                  ? 'Import some music and the feed fills with what those '
                        'artists have posted lately.'
                  : 'Gandar looked for recent uploads from '
                        '${watching.take(3).join(', ')}'
                        '${watching.length > 3 ? ' and ${watching.length - 3} more' : ''} '
                        'and found nothing new. YouTube search is a guess at '
                        'which channel belongs to an artist, so a small or '
                        'unusual name can miss.',
              action: FilledButton.icon(
                onPressed: () => ref.invalidate(artistFeedProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
            );
          }

          final queued = <Track>[for (final video in videos) video.toTrack()];

          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final currentId = controller.currentTrack?.id;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: SectionHeader(
                        title: 'New from your artists',
                        subtitle:
                            '${videos.length} recent uploads from '
                            '${watching.length} '
                            'artist${watching.length == 1 ? '' : 's'}',
                        action: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  ref.invalidate(artistFeedProvider),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                            ),
                            FilledButton.icon(
                              onPressed: () => controller.playTracks(queued),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play all'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        'Read from each artist\'s public YouTube channel, so '
                        'the channel behind a name is a best guess.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverList.builder(
                      itemCount: videos.length,
                      itemBuilder: (context, index) {
                        final video = videos[index];
                        return ListTile(
                          leading: AlbumArt(url: video.thumbnailUrl, size: 56),
                          title: Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: video.trackId == currentId
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (video.channelTitle.isNotEmpty)
                                video.channelTitle,
                              if (video.publishedAt != null)
                                relativeTime(video.publishedAt),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: const Icon(Icons.play_arrow),
                          onTap: () => controller.playTracks(
                            queued,
                            startTrackId: video.trackId,
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Adapts a feed entry into the track model, exactly as search does.
extension on FeedVideo {
  Track toTrack() => Track(
    id: trackId,
    title: title,
    artists: [if (channelTitle.isNotEmpty) channelTitle else 'YouTube'],
    artworkUrl: thumbnailUrl,
  );
}
