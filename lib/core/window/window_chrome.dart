import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../logging/app_logger.dart';

/// Finishes the window setup the native runner starts.
///
/// The runner is what removes the title bar: `windows/runner/win32_window.cpp`
/// claims the caption as client area in `WM_NCCALCSIZE`, and answers
/// `WM_NCHITTEST` so the top strip still drags and the edges still resize. That
/// has to happen while the window is being created — arranging it afterwards
/// from Dart leaves the client area offset by the height the platform still
/// reserved, which is what cut the bottom off the UI when this was done with
/// `TitleBarStyle.hidden`.
///
/// So there is little here that is genuinely Dart's: the smallest size the
/// layout survives, and the focus. Best effort throughout, because none of it
/// is worth failing a launch over.
///
/// **This is deliberately not on the launch's critical path.** The window is
/// shown by the runner itself — `SetNextFrameCallback` in
/// `windows/runner/flutter_window.cpp` calls `Show()` — so the `show()` that
/// used to be awaited here was doing work the runner had already done, and
/// awaiting it meant the app could not draw until two platform round-trips
/// finished. Measured on a release build, that was about half of the time to
/// the first frame.
///
/// Only the `ensureInitialized()` handshake is awaited, because the shell's
/// first build asks the window whether it is maximized. Everything after it
/// runs to completion on its own.
Future<void> configureMacWindowChrome() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
  try {
    await windowManager.ensureInitialized();
  } catch (e) {
    AppLogger.instance.warn(
      'window',
      'could not reach the window manager; the runner\'s window is still '
      'there, so the app works — the minimum size and focus are what is lost',
      error: e,
    );
    return;
  }
  unawaited(_applyWindowOptions());
}

/// Applies the window options in the background. Never throws.
Future<void> _applyWindowOptions() async {
  try {
    const options = WindowOptions(
      minimumSize: Size(880, 560),
      // The runner already hid the caption; saying so again here would re-apply
      // the platform's own idea of a title bar on top of that.
      titleBarStyle: TitleBarStyle.normal,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.focus();
    });
    AppLogger.instance.debug('window', 'window options applied');
  } catch (e) {
    AppLogger.instance.warn(
      'window',
      'could not apply the window options; leaving the window as the runner '
      'created it',
      error: e,
    );
  }
}
