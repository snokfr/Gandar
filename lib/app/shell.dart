import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/motion/motion.dart';
import '../core/theme/theme_engine.dart';
import '../core/window/window_actions.dart';
import '../features/player/player_surface.dart';
import '../widgets/common.dart';
import '../widgets/mac_window_controls.dart';

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
  _Destination('/albums', 'Albums', Icons.album_outlined, Icons.album),
  _Destination(
    '/playlists',
    'Playlists',
    Icons.queue_music_outlined,
    Icons.queue_music,
  ),
  _Destination(
    '/feed',
    'Feed',
    Icons.dynamic_feed_outlined,
    Icons.dynamic_feed,
  ),
  _Destination(
    '/mashup',
    'Mashup',
    Icons.motion_photos_on_outlined,
    Icons.motion_photos_on,
  ),
  _Destination('/search', 'Search', Icons.search_outlined, Icons.search),
  _Destination('/import', 'Import', Icons.download_outlined, Icons.download),
  _Destination('/themes', 'Themes', Icons.palette_outlined, Icons.palette),
  _Destination(
    '/settings',
    'Settings',
    Icons.settings_outlined,
    Icons.settings,
  ),
];

/// How many destinations the mobile bottom bar shows.
///
/// Nine tabs do not fit a phone's bottom bar, and Flutter's answer to that is
/// cramped labels rather than an overflow menu. The bar therefore shows the
/// places a phone is actually used for — browsing, searching, importing — and
/// the rest stay one tap away through the sidebar's equivalents on desktop,
/// where the whole list is shown.
const int _mobileDestinationCount = 5;

/// Width at or above which the desktop layout is used.
const double kDesktopBreakpoint = 900;

/// Adapts between a desktop layout (sidebar + window controls + rich playback
/// bar) and a mobile layout (bottom navigation + mini player).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _refreshMaximized();
  }

  Future<void> _refreshMaximized() async {
    final maximized = await WindowActions.instance.isMaximized();
    if (mounted && maximized != _maximized) {
      setState(() => _maximized = maximized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFor(location);
    final duration = Motion.adaptiveDuration(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= kDesktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(
                  index: index,
                  extended: constraints.maxWidth >= 1180,
                  maximized: _maximized,
                  onZoomChanged: _refreshMaximized,
                  onSelected: (i) => context.go(_destinations[i].path),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: duration,
                              child: KeyedSubtree(
                                key: ValueKey(location),
                                child: widget.child,
                              ),
                            ),
                          ),
                          const PlayerBar(),
                        ],
                      ),
                      // The content can be grabbed by its top edge too, the way
                      // the empty part of a Mac toolbar can. Translucent, so a
                      // control that lives up here still gets its taps.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: MacDragRegion(
                          height: 26,
                          onDrag: () => WindowActions.instance.startDragging(),
                          onZoom: () async {
                            await WindowActions.instance.toggleZoom();
                            await _refreshMaximized();
                          },
                        ),
                      ),
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
              Expanded(child: widget.child),
              const MiniPlayer(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index < _mobileDestinationCount ? index : 0,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            destinations: [
              for (final d in _destinations.take(_mobileDestinationCount))
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

/// The sidebar: window controls where a Mac puts them, then the logo, then the
/// destinations.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.extended,
    required this.onSelected,
    required this.maximized,
    required this.onZoomChanged,
  });

  final int index;
  final bool extended;
  final ValueChanged<int> onSelected;
  final bool maximized;
  final VoidCallback onZoomChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;

    Future<void> zoom() async {
      await WindowActions.instance.toggleZoom();
      onZoomChanged();
    }

    return Container(
      decoration: BoxDecoration(
        color: tokens.backgroundSecondaryColor,
        border: Border(right: BorderSide(color: tokens.borderColor)),
      ),
      child: NavigationRail(
        extended: extended,
        selectedIndex: index,
        onDestinationSelected: onSelected,
        labelType: extended
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.all,
        // `start`, because a centred leading puts the window buttons in the
        // middle of the sidebar, where the platform's own hit-testing treats
        // them as title bar and swallows the clicks before Flutter sees them.
        // They belong in the corner anyway — that is where a Mac puts them, and
        // where `WM_NCHITTEST` in the runner leaves them clickable.
        leading: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The top of the sidebar is part of the window's title bar, so it
            // is what the window is dragged by — except the lights themselves.
            MacDragRegion(
              height: 44,
              onDrag: () => WindowActions.instance.startDragging(),
              onZoom: zoom,
              child: Padding(
                padding: const EdgeInsets.only(left: 18, top: 16),
                child: MacWindowControls(
                  zoomIsMaximized: maximized,
                  onClose: () => WindowActions.instance.close(),
                  onMinimize: () => WindowActions.instance.minimize(),
                  onZoom: zoom,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 12, 12),
              child: GandarLogo(size: 26),
            ),
          ],
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
    );
  }
}
