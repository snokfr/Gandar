import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/theme_engine.dart';
import '../../data/lyrics/lyrics_source.dart';
import '../../domain/models/track.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// The words to a track, highlighted as they are sung when the source has
/// timestamps.
///
/// The highlight follows [position], which is the player's own clock rather
/// than a timer of its own, so seeking, pausing and a stream that starts late
/// all stay in step without any correcting logic.
///
/// [scrollable] is a decision the caller has to make, not a detail: this widget
/// keeps the active line in view by scrolling *itself*, and a scroll view
/// nested inside another one is how a UI ends up eating the user's drags in
/// both directions. The lyrics sheet gives it a bounded height and lets it
/// scroll; the now-playing sheet, which is already a scrollable, sets it false
/// and gets highlighting without the inner scrolling.
class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.position,
    this.scrollable = true,
    this.activeAlignment = 0.42,
  });

  final Lyrics lyrics;

  /// Live playback position. Highlighting follows it.
  final ValueListenable<Duration> position;

  final bool scrollable;

  /// Where in the viewport the active line is parked, 0 = top.
  final double activeAlignment;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  late List<LyricLine> _lines;
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  final ScrollController _scroll = ScrollController();
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _lines = widget.lyrics.timedLines;
    _active = activeLineIndex(_lines, widget.position.value);
    widget.position.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (!identical(old.position, widget.position)) {
      old.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
    }
    if (old.lyrics.synced != widget.lyrics.synced) {
      // A different track: re-parse and forget where the old one had scrolled
      // to, or the new lyrics open halfway down.
      _lines = widget.lyrics.timedLines;
      _lineKeys.clear();
      _active = activeLineIndex(_lines, widget.position.value);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition() {
    if (_lines.isEmpty || !mounted) return;
    final next = activeLineIndex(_lines, widget.position.value);
    // Position ticks many times a second; only a line change is worth a
    // rebuild, so the common case costs a binary search and nothing else.
    if (next == _active) return;
    setState(() => _active = next);
    if (widget.scrollable) _revealActive();
  }

  void _revealActive() {
    final context = _lineKeys[_active]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: widget.activeAlignment,
      duration: Motion.prefersReducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_lines.isEmpty) {
      // No timestamps: the words are still the point, and pretending to
      // highlight them would be worse than showing them plainly.
      final words = SelectableText(
        widget.lyrics.plain,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
      );
      if (!widget.scrollable) return words;
      return SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.only(right: 4),
        child: words,
      );
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < _lines.length; index++) _buildLine(index),
      ],
    );

    if (!widget.scrollable) return column;
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 4),
      child: column,
    );
  }

  Widget _buildLine(int index) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final line = _lines[index];
    // Stable per line, so the view can scroll to it without rebuilding the
    // whole list, and reused across rebuilds because the key is kept in a map.
    final key = _lineKeys[index] ??= GlobalKey();
    final isActive = index == _active;
    final isPast = index < _active;

    final color = isActive
        ? tokens.accentColor
        : isPast
        ? tokens.textSecondaryColor.withValues(alpha: 0.5)
        : tokens.textSecondaryColor;

    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: AnimatedDefaultTextStyle(
        duration: Motion.adaptiveDuration(
          context,
          full: const Duration(milliseconds: 180),
          reduced: Duration.zero,
        ),
        curve: Curves.easeOut,
        style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
          height: 1.35,
          color: color,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
        child: Text(
          // An empty line is a gap the LRC marked deliberately — an
          // instrumental break, or a pause before a chorus. Showing it as a
          // bare dot keeps the highlight moving through it instead of the
          // highlight appearing to stick on nothing.
          line.isBlank ? '•' : line.text,
          textAlign: TextAlign.start,
        ),
      ),
    );
  }
}

/// Opens the lyrics for [track] over the current screen.
///
/// This is what the button on the playback bar does. It is a sheet rather than
/// a page because the words are wanted *while* the song plays, next to the
/// transport controls rather than instead of them.
Future<void> showLyricsSheet(BuildContext context, Track track) {
  final duration = Motion.adaptiveDuration(
    context,
    full: const Duration(milliseconds: 320),
    reduced: const Duration(milliseconds: 120),
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    transitionAnimationController: AnimationController(
      vsync: Navigator.of(context),
      duration: duration,
    ),
    builder: (_) => LyricsSheet(track: track),
  );
}

/// The lyrics of one track, with the current line highlighted where the source
/// is time-synced.
class LyricsSheet extends ConsumerWidget {
  const LyricsSheet({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.gandarTokens;
    final theme = Theme.of(context);
    // The player's own clock, so a seek moves the highlight with the audio.
    final position = ref.watch(playbackControllerProvider).positionNotifier;
    final height = MediaQuery.sizeOf(context).height * 0.78;

    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.backgroundSecondaryColor,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.radiusLg),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  AlbumArt(url: track.artworkUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          track.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.borderColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ref
                    .watch(lyricsProvider(track))
                    .when(
                      loading: () => const Center(
                        child: SizedBox(
                          width: 120,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      ),
                      error: (error, _) => Center(
                        child: Text(
                          'Could not load lyrics: $error',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      data: (lyrics) =>
                          _LyricsBody(lyrics: lyrics, position: position),
                    ),
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 12),
          ],
        ),
      ),
    );
  }
}

class _LyricsBody extends StatelessWidget {
  const _LyricsBody({required this.lyrics, required this.position});

  final Lyrics? lyrics;
  final ValueListenable<Duration> position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final value = lyrics;

    if (value == null || (value.isEmpty && !value.hasSynced)) {
      return Center(
        child: EmptyState(
          icon: Icons.lyrics_outlined,
          title: value?.instrumental ?? false
              ? 'This track is instrumental'
              : 'No lyrics for this track',
          message: value?.instrumental ?? false
              ? 'There is nothing to show, and nothing is missing.'
              : 'LRCLIB has none for this one, which is a normal answer for '
                    'a lot of a large library rather than a failure.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value.hasSynced)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Synced — the current line follows the song',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondaryColor,
              ),
            ),
          ),
        Expanded(
          child: SyncedLyricsView(lyrics: value, position: position),
        ),
        if (value.attribution.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Lyrics from ${value.attribution}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondaryColor,
              ),
            ),
          ),
      ],
    );
  }
}
