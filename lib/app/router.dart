import 'package:go_router/go_router.dart';

import '../features/albums/albums_page.dart';
import '../features/feed/feed_page.dart';
import '../features/import/import_page.dart';
import '../features/library/library_page.dart';
import '../features/mashup/mashup_page.dart';
import '../features/playlists/playlists_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/themes/themes_page.dart';
import 'shell.dart';

/// The application router.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/library',
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryPage(),
          ),
          GoRoute(
            path: '/playlists',
            builder: (context, state) => const PlaylistsPage(),
            routes: <RouteBase>[
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    PlaylistDetailPage(playlistId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/albums',
            builder: (context, state) => const AlbumsPage(),
            routes: <RouteBase>[
              GoRoute(
                path: ':id',
                builder: (context, state) => AlbumDetailPage(
                  albumId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/feed',
            builder: (context, state) => const FeedPage(),
          ),
          GoRoute(
            path: '/mashup',
            builder: (context, state) => const MashupPage(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/import',
            builder: (context, state) => const ImportPage(),
          ),
          GoRoute(
            path: '/themes',
            builder: (context, state) => const ThemesPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
}
