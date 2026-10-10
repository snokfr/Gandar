// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, TrackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistsMeta = const VerificationMeta(
    'artists',
  );
  @override
  late final GeneratedColumn<String> artists = GeneratedColumn<String>(
    'artists',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _artworkUrlMeta = const VerificationMeta(
    'artworkUrl',
  );
  @override
  late final GeneratedColumn<String> artworkUrl = GeneratedColumn<String>(
    'artwork_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isrcMeta = const VerificationMeta('isrc');
  @override
  late final GeneratedColumn<String> isrc = GeneratedColumn<String>(
    'isrc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    artists,
    album,
    durationMs,
    artworkUrl,
    isrc,
    addedAt,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artists')) {
      context.handle(
        _artistsMeta,
        artists.isAcceptableOrUnknown(data['artists']!, _artistsMeta),
      );
    } else if (isInserting) {
      context.missing(_artistsMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('artwork_url')) {
      context.handle(
        _artworkUrlMeta,
        artworkUrl.isAcceptableOrUnknown(data['artwork_url']!, _artworkUrlMeta),
      );
    }
    if (data.containsKey('isrc')) {
      context.handle(
        _isrcMeta,
        isrc.isAcceptableOrUnknown(data['isrc']!, _isrcMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artists: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artists'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      artworkUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_url'],
      ),
      isrc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isrc'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      ),
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class TrackRow extends DataClass implements Insertable<TrackRow> {
  final String id;
  final String title;
  final String artists;
  final String? album;
  final int durationMs;
  final String? artworkUrl;
  final String? isrc;
  final DateTime? addedAt;
  final DateTime cachedAt;
  const TrackRow({
    required this.id,
    required this.title,
    required this.artists,
    this.album,
    required this.durationMs,
    this.artworkUrl,
    this.isrc,
    this.addedAt,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['artists'] = Variable<String>(artists);
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || artworkUrl != null) {
      map['artwork_url'] = Variable<String>(artworkUrl);
    }
    if (!nullToAbsent || isrc != null) {
      map['isrc'] = Variable<String>(isrc);
    }
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<DateTime>(addedAt);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      title: Value(title),
      artists: Value(artists),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      durationMs: Value(durationMs),
      artworkUrl: artworkUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkUrl),
      isrc: isrc == null && nullToAbsent ? const Value.absent() : Value(isrc),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory TrackRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      artists: serializer.fromJson<String>(json['artists']),
      album: serializer.fromJson<String?>(json['album']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      artworkUrl: serializer.fromJson<String?>(json['artworkUrl']),
      isrc: serializer.fromJson<String?>(json['isrc']),
      addedAt: serializer.fromJson<DateTime?>(json['addedAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'artists': serializer.toJson<String>(artists),
      'album': serializer.toJson<String?>(album),
      'durationMs': serializer.toJson<int>(durationMs),
      'artworkUrl': serializer.toJson<String?>(artworkUrl),
      'isrc': serializer.toJson<String?>(isrc),
      'addedAt': serializer.toJson<DateTime?>(addedAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  TrackRow copyWith({
    String? id,
    String? title,
    String? artists,
    Value<String?> album = const Value.absent(),
    int? durationMs,
    Value<String?> artworkUrl = const Value.absent(),
    Value<String?> isrc = const Value.absent(),
    Value<DateTime?> addedAt = const Value.absent(),
    DateTime? cachedAt,
  }) => TrackRow(
    id: id ?? this.id,
    title: title ?? this.title,
    artists: artists ?? this.artists,
    album: album.present ? album.value : this.album,
    durationMs: durationMs ?? this.durationMs,
    artworkUrl: artworkUrl.present ? artworkUrl.value : this.artworkUrl,
    isrc: isrc.present ? isrc.value : this.isrc,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  TrackRow copyWithCompanion(TracksCompanion data) {
    return TrackRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      artists: data.artists.present ? data.artists.value : this.artists,
      album: data.album.present ? data.album.value : this.album,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      artworkUrl: data.artworkUrl.present
          ? data.artworkUrl.value
          : this.artworkUrl,
      isrc: data.isrc.present ? data.isrc.value : this.isrc,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artists: $artists, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('isrc: $isrc, ')
          ..write('addedAt: $addedAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    artists,
    album,
    durationMs,
    artworkUrl,
    isrc,
    addedAt,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.artists == this.artists &&
          other.album == this.album &&
          other.durationMs == this.durationMs &&
          other.artworkUrl == this.artworkUrl &&
          other.isrc == this.isrc &&
          other.addedAt == this.addedAt &&
          other.cachedAt == this.cachedAt);
}

class TracksCompanion extends UpdateCompanion<TrackRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> artists;
  final Value<String?> album;
  final Value<int> durationMs;
  final Value<String?> artworkUrl;
  final Value<String?> isrc;
  final Value<DateTime?> addedAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.artists = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    this.isrc = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksCompanion.insert({
    required String id,
    required String title,
    required String artists,
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    this.isrc = const Value.absent(),
    this.addedAt = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       artists = Value(artists),
       cachedAt = Value(cachedAt);
  static Insertable<TrackRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? artists,
    Expression<String>? album,
    Expression<int>? durationMs,
    Expression<String>? artworkUrl,
    Expression<String>? isrc,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (artists != null) 'artists': artists,
      if (album != null) 'album': album,
      if (durationMs != null) 'duration_ms': durationMs,
      if (artworkUrl != null) 'artwork_url': artworkUrl,
      if (isrc != null) 'isrc': isrc,
      if (addedAt != null) 'added_at': addedAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? artists,
    Value<String?>? album,
    Value<int>? durationMs,
    Value<String?>? artworkUrl,
    Value<String?>? isrc,
    Value<DateTime?>? addedAt,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      isrc: isrc ?? this.isrc,
      addedAt: addedAt ?? this.addedAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artists.present) {
      map['artists'] = Variable<String>(artists.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (artworkUrl.present) {
      map['artwork_url'] = Variable<String>(artworkUrl.value);
    }
    if (isrc.present) {
      map['isrc'] = Variable<String>(isrc.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artists: $artists, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('isrc: $isrc, ')
          ..write('addedAt: $addedAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, PlaylistRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _trackCountMeta = const VerificationMeta(
    'trackCount',
  );
  @override
  late final GeneratedColumn<int> trackCount = GeneratedColumn<int>(
    'track_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _artworkUrlMeta = const VerificationMeta(
    'artworkUrl',
  );
  @override
  late final GeneratedColumn<String> artworkUrl = GeneratedColumn<String>(
    'artwork_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ownerNameMeta = const VerificationMeta(
    'ownerName',
  );
  @override
  late final GeneratedColumn<String> ownerName = GeneratedColumn<String>(
    'owner_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCollaborativeMeta = const VerificationMeta(
    'isCollaborative',
  );
  @override
  late final GeneratedColumn<bool> isCollaborative = GeneratedColumn<bool>(
    'is_collaborative',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_collaborative" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    trackCount,
    artworkUrl,
    ownerName,
    isCollaborative,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('track_count')) {
      context.handle(
        _trackCountMeta,
        trackCount.isAcceptableOrUnknown(data['track_count']!, _trackCountMeta),
      );
    }
    if (data.containsKey('artwork_url')) {
      context.handle(
        _artworkUrlMeta,
        artworkUrl.isAcceptableOrUnknown(data['artwork_url']!, _artworkUrlMeta),
      );
    }
    if (data.containsKey('owner_name')) {
      context.handle(
        _ownerNameMeta,
        ownerName.isAcceptableOrUnknown(data['owner_name']!, _ownerNameMeta),
      );
    }
    if (data.containsKey('is_collaborative')) {
      context.handle(
        _isCollaborativeMeta,
        isCollaborative.isAcceptableOrUnknown(
          data['is_collaborative']!,
          _isCollaborativeMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      trackCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_count'],
      )!,
      artworkUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_url'],
      ),
      ownerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_name'],
      ),
      isCollaborative: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_collaborative'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class PlaylistRow extends DataClass implements Insertable<PlaylistRow> {
  final String id;
  final String name;
  final String description;
  final int trackCount;
  final String? artworkUrl;
  final String? ownerName;
  final bool isCollaborative;
  final DateTime cachedAt;
  const PlaylistRow({
    required this.id,
    required this.name,
    required this.description,
    required this.trackCount,
    this.artworkUrl,
    this.ownerName,
    required this.isCollaborative,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['track_count'] = Variable<int>(trackCount);
    if (!nullToAbsent || artworkUrl != null) {
      map['artwork_url'] = Variable<String>(artworkUrl);
    }
    if (!nullToAbsent || ownerName != null) {
      map['owner_name'] = Variable<String>(ownerName);
    }
    map['is_collaborative'] = Variable<bool>(isCollaborative);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      trackCount: Value(trackCount),
      artworkUrl: artworkUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkUrl),
      ownerName: ownerName == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerName),
      isCollaborative: Value(isCollaborative),
      cachedAt: Value(cachedAt),
    );
  }

  factory PlaylistRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      trackCount: serializer.fromJson<int>(json['trackCount']),
      artworkUrl: serializer.fromJson<String?>(json['artworkUrl']),
      ownerName: serializer.fromJson<String?>(json['ownerName']),
      isCollaborative: serializer.fromJson<bool>(json['isCollaborative']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'trackCount': serializer.toJson<int>(trackCount),
      'artworkUrl': serializer.toJson<String?>(artworkUrl),
      'ownerName': serializer.toJson<String?>(ownerName),
      'isCollaborative': serializer.toJson<bool>(isCollaborative),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  PlaylistRow copyWith({
    String? id,
    String? name,
    String? description,
    int? trackCount,
    Value<String?> artworkUrl = const Value.absent(),
    Value<String?> ownerName = const Value.absent(),
    bool? isCollaborative,
    DateTime? cachedAt,
  }) => PlaylistRow(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    trackCount: trackCount ?? this.trackCount,
    artworkUrl: artworkUrl.present ? artworkUrl.value : this.artworkUrl,
    ownerName: ownerName.present ? ownerName.value : this.ownerName,
    isCollaborative: isCollaborative ?? this.isCollaborative,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  PlaylistRow copyWithCompanion(PlaylistsCompanion data) {
    return PlaylistRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      trackCount: data.trackCount.present
          ? data.trackCount.value
          : this.trackCount,
      artworkUrl: data.artworkUrl.present
          ? data.artworkUrl.value
          : this.artworkUrl,
      ownerName: data.ownerName.present ? data.ownerName.value : this.ownerName,
      isCollaborative: data.isCollaborative.present
          ? data.isCollaborative.value
          : this.isCollaborative,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('trackCount: $trackCount, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('ownerName: $ownerName, ')
          ..write('isCollaborative: $isCollaborative, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    trackCount,
    artworkUrl,
    ownerName,
    isCollaborative,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.trackCount == this.trackCount &&
          other.artworkUrl == this.artworkUrl &&
          other.ownerName == this.ownerName &&
          other.isCollaborative == this.isCollaborative &&
          other.cachedAt == this.cachedAt);
}

class PlaylistsCompanion extends UpdateCompanion<PlaylistRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<int> trackCount;
  final Value<String?> artworkUrl;
  final Value<String?> ownerName;
  final Value<bool> isCollaborative;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.trackCount = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    this.ownerName = const Value.absent(),
    this.isCollaborative = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.trackCount = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    this.ownerName = const Value.absent(),
    this.isCollaborative = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       cachedAt = Value(cachedAt);
  static Insertable<PlaylistRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? trackCount,
    Expression<String>? artworkUrl,
    Expression<String>? ownerName,
    Expression<bool>? isCollaborative,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (trackCount != null) 'track_count': trackCount,
      if (artworkUrl != null) 'artwork_url': artworkUrl,
      if (ownerName != null) 'owner_name': ownerName,
      if (isCollaborative != null) 'is_collaborative': isCollaborative,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? description,
    Value<int>? trackCount,
    Value<String?>? artworkUrl,
    Value<String?>? ownerName,
    Value<bool>? isCollaborative,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      trackCount: trackCount ?? this.trackCount,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      ownerName: ownerName ?? this.ownerName,
      isCollaborative: isCollaborative ?? this.isCollaborative,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (trackCount.present) {
      map['track_count'] = Variable<int>(trackCount.value);
    }
    if (artworkUrl.present) {
      map['artwork_url'] = Variable<String>(artworkUrl.value);
    }
    if (ownerName.present) {
      map['owner_name'] = Variable<String>(ownerName.value);
    }
    if (isCollaborative.present) {
      map['is_collaborative'] = Variable<bool>(isCollaborative.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('trackCount: $trackCount, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('ownerName: $ownerName, ')
          ..write('isCollaborative: $isCollaborative, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MappingsTable extends Mappings
    with TableInfo<$MappingsTable, MappingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MappingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _spotifyTrackIdMeta = const VerificationMeta(
    'spotifyTrackId',
  );
  @override
  late final GeneratedColumn<String> spotifyTrackId = GeneratedColumn<String>(
    'spotify_track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _containerMeta = const VerificationMeta(
    'container',
  );
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
    'container',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('m4a'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    spotifyTrackId,
    videoId,
    container,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mappings';
  @override
  VerificationContext validateIntegrity(
    Insertable<MappingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('spotify_track_id')) {
      context.handle(
        _spotifyTrackIdMeta,
        spotifyTrackId.isAcceptableOrUnknown(
          data['spotify_track_id']!,
          _spotifyTrackIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_spotifyTrackIdMeta);
    }
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('container')) {
      context.handle(
        _containerMeta,
        container.isAcceptableOrUnknown(data['container']!, _containerMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {spotifyTrackId};
  @override
  MappingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MappingRow(
      spotifyTrackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spotify_track_id'],
      )!,
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_id'],
      )!,
      container: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MappingsTable createAlias(String alias) {
    return $MappingsTable(attachedDatabase, alias);
  }
}

class MappingRow extends DataClass implements Insertable<MappingRow> {
  final String spotifyTrackId;
  final String videoId;
  final String container;
  final DateTime createdAt;
  const MappingRow({
    required this.spotifyTrackId,
    required this.videoId,
    required this.container,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['spotify_track_id'] = Variable<String>(spotifyTrackId);
    map['video_id'] = Variable<String>(videoId);
    map['container'] = Variable<String>(container);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MappingsCompanion toCompanion(bool nullToAbsent) {
    return MappingsCompanion(
      spotifyTrackId: Value(spotifyTrackId),
      videoId: Value(videoId),
      container: Value(container),
      createdAt: Value(createdAt),
    );
  }

  factory MappingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MappingRow(
      spotifyTrackId: serializer.fromJson<String>(json['spotifyTrackId']),
      videoId: serializer.fromJson<String>(json['videoId']),
      container: serializer.fromJson<String>(json['container']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'spotifyTrackId': serializer.toJson<String>(spotifyTrackId),
      'videoId': serializer.toJson<String>(videoId),
      'container': serializer.toJson<String>(container),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MappingRow copyWith({
    String? spotifyTrackId,
    String? videoId,
    String? container,
    DateTime? createdAt,
  }) => MappingRow(
    spotifyTrackId: spotifyTrackId ?? this.spotifyTrackId,
    videoId: videoId ?? this.videoId,
    container: container ?? this.container,
    createdAt: createdAt ?? this.createdAt,
  );
  MappingRow copyWithCompanion(MappingsCompanion data) {
    return MappingRow(
      spotifyTrackId: data.spotifyTrackId.present
          ? data.spotifyTrackId.value
          : this.spotifyTrackId,
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      container: data.container.present ? data.container.value : this.container,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MappingRow(')
          ..write('spotifyTrackId: $spotifyTrackId, ')
          ..write('videoId: $videoId, ')
          ..write('container: $container, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(spotifyTrackId, videoId, container, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MappingRow &&
          other.spotifyTrackId == this.spotifyTrackId &&
          other.videoId == this.videoId &&
          other.container == this.container &&
          other.createdAt == this.createdAt);
}

class MappingsCompanion extends UpdateCompanion<MappingRow> {
  final Value<String> spotifyTrackId;
  final Value<String> videoId;
  final Value<String> container;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MappingsCompanion({
    this.spotifyTrackId = const Value.absent(),
    this.videoId = const Value.absent(),
    this.container = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MappingsCompanion.insert({
    required String spotifyTrackId,
    required String videoId,
    this.container = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : spotifyTrackId = Value(spotifyTrackId),
       videoId = Value(videoId),
       createdAt = Value(createdAt);
  static Insertable<MappingRow> custom({
    Expression<String>? spotifyTrackId,
    Expression<String>? videoId,
    Expression<String>? container,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (spotifyTrackId != null) 'spotify_track_id': spotifyTrackId,
      if (videoId != null) 'video_id': videoId,
      if (container != null) 'container': container,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MappingsCompanion copyWith({
    Value<String>? spotifyTrackId,
    Value<String>? videoId,
    Value<String>? container,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return MappingsCompanion(
      spotifyTrackId: spotifyTrackId ?? this.spotifyTrackId,
      videoId: videoId ?? this.videoId,
      container: container ?? this.container,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (spotifyTrackId.present) {
      map['spotify_track_id'] = Variable<String>(spotifyTrackId.value);
    }
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MappingsCompanion(')
          ..write('spotifyTrackId: $spotifyTrackId, ')
          ..write('videoId: $videoId, ')
          ..write('container: $container, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
    'last_played_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    videoId,
    filePath,
    sizeBytes,
    lastPlayedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastPlayedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoId};
  @override
  CacheEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntryRow(
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played_at'],
      )!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntryRow extends DataClass implements Insertable<CacheEntryRow> {
  final String videoId;
  final String filePath;
  final int sizeBytes;
  final DateTime lastPlayedAt;
  const CacheEntryRow({
    required this.videoId,
    required this.filePath,
    required this.sizeBytes,
    required this.lastPlayedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_id'] = Variable<String>(videoId);
    map['file_path'] = Variable<String>(filePath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      videoId: Value(videoId),
      filePath: Value(filePath),
      sizeBytes: Value(sizeBytes),
      lastPlayedAt: Value(lastPlayedAt),
    );
  }

  factory CacheEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntryRow(
      videoId: serializer.fromJson<String>(json['videoId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      lastPlayedAt: serializer.fromJson<DateTime>(json['lastPlayedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoId': serializer.toJson<String>(videoId),
      'filePath': serializer.toJson<String>(filePath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'lastPlayedAt': serializer.toJson<DateTime>(lastPlayedAt),
    };
  }

  CacheEntryRow copyWith({
    String? videoId,
    String? filePath,
    int? sizeBytes,
    DateTime? lastPlayedAt,
  }) => CacheEntryRow(
    videoId: videoId ?? this.videoId,
    filePath: filePath ?? this.filePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
  );
  CacheEntryRow copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntryRow(
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntryRow(')
          ..write('videoId: $videoId, ')
          ..write('filePath: $filePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastPlayedAt: $lastPlayedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(videoId, filePath, sizeBytes, lastPlayedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntryRow &&
          other.videoId == this.videoId &&
          other.filePath == this.filePath &&
          other.sizeBytes == this.sizeBytes &&
          other.lastPlayedAt == this.lastPlayedAt);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntryRow> {
  final Value<String> videoId;
  final Value<String> filePath;
  final Value<int> sizeBytes;
  final Value<DateTime> lastPlayedAt;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.videoId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String videoId,
    required String filePath,
    this.sizeBytes = const Value.absent(),
    required DateTime lastPlayedAt,
    this.rowid = const Value.absent(),
  }) : videoId = Value(videoId),
       filePath = Value(filePath),
       lastPlayedAt = Value(lastPlayedAt);
  static Insertable<CacheEntryRow> custom({
    Expression<String>? videoId,
    Expression<String>? filePath,
    Expression<int>? sizeBytes,
    Expression<DateTime>? lastPlayedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoId != null) 'video_id': videoId,
      if (filePath != null) 'file_path': filePath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith({
    Value<String>? videoId,
    Value<String>? filePath,
    Value<int>? sizeBytes,
    Value<DateTime>? lastPlayedAt,
    Value<int>? rowid,
  }) {
    return CacheEntriesCompanion(
      videoId: videoId ?? this.videoId,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('videoId: $videoId, ')
          ..write('filePath: $filePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlayHistoryTable extends PlayHistory
    with TableInfo<$PlayHistoryTable, PlayHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playedAtMeta = const VerificationMeta(
    'playedAt',
  );
  @override
  late final GeneratedColumn<DateTime> playedAt = GeneratedColumn<DateTime>(
    'played_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, trackId, playedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('played_at')) {
      context.handle(
        _playedAtMeta,
        playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlayHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      playedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}played_at'],
      )!,
    );
  }

  @override
  $PlayHistoryTable createAlias(String alias) {
    return $PlayHistoryTable(attachedDatabase, alias);
  }
}

class PlayHistoryRow extends DataClass implements Insertable<PlayHistoryRow> {
  final int id;
  final String trackId;
  final DateTime playedAt;
  const PlayHistoryRow({
    required this.id,
    required this.trackId,
    required this.playedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_id'] = Variable<String>(trackId);
    map['played_at'] = Variable<DateTime>(playedAt);
    return map;
  }

  PlayHistoryCompanion toCompanion(bool nullToAbsent) {
    return PlayHistoryCompanion(
      id: Value(id),
      trackId: Value(trackId),
      playedAt: Value(playedAt),
    );
  }

  factory PlayHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      trackId: serializer.fromJson<String>(json['trackId']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackId': serializer.toJson<String>(trackId),
      'playedAt': serializer.toJson<DateTime>(playedAt),
    };
  }

  PlayHistoryRow copyWith({int? id, String? trackId, DateTime? playedAt}) =>
      PlayHistoryRow(
        id: id ?? this.id,
        trackId: trackId ?? this.trackId,
        playedAt: playedAt ?? this.playedAt,
      );
  PlayHistoryRow copyWithCompanion(PlayHistoryCompanion data) {
    return PlayHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryRow(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, trackId, playedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayHistoryRow &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.playedAt == this.playedAt);
}

class PlayHistoryCompanion extends UpdateCompanion<PlayHistoryRow> {
  final Value<int> id;
  final Value<String> trackId;
  final Value<DateTime> playedAt;
  const PlayHistoryCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.playedAt = const Value.absent(),
  });
  PlayHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String trackId,
    required DateTime playedAt,
  }) : trackId = Value(trackId),
       playedAt = Value(playedAt);
  static Insertable<PlayHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? trackId,
    Expression<DateTime>? playedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (playedAt != null) 'played_at': playedAt,
    });
  }

  PlayHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? trackId,
    Value<DateTime>? playedAt,
  }) {
    return PlayHistoryCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<DateTime>(playedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $MappingsTable mappings = $MappingsTable(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  late final $PlayHistoryTable playHistory = $PlayHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    playlists,
    mappings,
    cacheEntries,
    playHistory,
  ];
}

typedef $$TracksTableCreateCompanionBuilder = TracksCompanion Function({
  required String id,
  required String title,
  required String artists,
  Value<String?> album,
  Value<int> durationMs,
  Value<String?> artworkUrl,
  Value<String?> isrc,
  Value<DateTime?> addedAt,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$TracksTableUpdateCompanionBuilder = TracksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> artists,
  Value<String?> album,
  Value<int> durationMs,
  Value<String?> artworkUrl,
  Value<String?> isrc,
  Value<DateTime?> addedAt,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$TracksTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artists => $composableBuilder(
    column: $table.artists,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isrc => $composableBuilder(
    column: $table.isrc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artists => $composableBuilder(
    column: $table.artists,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isrc => $composableBuilder(
    column: $table.isrc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artists =>
      $composableBuilder(column: $table.artists, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get isrc =>
      $composableBuilder(column: $table.isrc, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TracksTable,
          TrackRow,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (TrackRow, BaseReferences<_$AppDatabase, $TracksTable, TrackRow>),
          TrackRow,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$AppDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artists = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                Value<String?> isrc = const Value.absent(),
                Value<DateTime?> addedAt = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                title: title,
                artists: artists,
                album: album,
                durationMs: durationMs,
                artworkUrl: artworkUrl,
                isrc: isrc,
                addedAt: addedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String artists,
                Value<String?> album = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                Value<String?> isrc = const Value.absent(),
                Value<DateTime?> addedAt = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion.insert(
                id: id,
                title: title,
                artists: artists,
                album: album,
                durationMs: durationMs,
                artworkUrl: artworkUrl,
                isrc: isrc,
                addedAt: addedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TracksTable, TrackRow>(table),
                  BaseReferences<_$AppDatabase, $TracksTable, TrackRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TracksTable,
      TrackRow,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (TrackRow, BaseReferences<_$AppDatabase, $TracksTable, TrackRow>),
      TrackRow,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder = PlaylistsCompanion Function({
  required String id,
  required String name,
  Value<String> description,
  Value<int> trackCount,
  Value<String?> artworkUrl,
  Value<String?> ownerName,
  Value<bool> isCollaborative,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$PlaylistsTableUpdateCompanionBuilder = PlaylistsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> description,
  Value<int> trackCount,
  Value<String?> artworkUrl,
  Value<String?> ownerName,
  Value<bool> isCollaborative,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackCount => $composableBuilder(
    column: $table.trackCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerName => $composableBuilder(
    column: $table.ownerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCollaborative => $composableBuilder(
    column: $table.isCollaborative,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackCount => $composableBuilder(
    column: $table.trackCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerName => $composableBuilder(
    column: $table.ownerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCollaborative => $composableBuilder(
    column: $table.isCollaborative,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackCount => $composableBuilder(
    column: $table.trackCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerName =>
      $composableBuilder(column: $table.ownerName, builder: (column) => column);

  GeneratedColumn<bool> get isCollaborative => $composableBuilder(
    column: $table.isCollaborative,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          PlaylistRow,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (
            PlaylistRow,
            BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistRow>,
          ),
          PlaylistRow,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> trackCount = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                Value<String?> ownerName = const Value.absent(),
                Value<bool> isCollaborative = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                id: id,
                name: name,
                description: description,
                trackCount: trackCount,
                artworkUrl: artworkUrl,
                ownerName: ownerName,
                isCollaborative: isCollaborative,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> description = const Value.absent(),
                Value<int> trackCount = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                Value<String?> ownerName = const Value.absent(),
                Value<bool> isCollaborative = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                name: name,
                description: description,
                trackCount: trackCount,
                artworkUrl: artworkUrl,
                ownerName: ownerName,
                isCollaborative: isCollaborative,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistsTable, PlaylistRow>(table),
                  BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      PlaylistRow,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (
        PlaylistRow,
        BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistRow>,
      ),
      PlaylistRow,
      PrefetchHooks Function()
    >;
typedef $$MappingsTableCreateCompanionBuilder = MappingsCompanion Function({
  required String spotifyTrackId,
  required String videoId,
  Value<String> container,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$MappingsTableUpdateCompanionBuilder = MappingsCompanion Function({
  Value<String> spotifyTrackId,
  Value<String> videoId,
  Value<String> container,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$MappingsTableFilterComposer
    extends Composer<_$AppDatabase, $MappingsTable> {
  $$MappingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get spotifyTrackId => $composableBuilder(
    column: $table.spotifyTrackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MappingsTableOrderingComposer
    extends Composer<_$AppDatabase, $MappingsTable> {
  $$MappingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get spotifyTrackId => $composableBuilder(
    column: $table.spotifyTrackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MappingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MappingsTable> {
  $$MappingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get spotifyTrackId => $composableBuilder(
    column: $table.spotifyTrackId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MappingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MappingsTable,
          MappingRow,
          $$MappingsTableFilterComposer,
          $$MappingsTableOrderingComposer,
          $$MappingsTableAnnotationComposer,
          $$MappingsTableCreateCompanionBuilder,
          $$MappingsTableUpdateCompanionBuilder,
          (
            MappingRow,
            BaseReferences<_$AppDatabase, $MappingsTable, MappingRow>,
          ),
          MappingRow,
          PrefetchHooks Function()
        > {
  $$MappingsTableTableManager(_$AppDatabase db, $MappingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MappingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MappingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MappingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> spotifyTrackId = const Value.absent(),
                Value<String> videoId = const Value.absent(),
                Value<String> container = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MappingsCompanion(
                spotifyTrackId: spotifyTrackId,
                videoId: videoId,
                container: container,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String spotifyTrackId,
                required String videoId,
                Value<String> container = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => MappingsCompanion.insert(
                spotifyTrackId: spotifyTrackId,
                videoId: videoId,
                container: container,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MappingsTable, MappingRow>(table),
                  BaseReferences<_$AppDatabase, $MappingsTable, MappingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MappingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MappingsTable,
      MappingRow,
      $$MappingsTableFilterComposer,
      $$MappingsTableOrderingComposer,
      $$MappingsTableAnnotationComposer,
      $$MappingsTableCreateCompanionBuilder,
      $$MappingsTableUpdateCompanionBuilder,
      (MappingRow, BaseReferences<_$AppDatabase, $MappingsTable, MappingRow>),
      MappingRow,
      PrefetchHooks Function()
    >;
typedef $$CacheEntriesTableCreateCompanionBuilder =
    CacheEntriesCompanion Function({
      required String videoId,
      required String filePath,
      Value<int> sizeBytes,
      required DateTime lastPlayedAt,
      Value<int> rowid,
    });
typedef $$CacheEntriesTableUpdateCompanionBuilder =
    CacheEntriesCompanion Function({
      Value<String> videoId,
      Value<String> filePath,
      Value<int> sizeBytes,
      Value<DateTime> lastPlayedAt,
      Value<int> rowid,
    });

class $$CacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );
}

class $$CacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheEntriesTable,
          CacheEntryRow,
          $$CacheEntriesTableFilterComposer,
          $$CacheEntriesTableOrderingComposer,
          $$CacheEntriesTableAnnotationComposer,
          $$CacheEntriesTableCreateCompanionBuilder,
          $$CacheEntriesTableUpdateCompanionBuilder,
          (
            CacheEntryRow,
            BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntryRow>,
          ),
          CacheEntryRow,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableManager(_$AppDatabase db, $CacheEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> videoId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> lastPlayedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion(
                videoId: videoId,
                filePath: filePath,
                sizeBytes: sizeBytes,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String videoId,
                required String filePath,
                Value<int> sizeBytes = const Value.absent(),
                required DateTime lastPlayedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion.insert(
                videoId: videoId,
                filePath: filePath,
                sizeBytes: sizeBytes,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheEntriesTable, CacheEntryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CacheEntriesTable,
                    CacheEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheEntriesTable,
      CacheEntryRow,
      $$CacheEntriesTableFilterComposer,
      $$CacheEntriesTableOrderingComposer,
      $$CacheEntriesTableAnnotationComposer,
      $$CacheEntriesTableCreateCompanionBuilder,
      $$CacheEntriesTableUpdateCompanionBuilder,
      (
        CacheEntryRow,
        BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntryRow>,
      ),
      CacheEntryRow,
      PrefetchHooks Function()
    >;
typedef $$PlayHistoryTableCreateCompanionBuilder =
    PlayHistoryCompanion Function({
      Value<int> id,
      required String trackId,
      required DateTime playedAt,
    });
typedef $$PlayHistoryTableUpdateCompanionBuilder =
    PlayHistoryCompanion Function({
      Value<int> id,
      Value<String> trackId,
      Value<DateTime> playedAt,
    });

class $$PlayHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<DateTime> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);
}

class $$PlayHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayHistoryTable,
          PlayHistoryRow,
          $$PlayHistoryTableFilterComposer,
          $$PlayHistoryTableOrderingComposer,
          $$PlayHistoryTableAnnotationComposer,
          $$PlayHistoryTableCreateCompanionBuilder,
          $$PlayHistoryTableUpdateCompanionBuilder,
          (
            PlayHistoryRow,
            BaseReferences<_$AppDatabase, $PlayHistoryTable, PlayHistoryRow>,
          ),
          PlayHistoryRow,
          PrefetchHooks Function()
        > {
  $$PlayHistoryTableTableManager(_$AppDatabase db, $PlayHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<DateTime> playedAt = const Value.absent(),
              }) => PlayHistoryCompanion(
                id: id,
                trackId: trackId,
                playedAt: playedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String trackId,
                required DateTime playedAt,
              }) => PlayHistoryCompanion.insert(
                id: id,
                trackId: trackId,
                playedAt: playedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlayHistoryTable, PlayHistoryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PlayHistoryTable,
                    PlayHistoryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayHistoryTable,
      PlayHistoryRow,
      $$PlayHistoryTableFilterComposer,
      $$PlayHistoryTableOrderingComposer,
      $$PlayHistoryTableAnnotationComposer,
      $$PlayHistoryTableCreateCompanionBuilder,
      $$PlayHistoryTableUpdateCompanionBuilder,
      (
        PlayHistoryRow,
        BaseReferences<_$AppDatabase, $PlayHistoryTable, PlayHistoryRow>,
      ),
      PlayHistoryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$MappingsTableTableManager get mappings =>
      $$MappingsTableTableManager(_db, _db.mappings);
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
  $$PlayHistoryTableTableManager get playHistory =>
      $$PlayHistoryTableTableManager(_db, _db.playHistory);
}
