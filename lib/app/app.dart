import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/theme_engine.dart';
import '../state/providers.dart';

/// Root widget. Rebuilds the Material theme whenever the active theme changes.
class GandarApp extends ConsumerWidget {
  const GandarApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider.select((s) => s.active));
    return MaterialApp.router(
      title: 'Gandar',
      debugShowCheckedModeBanner: false,
      theme: ThemeEngine.build(tokens),
      darkTheme: ThemeEngine.build(tokens),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
