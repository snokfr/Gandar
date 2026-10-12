import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_engine.dart';
import '../../data/lyrics/lyrics_source.dart';
import '../../domain/models/mashup.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../player/player_surface.dart' show formatDuration;

/// The words of every part of a mix, in the order they will be heard.
///
/// This is the answer to a question the arrangement itself cannot answer: the
/// timeline says *when* each part plays, and only the lyrics say *what is being
/// sung* there. Putting them side by side is what lets you pick a slice because
/// of the line inside it rather than because of where the slider happened to
/// land.
///
/// Only the lines inside each part's slice are listed. A part is a chosen
/// moment of a song, so the rest of that song's words are not the words this
/// mix is made of — showing all of them would bury the eight lines that matter
/// in eighty that do not. Each line is tappable, and tapping moves the mix to
/// that line.
class MashupWordsCard extends StatelessWidget {
  const MashupWordsCard({
    super.key,
    required this.mashup,
    required this.onJump,
    this.playingIndex,
  });

  final Mashup mashup;

  /// Called with a part's index and a moment *inside that part's own song*.
  final void Function(int index, Duration songTime) onJump;

  /// The part the playhead is inside, when the mix is somewhere in particular.
  final int? playingIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The words', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Every part’s lyrics for the slice it plays. Tap a line to move the '
            'mix to it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < mashup.parts.length; index++)
            _PartWords(
              index: index,
              part: mashup.parts[index],
              playing: playingIndex == index,
              onJump: (songTime) => onJump(index, songTime),
            ),
        ],
      ),
    );
  }
}

class _PartWords extends ConsumerWidget {
  const _PartWords({
    required this.index,
    required this.part,
    required this.playing,
    required this.onJump,
  });

  final int index;
  final MashupPart part;
  final bool playing;
  final ValueChanged<Duration> onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final lyrics = ref.watch(lyricsProvider(part.track));

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Text(
                  part.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: playing ? tokens.accentColor : null,
                  ),
                ),
              ),
              Text(
                part.hasKnownLength
                    ? '${formatDuration(part.start)}–'
                          '${formatDuration(part.end)}'
                    : 'whole song',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: lyrics.when(
              loading: () => Text(
                'Looking up the words…',
                style: theme.textTheme.bodySmall,
              ),
              error: (error, _) => Text(
                'Could not load the words: $error',
                style: theme.textTheme.bodySmall,
              ),
              data: (value) => _Words(
                lyrics: value,
                part: part,
                onJump: onJump,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Words extends StatelessWidget {
  const _Words({
    required this.lyrics,
    required this.part,
    required this.onJump,
  });

  final Lyrics? lyrics;
  final MashupPart part;
  final ValueChanged<Duration> onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final value = lyrics;

    if (value == null || (value.isEmpty && !value.hasSynced)) {
      return Text(
        value?.instrumental ?? false
            ? 'Instrumental — there are no words in this one.'
            : 'No words found for this song.',
        style: theme.textTheme.bodySmall,
      );
    }

    final lines = value.timedLines;
    if (lines.isEmpty) {
      // Words without timestamps are still the words of the part; they just
      // cannot be tapped, and the note says so rather than leaving the reader
      // wondering why nothing happens.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.plain.length > 400
                ? '${value.plain.substring(0, 400)}…'
                : value.plain,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 2),
          Text(
            'These words have no timestamps, so they cannot be jumped to.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textSecondaryColor,
            ),
          ),
        ],
      );
    }

    final inside = <LyricLine>[
      for (final line in lines)
        if (line.at >= part.start && (line.at < part.end || !part.hasKnownLength))
          line,
    ];

    if (inside.isEmpty) {
      return Text(
        'None of the timed lines fall inside this slice — the part is playing '
        'a stretch without words.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in inside) _WordLine(line: line, onJump: onJump),
      ],
    );
  }
}

class _WordLine extends StatelessWidget {
  const _WordLine({required this.line, required this.onJump});

  final LyricLine line;
  final ValueChanged<Duration> onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    return InkWell(
      onTap: () => onJump(line.at),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              child: Text(
                formatDuration(line.at),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondaryColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                line.isBlank ? '•' : line.text,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
