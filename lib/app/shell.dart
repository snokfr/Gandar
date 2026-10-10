import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/motion/motion.dart';
import '../core/theme/theme_engine.dart';
import '../features/player/player_surface.dart';
import '../widgets/common.dart';

/// Navigation destinations shown in both layouts.
class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_Destination> _destinations = <_Destination>[
  _Destination(
    '/library',
    'Library',
    Icons.library_music_outlined,
    Icons.library_music,
  ),
  _Destination(
    '/playlists',
    'Playlists',
    Icons.queue_music_outlined,
    Icons.queue_music,
  ),
  _Destination('/search', 'Search', Icons.search_outlined, Icons.search),
  _Destination('/themes', 'Themes', Icons.palette_outlined, Icons.palette),
  _Destination(
    '/settings',
    'Settings',
    Icons.settings_outlined,
    Icons.settings,
  ),
];

/// Width at or above which the desktop layout is used.
const double kDesktopBreakpoint = 900;

/// Adapts between a desktop layout (side rail + rich playback bar) and a
/// mobile layout (bottom navigation + mini player).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFor(location);
    final tokens = context.gandarTokens;
    final duration = Motion.adaptiveDuration(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= kDesktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: tokens.backgroundSecondaryColor,
                    border: Border(
                      right: BorderSide(color: tokens.borderColor),
                    ),
                  ),
                  child: NavigationRail(
                    extended: constraints.maxWidth >= 1180,
                    selectedIndex: index,
                    onDestinationSelected: (i) =>
                        context.go(_destinations[i].path),
                    labelType: constraints.maxWidth >= 1180
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: GandarLogo(size: 26),
                      ),
                    ),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: KeyedSubtree(
                            key: ValueKey(location),
                            child: child,
                          ),
                        ),
                      ),
                      const PlayerBar(),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Column(
            children: [
              Expanded(child: child),
              const MiniPlayer(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }

  static int _indexFor(String location) {
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].path)) return i;
    }
    return 0;
  }
}
