import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

/// The minimum a `QueryExecutor` needs to be opened over a file, so a database
/// can be written by hand without drift's own version number being involved.
class _NoMigrations extends QueryExecutorUser {
  _NoMigrations(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// The v1 schema, as those tables were created when the app first shipped.
///
/// Spelled out here rather than taken from the live schema on purpose: a
/// fixture that follows the code it is testing cannot catch that code changing.
const _v1Tables = {
  'tracks': '''
    CREATE TABLE IF NOT EXISTS tracks (
      id TEXT NOT NULL,
      title TEXT NOT NULL,
      artists TEXT NOT NULL,
      album TEXT,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      artwork_url TEXT,
      isrc TEXT,
      added_at INTEGER,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );''',
  'playlists': '''
    CREATE TABLE IF NOT EXISTS playlists (
      id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      track_count INTEGER NOT NULL DEFAULT 0,
      artwork_url TEXT,
      owner_name TEXT,
      is_collaborative INTEGER NOT NULL DEFAULT 0
        CHECK ("is_collaborative" IN (0, 1)),
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );''',
  'mappings': '''
    CREATE TABLE IF NOT EXISTS mappings (
      spotify_track_id TEXT NOT NULL,
      video_id TEXT NOT NULL,
      container TEXT NOT NULL DEFAULT 'm4a',
      created_at INTEGER NOT NULL,
      PRIMARY KEY (spotify_track_id)
    );''',
  'cache_entries': '''
    CREATE TABLE IF NOT EXISTS cache_entries (
      video_id TEXT NOT NULL,
      file_path TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      last_played_at INTEGER NOT NULL,
      PRIMARY KEY (video_id)
    );''',
  'play_history': '''
    CREATE TABLE IF NOT EXISTS play_history (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      track_id TEXT NOT NULL,
      played_at INTEGER NOT NULL
    );''',
};

const _v3Table = '''
  CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    cached_at INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, track_id)
  );''';

const _v3Index =
    'CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist '
    'ON playlist_tracks (playlist_id);';

/// Writes a database file that looks the way an older Gandar left it.
///
/// [isLocalColumn] and [v3Applied] add the pieces that the v4 and v3 steps
/// bring, which lets a caller build a file that already holds what a later
/// version adds while its version number still says otherwise — the shape an
/// upgrade that dies part-way leaves behind, and the shape that used to wedge
/// the library.
Future<void> _writeDatabaseFile(
  File file, {
  required int version,
  bool isLocalColumn = false,
  bool v3Applied = false,
}) async {
  // A bare executor, not an [AppDatabase]: opening one of those would create
  // the current schema and set the current version, which is the opposite of
  // what this file is for.
  final executor = NativeDatabase(file);
  await executor.ensureOpen(_NoMigrations(1));
  for (final statement in _v1Tables.values) {
    await executor.runCustom(statement);
  }
  if (isLocalColumn) {
    await executor.runCustom(
      'ALTER TABLE playlists ADD COLUMN is_local INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("is_local" IN (0, 1))',
    );
  }
  if (v3Applied) {
    await executor.runCustom(_v3Table);
    await executor.runCustom(_v3Index);
  }
  await executor.runCustom('PRAGMA user_version = $version');
  await executor.close();
}

Future<int> _userVersion(GeneratedDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<Set<String>> _columnsOf(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<Set<String>> _indexes(GeneratedDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('gandar-schema');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  File fileNamed(String name) => File(p.join(directory.path, name));

  AppDatabase open(File file) => AppDatabase.withExecutor(NativeDatabase(file));

  group('schema upgrades', skip: sqliteSkipReason, () {
    test('an upgrade that died after adding the v4 column finishes', () async {
      // v3's work is in the file and so is the column v4 adds, but the version
      // still says 3: what an interrupted v3 -> v4 upgrade leaves behind.
      final file = fileNamed('half-applied-v4.sqlite');
      await _writeDatabaseFile(
        file,
        version: 3,
        isLocalColumn: true,
        v3Applied: true,
      );

      final db = open(file);
      addTearDown(db.close);

      // Before this was handled, opening the database threw
      // `SqliteException(1): duplicate column name: is_local`, the version
      // stayed at 3, and every later launch failed the same way.
      await expectLater(
        db.customSelect('SELECT id FROM playlists').get(),
        completes,
      );
      expect(await _userVersion(db), 4);
    });

    test('an upgrade whose steps had all already run can run again', () async {
      // Everything v1 -> v4 adds is already there, with the version rolled back
      // to where the upgrade would have started from. Every step has to notice
      // its own work and leave it alone.
      final file = fileNamed('all-steps-applied.sqlite');
      await _writeDatabaseFile(
        file,
        version: 1,
        isLocalColumn: true,
        v3Applied: true,
      );

      final db = open(file);
      addTearDown(db.close);

      await db.customSelect('SELECT id FROM playlists').get();
      expect(await _userVersion(db), 4);

      // The column was left alone rather than added a second time, and the
      // table it belongs to is still usable.
      await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: 'p1',
              name: 'Made here',
              cachedAt: DateTime(2026, 10, 11),
              isLocal: const Value(true),
            ),
          );
      expect((await db.select(db.playlists).getSingle()).isLocal, isTrue);
    });

    test('a v1 database gains v2, v3 and v4', () async {
      final file = fileNamed('upgrade-from-v1.sqlite');
      await _writeDatabaseFile(file, version: 1);

      final db = open(file);
      addTearDown(db.close);

      await db.customSelect('SELECT id FROM playlists').get();
      expect(await _userVersion(db), 4);

      expect(await _columnsOf(db, 'playlists'), contains('is_local'));

      // Every index the later versions define, not just the newest.
      expect(
        await _indexes(db),
        containsAll(<String>[
          'idx_tracks_added_at',
          'idx_tracks_title',
          'idx_playlists_name',
          'idx_playlist_tracks_playlist',
          'idx_cache_last_played',
          'idx_history_track',
          'idx_history_played_at',
        ]),
      );

      // A playlist stored before v4 was imported from somewhere else, so the
      // default has to be false, not true.
      await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: 'old',
              name: 'Imported',
              cachedAt: DateTime(2026, 1, 1),
            ),
          );
      expect((await db.select(db.playlists).getSingle()).isLocal, isFalse);
    });
  });
}
