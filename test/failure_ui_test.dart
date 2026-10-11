import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/theme/theme_engine.dart';
import 'package:gandar/core/theme/theme_presets.dart';
import 'package:gandar/data/import/library_file_import.dart';
import 'package:gandar/domain/models/playlist.dart';
import 'package:gandar/features/playlists/playlists_page.dart';
import 'package:gandar/state/providers.dart';
import 'package:gandar/state/retry_policy.dart';

/// What the playlists screen says when the library cannot be read.
///
/// The container is built with the production retry policy, so these tests also
/// cover the wiring that stops an unchangeable answer from being retried
/// forever.

/// A failure a second attempt cannot fix.
LibraryFileException _unreadableStore() =>
    LibraryFileException('library.db could not be opened.');

Widget _page(Object error) => ProviderScope(
  retry: gandarProviderRetry,
  overrides: [playlistsProvider.overrideWith((ref) async => throw error)],
  child: MaterialApp(
    theme: ThemeEngine.build(ThemePresets.spotifyClassic),
    home: const PlaylistsPage(),
  ),
);

void main() {
  testWidgets('an unreadable library is explained without a retry button', (
    tester,
  ) async {
    await tester.pumpWidget(_page(_unreadableStore()));
    await tester.pumpAndSettle();

    expect(find.text('Could not read your playlists'), findsOneWidget);
    expect(
      find.textContaining('could not be opened', findRichText: false),
      findsOneWidget,
    );
    // Retrying a file that cannot be read would be a lie: the answer cannot
    // change, so the button is not offered.
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a transport failure keeps the retry button', (tester) async {
    await tester.pumpWidget(_page(Exception('connection reset')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the explanation survives a small window', (tester) async {
    tester.view.physicalSize = const Size(640, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(_unreadableStore()));
    await tester.pumpAndSettle();

    // A RenderFlex overflow would be reported as a framework exception here.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('could not be opened'), findsOneWidget);
  });

  testWidgets('the empty state points at the import screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: gandarProviderRetry,
        overrides: [
          playlistsProvider.overrideWith((ref) async => const <Playlist>[]),
        ],
        child: MaterialApp(
          theme: ThemeEngine.build(ThemePresets.spotifyClassic),
          home: const PlaylistsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No playlists yet'), findsOneWidget);
    expect(find.text('Import a playlist'), findsOneWidget);
  });

  testWidgets('an imported playlist is listed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: gandarProviderRetry,
        overrides: [
          playlistsProvider.overrideWith(
            (ref) async => const <Playlist>[
              Playlist(id: 'p1', name: 'Late Night', trackCount: 12),
            ],
          ),
        ],
        child: MaterialApp(
          theme: ThemeEngine.build(ThemePresets.spotifyClassic),
          home: const PlaylistsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Late Night'), findsOneWidget);
  });
}
