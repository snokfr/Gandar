import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:path/path.dart' as p;

import 'app/app.dart';
import 'app/router.dart';
import 'core/logging/app_logger.dart';
import 'core/settings/settings_repository.dart';
import 'core/storage/app_directory.dart';
import 'core/window/window_chrome.dart';
import 'data/storage/app_database.dart';
import 'playback/audio_engine/media_kit_audio_engine.dart';
import 'playback/audio_engine/playback_temp.dart';
import 'state/app_dependencies.dart';
import 'state/providers.dart';
import 'state/retry_policy.dart';

Future<void> main() async {
  final startup = Stopwatch()..start();

  // Resolved before anything else writes a file: the database, the log and the
  // playback temp directory all come from here, so deciding once is what keeps
  // them in the same place. [AppDirectory] survives the platform lookup that
  // used to fail and take the library, imports and playback with it.
  final dataDirectory = await AppDirectory.support();

  final log = AppLogger.instance;
  // Set before starting: `start` writes the header, and a log with no version,
  // platform or configuration in it is much harder to act on.
  log.environment = <String, String>{
    'platform':
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'dart': Platform.version.split(' ').first,
    'mode': kDebugMode ? 'debug' : 'release',
    'data': AppDirectory.lastChoice ?? dataDirectory.path,
  };
  await log.start(directory: Directory(p.join(dataDirectory.path, 'logs')));
  // The first line in the log, and the only way to see what the work *before*
  // logging costs: resolving the data directory is a platform lookup plus a
  // writability probe, and it all happens before there is anywhere to log to.
  // Without this number the startup breakdown starts halfway through.
  log.info(
    'startup',
    'data directory resolved at ${startup.elapsedMilliseconds} ms '
        '(${AppDirectory.lastChoice ?? dataDirectory.path})',
  );

  runZonedGuarded(
    () async {
      log.captureErrors();
      WidgetsFlutterBinding.ensureInitialized();

      // Three startup steps that have nothing to do with each other, started
      // together rather than in a queue. Each one is a fixed cost this app
      // cannot avoid — a platform window handshake, a writability probe on
      // disk, opening the preference store — so the only lever available is how
      // many of them are in flight at once. On the machine this was measured
      // on, overlapping them roughly halves the time to the first frame.
      //
      // Finishes the window setup the native runner starts: the title bar is
      // already gone by the time Dart runs (see
      // `windows/runner/win32_window.cpp`), and the sidebar draws the controls
      // in its place. Best effort — see [configureMacWindowChrome].
      final chrome = log.time(
        'startup',
        'window chrome',
        configureMacWindowChrome,
      );

      // media_kit writes a temporary playlist into the system temp directory
      // before every playback, and playback cannot start if that write fails:
      // on a machine that denies new files in %TEMP%, the symptom is a track
      // that silently never plays. So the app hands media_kit a directory of
      // its own and proves it is writable first — in every build, because
      // release builds write that file too.
      final playbackTempFuture = log.time(
        'startup',
        'prepare playback temp directory',
        PlaybackTemp.ensure,
      );

      final settingsFuture = log.time<SettingsRepository>(
        'startup',
        'open settings store',
        () => SharedPrefsStore.open().then(SettingsRepository.new),
      );

      // libmpv must be initialized before any Player is constructed. It is a
      // synchronous registration, so it costs nothing to do here while the
      // three above are still in flight.
      await log.time('startup', 'media_kit init', () async {
        MediaKit.ensureInitialized();
      });

      final playbackTemp = await playbackTempFuture;
      log.info('startup', 'playback temp: ${playbackTemp.status}');
      if (!playbackTemp.writable) {
        // This is the state that used to be silent, and it is the state that
        // produced "Cannot create file … Access is denied" for every track.
        log.warn(
          'startup',
          'playback has no writable temp directory of its own; if tracks fail '
          'to start, that is why',
        );
      }

      final settingsRepository = await settingsFuture;

      // The window handshake has to have finished before the first frame is
      // drawn, but nothing before this point needed it, so it has been running
      // alongside the rest rather than holding them up.
      await chrome;

      final database = AppDatabase();
      final audioEngine = MediaKitAudioEngine(temp: playbackTemp);

      final dependencies = await log.time(
        'startup',
        'bootstrap dependencies',
        () => AppDependencies.bootstrap(
          database: database,
          settingsRepository: settingsRepository,
          audioEngine: audioEngine,
        ),
      );

      runApp(
        ProviderScope(
          overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
          // Retry a flaky network, never a refusal.
          retry: gandarProviderRetry,
          child: GandarApp(router: buildRouter()),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        log.info(
          'startup',
          'first frame in ${startup.elapsedMilliseconds} ms '
              '(engine ${dependencies.playbackController.engineState.name})',
        );
      });
    },
    (error, stack) {
      log.error('uncaught', '$error', error: error, stackTrace: stack);
    },
  );
}
