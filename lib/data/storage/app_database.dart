import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Cached Spotify track metadata.
@DataClassName('TrackRow')
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artists => text()(); // newline-separated
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get artworkUrl => text().nullable()();
  TextColumn get isrc => text().nullable()();
  DateTimeColumn get addedAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached Spotify playlist summaries.
@DataClassName('PlaylistRow')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  TextColumn get artworkUrl => text().nullable()();
  TextColumn get ownerName => text().nullable()();
  BoolColumn get isCollaborative =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Permanent Spotify track id -> YouTube video id mapping.
///
/// This is the "instant playback" table: once resolved, a song never needs a
/// YouTube search again.
@DataClassName('MappingRow')
class Mappings extends Table {
  TextColumn get spotifyTrackId => text()();
  TextColumn get videoId => text()();
  TextColumn get container => text().withDefault(const Constant('m4a'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {spotifyTrackId};
}

/// Cached audio files on disk, ordered for LRU eviction.
@DataClassName('CacheEntryRow')
class CacheEntries extends Table {
  TextColumn get videoId => text()();
  TextColumn get filePath => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {videoId};
}

/// Play interaction history.
@DataClassName('PlayHistoryRow')
class PlayHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text()();
  DateTimeColumn get playedAt => dateTime()();
}

@DriftDatabase(tables: [Tracks, Playlists, Mappings, CacheEntries, PlayHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test/desktop constructor for an explicit executor (e.g. in-memory).
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'gandar.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
