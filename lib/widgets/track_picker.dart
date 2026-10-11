import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme_engine.dart';
import '../domain/models/track.dart';
import '../state/providers.dart';
import 'common.dart';

/// Asks the library for tracks, by search.
///
/// Stays open between taps and reports each pick through [onPick] instead of
/// returning one value, because every use of this is a batch job — filling a
/// playlist, building a mix — and making the user reopen a dialog per song is
/// the kind of small tax that leaves a feature unused.
///
/// [alreadyPicked] seeds the tick marks. The sheet also remembers what it has
/// been told to add during this visit, so the marks stay right without the
/// caller having to feed state back in.
Future<void> showTrackPicker(
  BuildContext context, {
  required String title,
  required ValueChanged<Track> onPick,
  Set<String> alreadyPicked = const <String>{},
  String? hint,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TrackPickerSheet(
      title: title,
      onPick: onPick,
      alreadyPicked: alreadyPicked,
      hint: hint,
    ),
  );
}

class _TrackPickerSheet extends ConsumerStatefulWidget {
  const _TrackPickerSheet({
    required this.title,
    required this.onPick,
    required this.alreadyPicked,
    this.hint,
  });

  final String title;
  final ValueChanged<Track> onPick;
  final Set<String> alreadyPicked;
  final String? hint;

  @override
  ConsumerState<_TrackPickerSheet> createState() => _TrackPickerSheetState();
}

class _TrackPickerSheetState extends ConsumerState<_TrackPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';
  late final Set<String> _picked = <String>{...widget.alreadyPicked};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(likedTracksProvider).asData?.value ?? const [];
    final needle = _query.trim().toLowerCase();
    final matches = needle.isEmpty
        ? library
        : library
              .where(
                (t) =>
                    t.title.toLowerCase().contains(needle) ||
                    t.artists.any((a) => a.toLowerCase().contains(needle)) ||
                    (t.album?.toLowerCase().contains(needle) ?? false),
              )
              .toList(growable: false);

    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SectionHeader(
              title: widget.title,
              subtitle: widget.hint ?? 'Tap a song to add it',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'Search your library',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: library.isEmpty
                ? EmptyState(
                    icon: Icons.library_music_outlined,
                    title: 'Your library is empty',
                    message: 'Import some music first, then pick from it here.',
                  )
                : matches.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing matches',
                    message: 'Try a different word.',
                  )
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final track = matches[index];
                      final already = _picked.contains(track.id);
                      return TrackTile(
                        track: track,
                        trailing: Icon(
                          already
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          color: already
                              ? context.gandarTokens.accentColor
                              : null,
                        ),
                        onTap: () =>
                            _pick(track, already: already, theme: theme),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _pick(Track track, {required bool already, required ThemeData theme}) {
    final messenger = ScaffoldMessenger.of(context);
    if (already) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('"${track.title}" is already in there.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _picked.add(track.id));
    widget.onPick(track);
  }
}
