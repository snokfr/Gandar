import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/track.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/track_picker.dart';

/// Builds a blended set out of two or more tracks.
///
/// ## What this is, and what it is not
///
/// A player runs one stream at a time, so this cannot layer two songs on top of
/// each other — that needs a mixer with two decoders and a beat grid. What it
/// does instead is the other half of a mashup: it takes the records you chose
/// and plays them as **one continuous set**, crossfading each into the next by
/// an amount you set, with no gaps and no dead air. Choosing a transition longer
/// than a track's tail makes the records overlap audibly, which is where the
/// blended effect comes from.
///
/// Being clear about that matters more than the name: a button labeled "mashup"
/// that silently produced a plain playlist would be a lie.
class MashupPage extends ConsumerStatefulWidget {
  const MashupPage({super.key});

  @override
  ConsumerState<MashupPage> createState() => _MashupPageState();
}

class _MashupPageState extends ConsumerState<MashupPage> {
  final List<Track> _selected = <Track>[];
  double _blendSeconds = 6;

  void _add(Track track) {
    if (_selected.any((t) => t.id == track.id)) return;
    setState(() => _selected.add(track));
  }

  void _remove(Track track) {
    setState(() => _selected.removeWhere((t) => t.id == track.id));
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _selected.length) return;
    setState(() {
      final track = _selected.removeAt(index);
      _selected.insert(target, track);
    });
  }

  /// Plays the selection through the normal queue with the blend applied.
  Future<void> _play() async {
    final settings = ref.read(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    // The blend is the feature, so it turns the two settings it needs on. Said
    // out loud in the snack bar rather than done quietly, because these are the
    // user's playback settings and they outlive this screen.
    await notifier.update(
      settings.copyWith(
        automixEnabled: _blendSeconds > 0,
        crossfadeSeconds: _blendSeconds,
      ),
    );
    await ref.read(playbackControllerProvider).playTracks(_selected);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _blendSeconds > 0
              ? 'Playing as a blend, with a '
                    '${_blendSeconds.toStringAsFixed(0)}s crossfade. Your '
                    'playback settings were changed to match.'
              : 'Playing in order, with no blend.',
        ),
      ),
    );
  }

  /// Saves the selection as a real playlist, so it can be played again.
  Future<void> _saveAsPlaylist() async {
    final name = await promptForName(
      context,
      title: 'Save this mashup',
      action: 'Save',
      hint: 'Late night blend',
    );
    if (name == null || !mounted) return;

    final repository = ref.read(appDependenciesProvider).libraryRepository;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final playlist = await repository.createPlaylist(name);
      for (final track in _selected) {
        await repository.addTrackToPlaylist(playlist.id, track.id);
      }
      ref.invalidate(playlistsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved "$name" as a playlist.'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => context.go('/playlists/${playlist.id}'),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save that: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blend = _blendSeconds;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: SectionHeader(
                title: 'Mashup',
                subtitle:
                    '${_selected.length} '
                    'track${_selected.length == 1 ? '' : 's'} in the blend',
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => showTrackPicker(
                        context,
                        title: 'Add to the mashup',
                        alreadyPicked: <String>{
                          for (final track in _selected) track.id,
                        },
                        onPick: _add,
                      ),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Add songs'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _selected.isEmpty ? null : _play,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play blend'),
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
                'Gandar plays one stream at a time, so this blends tracks into '
                'one continuous set rather than layering two songs at once. '
                'The transition below is how long each record overlaps the next.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: GandarCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingSliderTile(
                      title: 'Blend length',
                      description:
                          'How long one track takes to become the next. '
                          '0 plays them back to back instead.',
                      value: blend,
                      min: 0,
                      max: 12,
                      divisions: 24,
                      valueLabel: (v) =>
                          v == 0 ? 'None' : '${v.toStringAsFixed(1)} s',
                      onChanged: (v) => setState(() => _blendSeconds = v),
                    ),
                    if (_selected.length >= 2)
                      Text(
                        'About '
                        '${(_selected.length - 1) * blend.round()} s of the set '
                        'is transition.',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_selected.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: EmptyState(
                  icon: Icons.motion_photos_on_outlined,
                  title: 'Nothing in the blend yet',
                  message:
                      'Add two or more songs and they will play as one set, '
                      'each fading into the next.',
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: SectionHeader(
                  title: 'The running order',
                  subtitle: 'Reorder or drop anything',
                  action: _selected.length < 2
                      ? null
                      : OutlinedButton.icon(
                          onPressed: _saveAsPlaylist,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Save as playlist'),
                        ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverList.builder(
                itemCount: _selected.length,
                itemBuilder: (context, index) {
                  final track = _selected[index];
                  return TrackTile(
                    track: track,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        AlbumArt(url: track.artworkUrl, size: 44),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Move up',
                          onPressed: index == 0
                              ? null
                              : () => _move(index, -1),
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          tooltip: 'Move down',
                          onPressed: index == _selected.length - 1
                              ? null
                              : () => _move(index, 1),
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _remove(track),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
