import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../logging/app_logger.dart';

/// The window things the custom chrome can ask for.
///
/// Every call is best-effort. With the system title bar hidden the app owns
/// these buttons, so there is no fallback to fall back to — but a failure here
/// also must not break the UI, and in a widget test there is no window at all.
/// So each action logs and returns, and the UI never has to know whether it is
/// running in a real window.
class WindowActions {
  WindowActions();

  /// The instance the UI talks to, so tests can replace it.
  static WindowActions instance = WindowActions();

  /// Swaps the implementation, for tests.
  @visibleForTesting
  static set overrideWith(WindowActions actions) => instance = actions;

  bool get _supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> startDragging() =>
      _run('startDragging', windowManager.startDragging);

  Future<void> minimize() => _run('minimize', windowManager.minimize);

  Future<void> close() => _run('close', windowManager.close);

  /// Zooms the window: maximize when it is not, restore when it is.
  Future<void> toggleZoom() => _run('toggleZoom', () async {
    if (await isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  });

  Future<bool> isMaximized() async {
    if (!_supported) return false;
    try {
      return await windowManager.isMaximized();
    } catch (_) {
      return false;
    }
  }

  Future<void> _run(String what, Future<void> Function() action) async {
    if (!_supported) return;
    try {
      await action();
    } catch (e) {
      AppLogger.instance.debug('window', '$what failed: $e');
    }
  }
}
