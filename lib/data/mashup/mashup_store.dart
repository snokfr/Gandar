import 'dart:convert';
import 'dart:io';


import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/storage/app_directory.dart';
import '../../domain/models/mashup.dart';

/// One mashup on disk: the arrangement, and what it is called.
class SavedMashup {
  const SavedMashup({
    required this.name,
    required this.mashup,
    required this.savedAt,
  });

  /// The name the user gave it. Also the file's own name, so the two cannot
  /// disagree about what a mashup is called.
  final String name;

  final Mashup mashup;
  final DateTime savedAt;

  /// The songs in it, which is what a list of mixes has to say about each one.
  int get partCount => mashup.parts.length;

  String get summary {
    final count = mashup.parts.length;
    final minutes = mashup.duration.inMinutes;
    final seconds = mashup.duration.inSeconds.remainder(60).toString().padLeft(
      2,
      '0',
    );
    return '$count song${count == 1 ? '' : 's'} · $minutes:$seconds';
  }
}

/// Reads and writes mashups as files of their own.
///
/// A mashup is not a playlist and not a pair of songs: it is an arrangement —
/// which slice of each song, where each slice enters, how loud each one sits,
/// and how far they overlap. None of that fits in a playlist row, and losing it
/// means redoing the work by ear. So it gets a file: `<data>/mashups/<name>.json`,
/// readable, diffable, and copyable between machines.
///
/// The file is written whole through a temporary name and then moved into
/// place. A mashup that is half-written is worse than no mashup, and a crash
/// during a write is exactly when that happens.
///
/// The file calls are synchronous, behind asynchronous methods. There are a
/// handful of small JSON files here rather than a music library, and a mashup
/// save is something the user is waiting on with a snackbar at the end of it:
/// the round trip through the event loop buys nothing and, in a widget test
/// where the clock is fake and real I/O is not, buys a spinner that never
/// stops. Reading and writing directly keeps every one of these futures
/// completable without the event loop's help.
class MashupStore {
  MashupStore({Directory? directory}) {
    _root = directory;
  }

  /// Set by tests to keep mashup files out of the user's data directory.
  Directory? _root;

  /// `1` is the only version there has ever been. It is written into the file
  /// so a future version can tell an old mashup from a new one instead of
  /// guessing from which fields happen to be missing.
  static const int formatVersion = 1;

  static const String extension = '.json';

  /// Where mashups live. Created on demand, so a machine that has never saved
  /// one has no empty folder to explain.
  Future<Directory> directory() async {
    final cached = _root;
    if (cached != null) {
      cached.createSync(recursive: true);
      return cached;
    }
    final root = await AppDirectory.support();
    final directory = Directory(p.join(root.path, 'mashups'));
    directory.createSync(recursive: true);
    return _root = directory;
  }

  /// Every mashup on disk, most recently saved first.
  ///
  /// A file that cannot be read is skipped and logged rather than failing the
  /// list: one bad file must not hide every good one.
  Future<List<SavedMashup>> list() async {
    final directory = await this.directory();
    final files = <File>[];
    try {
      for (final entry in directory.listSync()) {
        if (entry is File && entry.path.endsWith(extension)) files.add(entry);
      }
    } on FileSystemException catch (e) {
      AppLogger.instance.warn('mashup', 'could not list mashups', error: e);
      return const <SavedMashup>[];
    }

    final saved = <SavedMashup>[];
    for (final file in files) {
      final mashup = await read(file);
      if (mashup == null) continue;
      saved.add(mashup);
    }
    saved.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return saved;
  }

  /// Reads one file. Null when it is not a mashup this version understands.
  Future<SavedMashup?> read(File file) async {
    try {
      final text = file.readAsStringSync();
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      final name = (json['name'] as String?)?.trim();
      final mashup = Mashup.fromJson(json);
      // An arrangement with no parts is not a mashup, whatever the file is
      // called: listing it would put a row on screen that opens an empty
      // screen, which is worse than not listing it.
      if (mashup.parts.isEmpty) return null;
      return SavedMashup(
        name: name == null || name.isEmpty
            ? p.basenameWithoutExtension(file.path)
            : name,
        mashup: mashup,
        savedAt:
            DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            file.statSync().modified,
      );
    } catch (e) {
      AppLogger.instance.warn(
        'mashup',
        'could not read ${file.path}',
        error: e,
      );
      return null;
    }
  }

  /// Writes [mashup] under [name], replacing any mashup already called that.
  ///
  /// Replacing rather than versioning is deliberate: "save" on a screen that
  /// is already called something means the thing you were just working on, and
  /// a shelf of `Late night blend (2)` files is not a feature.
  Future<SavedMashup> save(String name, Mashup mashup) async {
    final clean = name.trim();
    final saved = SavedMashup(
      name: clean,
      mashup: mashup,
      savedAt: DateTime.now(),
    );
    final file = await fileFor(clean);
    final payload = <String, dynamic>{
      'version': formatVersion,
      'name': clean,
      'savedAt': saved.savedAt.toIso8601String(),
      ...mashup.toJson(),
    };
    final temporary = File('${file.path}.part');
    temporary.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    temporary.renameSync(file.path);
    AppLogger.instance.info(
      'mashup',
      'saved "$clean" (${mashup.parts.length} parts) to ${file.path}',
    );
    return saved;
  }

  /// Deletes the mashup called [name]. Returns false when there was none.
  Future<bool> delete(String name) async {
    final file = await fileFor(name);
    if (!file.existsSync()) return false;
    file.deleteSync();
    AppLogger.instance.info('mashup', 'deleted "$name"');
    return true;
  }

  /// The file a mashup called [name] lives in.
  ///
  /// The name is stripped down to something a file system will accept, and a
  /// name that reduces to nothing gets a fixed stand-in, because a mashup whose
  /// name is `/` must not become a path.
  Future<File> fileFor(String name) async {
    final directory = await this.directory();
    return File(p.join(directory.path, '${safeName(name)}$extension'));
  }

  /// A name that is safe to use as a file name, and still close to what the
  /// user typed.
  static String safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '-')
        // A run of illegal characters is one dash, not a row of them: the name
        // is read by a person looking at a list.
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final withoutDots = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    return withoutDots.isEmpty ? 'mashup' : withoutDots;
  }
}
