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
/// So there is nothing here but the parts that are genuinely Dart's: the
/// smallest size the layout survives, and making sure the window is actually
/// shown once Flutter can draw. Best effort throughout, because none of it is
/// worth failing a launch over.
Future<void> configureMacWindowChrome() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
  try {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      minimumSize: Size(880, 560),
      // The runner already hid the caption; saying so again here would re-apply
      // the platform's own idea of a title bar on top of that.
      titleBarStyle: TitleBarStyle.normal,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    AppLogger.instance.debug('window', 'window setup complete');
  } catch (e) {
    AppLogger.instance.warn(
      'window',
      'could not finish the window setup; leaving the window as the runner '
      'created it',
      error: e,
    );
  }
}
