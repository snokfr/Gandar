import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../storage/app_directory.dart';

/// How much detail is written.
///
/// Ordered by severity; a logger configured at [LogLevel.info] writes
/// `info`, `warn` and `error` and drops [LogLevel.debug].
enum LogLevel {
  debug('DEBUG'),
  info('INFO '),
  warn('WARN '),
  error('ERROR');

  const LogLevel(this.label);

  /// Fixed-width label so log files line up in a plain text editor.
  final String label;

  static LogLevel? byName(String name) {
    for (final level in LogLevel.values) {
      if (level.name.toLowerCase() == name.toLowerCase()) return level;
    }
    return null;
  }
}

/// One log record.
class LogEntry {
  LogEntry({
    required this.at,
    required this.level,
    required this.scope,
    required this.message,
    this.detail,
  });

  final DateTime at;
  final LogLevel level;

  /// Short tag identifying the subsystem, e.g. `spotify` or `cache`.
  final String scope;
  final String message;

  /// Extra lines (stack traces, response bodies) kept out of the headline.
  final String? detail;

  /// Single line, as written to the file.
  String get line {
    final buffer = StringBuffer()
      ..write(at.toIso8601String())
      ..write(' ')
      ..write(level.label)
      ..write(' [')
      ..write(scope)
      ..write('] ')
      ..write(message);
    if (detail != null && detail!.isNotEmpty) {
      buffer.write('\n  ');
      buffer.write(detail!.replaceAll('\n', '\n  '));
    }
    return buffer.toString();
  }

  @override
  String toString() => line;
}

/// Application-wide logger.
///
/// Writes a daily file into `<app support>/logs/` plus a mirrored copy to
/// stdout in debug builds, and keeps the most recent records in memory so the
/// Settings screen can show them without touching the filesystem.
///
/// Nothing here throws: logging must never be the reason the app fails.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// Convenience accessor: `Log.info('...')`.
  static AppLogger get log => instance;

  static const int _maxRecent = 400;
  static const int _maxFileBytes = 4 * 1024 * 1024;
  static const int _keepFiles = 7;

  final List<LogEntry> _recent = <LogEntry>[];

  /// Bumped whenever [_recent] changes, so widgets can rebuild cheaply.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Directory? _directory;
  IOSink? _sink;
  File? _file;
  bool _started = false;
  bool _fileLoggingFailed = false;

  LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// Where log files are written, or null before [start].
  Directory? get directory => _directory;

  /// The file currently being appended to, or null if file logging is off.
  File? get file => _file;

  /// True when the log directory could not be created or written to.
  bool get fileLoggingFailed => _fileLoggingFailed;

  /// Records the most recent entries, newest last.
  List<LogEntry> recent([int limit = 200]) {
    final start = _recent.length > limit ? _recent.length - limit : 0;
    return List<LogEntry>.unmodifiable(_recent.sublist(start));
  }

  /// Set once the app is running, for the version banner.
  Map<String, String> environment = <String, String>{};

  /// Opens the log file and writes the session header.
  ///
  /// Pass [directory] to override the location (used by tests).
  Future<void> start({Directory? directory, LogLevel? level}) async {
    if (_started) return;
    _started = true;
    if (level != null) minLevel = level;

    try {
      final dir = directory ?? await _defaultDirectory();
      await dir.create(recursive: true);
      _directory = dir;
      await _pruneOldFiles(dir);
      final stamp = _dateStamp(DateTime.now());
      final candidate = File(p.join(dir.path, 'gandar-$stamp.log'));
      // Roll over if today's file is already large.
      final file =
          candidate.existsSync() && candidate.lengthSync() > _maxFileBytes
          ? File(
              p.join(
                dir.path,
                'gandar-$stamp-${DateTime.now().millisecondsSinceEpoch}.log',
              ),
            )
          : candidate;
      _file = file;
      _sink = file.openWrite(mode: FileMode.append);
    } catch (e) {
      // Fall back to memory-only logging rather than failing to launch.
      _fileLoggingFailed = true;
      write(
        LogLevel.warn,
        'logger',
        'File logging unavailable, keeping logs in memory only',
        error: e,
      );
    }

    write(
      LogLevel.info,
      'logger',
      'Log file: ${_file?.path ?? '(memory only)'}',
    );
    for (final entry in environment.entries) {
      write(LogLevel.info, 'env', '${entry.key}: ${entry.value}');
    }
  }

  Future<Directory> _defaultDirectory() async {
    // [AppDirectory] already tries path_provider first, so this is the same
    // location on a healthy machine — but it survives the lookup failing, which
    // is the difference between logs on disk and logs in memory only.
    final support = await AppDirectory.support();
    return Directory(p.join(support.path, 'logs'));
  }

  Future<void> _pruneOldFiles(Directory dir) async {
    try {
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).startsWith('gandar-'))
              .toList()
            ..sort(
              (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
            );
      final excess = files.length - _keepFiles + 1;
      for (var i = 0; i < excess && i < files.length; i++) {
        files[i].deleteSync();
      }
    } catch (_) {
      // Pruning is best effort.
    }
  }

  static String _dateStamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}';
  }

  /// Reads the whole current log file (for the "copy log" action).
  Future<String> readCurrentFile() async {
    final f = _file;
    if (f == null || !f.existsSync()) {
      return _recent.map((e) => e.line).join('\n');
    }
    await flush();
    return f.readAsString();
  }

  void debug(String scope, String message) =>
      write(LogLevel.debug, scope, message);

  void info(String scope, String message) =>
      write(LogLevel.info, scope, message);

  void warn(String scope, String message, {Object? error}) =>
      write(LogLevel.warn, scope, message, error: error);

  void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => write(
    LogLevel.error,
    scope,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  /// Records one entry. Never throws.
  void write(
    LogLevel level,
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) return;

    String? detail;
    if (error != null) {
      detail = '${error.runtimeType}: $error';
    }
    if (stackTrace != null) {
      final frames = stackTrace
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(12)
          .join('\n');
      detail = detail == null ? frames : '$detail\n$frames';
    }

    final entry = LogEntry(
      at: DateTime.now(),
      level: level,
      scope: scope,
      message: message,
      detail: detail,
    );

    _recent.add(entry);
    if (_recent.length > _maxRecent) {
      _recent.removeRange(0, _recent.length - _maxRecent);
    }
    revision.value++;

    try {
      _sink?.writeln(entry.line);
    } catch (_) {
      _fileLoggingFailed = true;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print(entry.line);
    }
  }

  /// Times [body], logging the elapsed milliseconds under [scope].
  ///
  /// Used to keep startup honest: every expensive step reports its cost.
  Future<T> time<T>(
    String scope,
    String label,
    Future<T> Function() body, {
    LogLevel level = LogLevel.info,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await body();
      write(level, scope, '$label: ${sw.elapsedMilliseconds} ms');
      return result;
    } catch (e, s) {
      write(
        LogLevel.error,
        scope,
        '$label failed after ${sw.elapsedMilliseconds} ms',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  /// Routes Flutter framework errors and uncaught async errors into the log.
  void captureErrors() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error(
        'flutter',
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
      );
      if (details.informationCollector != null) {
        debug(
          'flutter',
          details.informationCollector!().map((n) => n.toString()).join('\n'),
        );
      }
      previous?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      this.error('uncaught', '$error', error: error, stackTrace: stack);
      return true;
    };
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {
      _fileLoggingFailed = true;
    }
  }

  /// Test seam: stops file logging and clears buffered entries.
  Future<void> reset() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _file = null;
    _directory = null;
    _started = false;
    _fileLoggingFailed = false;
    _recent.clear();
  }
}
