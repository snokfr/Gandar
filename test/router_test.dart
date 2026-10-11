import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/app/router.dart';
import 'package:go_router/go_router.dart';

/// The router is checked directly rather than through a pumped app: these are
/// questions about the route table (which locations resolve, and which keep the
/// navigation shell), and answering them here keeps the test free of audio
/// engines, databases and frame timings.
void main() {
  late GoRouter router;

  setUp(() => router = buildRouter());
  tearDown(() => router.dispose());

  RouteMatchList match(String location) =>
      router.configuration.findMatch(Uri.parse(location));

  test('every screen the sidebar offers resolves', () {
    for (final path in <String>[
      '/library',
      '/playlists',
      '/search',
      '/import',
      '/themes',
      '/settings',
    ]) {
      expect(match(path).matches, isNotEmpty, reason: '$path should resolve');
      expect(
        match(path).matches.whereType<ShellRouteMatch>(),
        isNotEmpty,
        reason: '$path should keep the navigation rail visible',
      );
    }
  });

  test('importing is a first-class screen, not a corner of Settings', () {
    final matches = match('/import').matches;

    expect(matches, isNotEmpty);
    // Inside the shell, so the player bar and the rail stay put while the user
    // pastes a link.
    expect(matches.whereType<ShellRouteMatch>(), isNotEmpty);
  });

  test('the sign-in and setup routes are gone, not just unlinked', () {
    for (final path in <String>['/signin', '/setup']) {
      expect(
        match(path).matches,
        isEmpty,
        reason: '$path should not exist any more',
      );
    }
  });

  test('a playlist opens under the playlists route', () {
    expect(match('/playlists/abc123').matches, isNotEmpty);
  });
}
