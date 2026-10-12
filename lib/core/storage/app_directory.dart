import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where Gandar keeps the files that belong to it.
///
/// This exists because `getApplicationSupportDirectory()` is a *lookup*, not a
/// fact. On Windows it resolves the roaming app-data folder and appends the
/// executable's company and product name, and when that resolution fails it
/// throws `MissingPlatformDirectoryException` — which it does intermittently on
/// a real machine. One failure broke four things at once:
///
///   * the library could not be opened, so the Library page showed
///     "Unable to get application support directory";
///   * CSV and JSON imports failed with the same message;
///   * the log file fell back to the working directory;
///   * `PlaybackTemp` could not prepare an app-owned directory, silently kept
///     the system temp directory instead, and playback died with
///     `PathAccessException: Cannot create file, path = '\\?\…\Temp\<uuid>'`,
///     because that is the directory this machine refuses to write to.
///
/// So the folder is worked out from several sources, and the first one that
/// accepts a probe file wins. path_provider's own answer is tried first, so
/// existing installs stay exactly where they are.
class AppDirectory {
  AppDirectory._();

  /// The vendor and product segments path_provider appends on Windows, and the
  /// ones `windows/runner/Runner.rc` gives this executable.
  static const String vendor = 'com.gandar';
  static const String product = 'gandar';

  static Directory? _cached;

  /// One sentence describing which candidate won, for the log. Null until
  /// [support] has run.
  static String? lastChoice;

  /// The directory Gandar's data belongs in.
  ///
  /// Resolved once; every later call returns the same directory, so the
  /// database, the log and the playback temp directory cannot drift apart.
  static Future<Directory> support() async {
    final cached = _cached;
    if (cached != null) return cached;
    return _cached = await pick(await candidates());
  }

  /// Where cached audio files live: `<data>/cache`.
  ///
  /// Named here, next to the database and the log, so all three cannot drift
  /// apart — and created on demand, because a cache directory that only exists
  /// once a track has been downloaded is one fewer thing to get wrong at
  /// startup.
  static Future<Directory> cacheDirectory() async {
    // Not `support`, which would shadow the method being called.
    final root = await support();
    final directory = Directory(p.join(root.path, 'cache'));
    await directory.create(recursive: true);
    return directory;
  }

  /// The places worth trying, in order of preference.
  static Future<List<Directory>> candidates() async {
    final out = <Directory>[];

    // 1. What path_provider says, which is where existing installs already are.
    try {
      final support = await getApplicationSupportDirectory();
      out.add(support);
    } catch (e) {
      lastChoice = 'path_provider failed ($e)';
    }

    // 2. The same folder, worked out from the environment instead of asked for.
    final fromEnvironment = _environmentDirectory();
    if (fromEnvironment != null) out.add(fromEnvironment);

    // 3. A folder beside the executable. Read-only in an installed location,
    //    which is fine: the probe decides.
    try {
      final exe = File(Platform.resolvedExecutable).parent;
      out.add(Directory(p.join(exe.path, 'data', product)));
    } catch (_) {
      // No executable path on this platform; the other candidates cover it.
    }

    // 4. Somewhere is better than nowhere.
    out.add(Directory.systemTemp);
    return out;
  }

  /// The first of [candidates] that can be created and written to.
  ///
  /// Returns the system temp directory when none of them can — a last resort
  /// rather than a good answer, and the log says so.
  static Future<Directory> pick(List<Directory> candidates) async {
    for (final candidate in candidates) {
      if (!await isWritable(candidate)) continue;
      final skipped = candidates
          .take(candidates.indexOf(candidate))
          .map((c) => c.path)
          .toList(growable: false);
      lastChoice = skipped.isEmpty
          ? candidate.path
          : '${candidate.path} (fell back past ${skipped.join(', ')})';
      return candidate;
    }
    lastChoice =
        'nothing was writable; using ${Directory.systemTemp.path}, '
        'which this machine may refuse';
    return Directory.systemTemp;
  }

  /// Whether [directory] can be created and given a new file.
  ///
  /// The write is the only test that matters: a directory can exist and still
  /// refuse new files, which is the whole reason this class exists.
  static Future<bool> isWritable(Directory directory) async {
    try {
      await directory.create(recursive: true);
      final probe = File(p.join(directory.path, writeProbeName));
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Name of the file the writability probe writes. Kept in one place so tests
  /// and the app agree on what a leftover probe file looks like.
  static const String writeProbeName = '.gandar-write-probe';

  /// `%APPDATA%\com.gandar\gandar` on Windows, the XDG equivalent elsewhere.
  static Directory? _environmentDirectory() {
    String? base;
    if (Platform.isWindows) {
      base = Platform.environment['APPDATA'];
    } else {
      base = Platform.environment['XDG_DATA_HOME'];
      if (base == null || base.isEmpty) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          base = p.join(home, '.local', 'share');
        }
      }
    }
    if (base == null || base.isEmpty) return null;
    return Directory(p.join(base, vendor, product));
  }
}
