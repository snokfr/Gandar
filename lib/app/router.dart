import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_page.dart';
import '../features/library/library_page.dart';
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
            path: '/search',
            builder: (context, state) => const SearchPage(),
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
      GoRoute(path: '/signin', builder: (context, state) => const SignInPage()),
    ],
  );
}
