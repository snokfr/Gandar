import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/storage/app_directory.dart';

/// The directory `media_kit` is allowed to write its temporary files into.
///
/// Before it hands a stream to libmpv, media_kit writes the playlist it is
/// about to load into `Directory.systemTemp` — a bare `<temp>\<uuid>`, no
/// extension — and only then tells mpv to play it. On a machine where the
/// Windows temp directory refuses new files from an unsigned binary, that write
/// fails:
///
/// ```
/// PathAccessException: Cannot create file,
///   path = '\\?\C:\Users\…\AppData\Local\Temp\f1652055-…'
///   (OS Error: Access is denied, errno = 5)
/// ```
///
/// The exception is thrown inside `Player.open`, before any audio is touched,
/// so the visible symptom is a track that silently never starts.
///
/// The app's own support directory is writable — the log file and the database
/// already live there — so playback is pointed at `<support>/temp` instead.
/// Nothing else in the app reads this directory, and the files in it are
/// media_kit's own playlists, which media_kit deletes seconds after loading
/// them.
class PlaybackTemp {
  const PlaybackTemp._(this.directory, this.status, this.writable);

  /// The directory `media_kit` should use.
  final Directory directory;

  /// One sentence for the log, describing what was chosen and why.
  final String status;

  /// Whether this directory accepted a probe file. False means playback is on
  /// the system temp directory and may fail the way it did before.
  final bool writable;

  /// Prepares an app-owned temp directory and proves it is writable.
  ///
  /// Never throws, and tries several homes for it in turn. That order matters:
  /// the first version of this method asked for the application support
  /// directory, and when that lookup failed it quietly kept the system temp
  /// directory — the one directory on this machine that refuses the write — so
  /// the guard was absent exactly when it was needed.
  static Future<PlaybackTemp> ensure() async {
    final listeners = <Directory>[];
    final support = await AppDirectory.support();
    listeners.add(Directory(p.join(support.path, 'temp')));
    // The same idea one level out: local app data on Windows, and the app's own
    // folder beside the executable, which is inside the install for a portable
    // copy and read-only for an installed one — [AppDirectory.isWritable]
    // answers that rather than assuming either way.
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      listeners.add(
        Directory(p.join(local, AppDirectory.vendor, AppDirectory.product, 'temp')),
      );
    }
    try {
      final exe = File(Platform.resolvedExecutable).parent;
      listeners.add(Directory(p.join(exe.path, 'temp')));
    } catch (_) {
      // No executable path here; the other homes cover it.
    }

    for (final candidate in listeners) {
      final prepared = await forDirectory(candidate);
      if (prepared.writable) return prepared;
    }

    return PlaybackTemp._(
      Directory.systemTemp,
      'no app-owned directory was writable (tried '
      '${listeners.map((d) => d.path).join(', ')}); '
      'using ${Directory.systemTemp.path}, which playback may not be allowed to '
      'write to',
      false,
    );
  }

  /// Creates [directory] and checks that a file can actually be written there.
  ///
  /// The write is the only test that matters: a directory can exist and still
  /// refuse new files, which is exactly the failure this class exists for.
  static Future<PlaybackTemp> forDirectory(Directory directory) async {
    try {
      await directory.create(recursive: true);
      final probe = File(p.join(directory.path, 'write-probe'));
      await probe.writeAsString('ok');
      await probe.delete();
      return PlaybackTemp._(directory, 'writable: ${directory.path}', true);
    } catch (e) {
      return PlaybackTemp._(
        Directory.systemTemp,
        '${directory.path} is not writable ($e); '
        'using ${Directory.systemTemp.path} instead',
        false,
      );
    }
  }

  /// Runs [body] with `Directory.systemTemp` answered by [directory].
  ///
  /// `media_kit` reads `Directory.systemTemp` when it writes its playlist file,
  /// so this is what keeps its temp file inside a directory the app can write
  /// to without patching the package.
  Future<T> withTempDirectory<T>(Future<T> Function() body) =>
      IOOverrides.runZoned(body, getSystemTempDirectory: () => directory);
}
