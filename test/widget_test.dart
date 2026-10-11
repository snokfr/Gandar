import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/theme/theme_engine.dart';
import 'package:gandar/core/theme/theme_presets.dart';
import 'package:gandar/core/theme/theme_tokens.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/features/player/player_surface.dart';
import 'package:gandar/widgets/common.dart';

Widget _wrap(Widget child, {ThemeTokens? tokens}) {
  final theme = tokens ?? ThemePresets.spotifyClassic;
  return MaterialApp(
    theme: ThemeEngine.build(theme),
    home: Scaffold(body: child),
  );
}

const _track = Track(
  id: 't1',
  title: 'Midnight Drive',
  artists: ['Neon Owls', 'Guest'],
  album: 'Night',
  durationMs: 210000,
);

void main() {
  group('formatDuration', () {
    test('formats minutes and seconds', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    });

    test('formats hours when present', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  testWidgets('GandarLogo renders the wordmark', (tester) async {
    await tester.pumpWidget(_wrap(const GandarLogo()));
    expect(find.text('Gandar'), findsOneWidget);
  });

  testWidgets('TrackTile shows the title and joined artists', (tester) async {
    await tester.pumpWidget(_wrap(const TrackTile(track: _track)));

    expect(find.text('Midnight Drive'), findsOneWidget);
    expect(find.text('Neon Owls, Guest'), findsOneWidget);
  });

  testWidgets('TrackTile invokes onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(TrackTile(track: _track, onTap: () => taps++)),
    );
    await tester.tap(find.byType(ListTile));
    expect(taps, 1);
  });

  testWidgets('EmptyState shows its title, message and action', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmptyState(
          icon: Icons.library_music_outlined,
          title: 'Your library is empty',
          message: 'Import a library file to begin.',
          action: FilledButton(onPressed: null, child: Text('Import music')),
        ),
      ),
    );

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Import a library file to begin.'), findsOneWidget);
    expect(find.text('Import music'), findsOneWidget);
  });

  testWidgets('SectionHeader shows title, subtitle and action', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SectionHeader(
          title: 'Liked Songs',
          subtitle: '128 tracks',
          action: Icon(Icons.play_arrow),
        ),
      ),
    );
    expect(find.text('Liked Songs'), findsOneWidget);
    expect(find.text('128 tracks'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('SettingSliderTile reports the formatted value', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SettingSliderTile(
          title: 'Crossfade',
          value: 6,
          min: 0,
          max: 12,
          divisions: 12,
          valueLabel: (v) => '${v.toStringAsFixed(0)} s',
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Crossfade'), findsOneWidget);
    expect(find.text('6 s'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('the earthy theme applies its warm palette', (tester) async {
    await tester.pumpWidget(
      _wrap(const GandarLogo(), tokens: ThemePresets.earthyBrown),
    );
    final context = tester.element(find.byType(GandarLogo));
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      ThemePresets.earthyBrown.backgroundPrimaryColor,
    );
  });
}
