import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:gandar/data/storage/app_database.dart';

/// A Dio adapter that answers every request from a scripted handler.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a JSON response body.
ResponseBody jsonBody(Object payload, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// A Dio whose transport is replaced by [adapter].
Dio dioWith(FakeHttpAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

/// Whether an in-memory drift database can actually be opened on this host.
///
/// `package:sqlite3` 3.5+ bundles SQLite through Dart build hooks (native
/// assets), so this normally succeeds; the probe exists so tests can report a
/// clear reason instead of failing with a confusing loader error.
bool _sqliteReady = false;
bool _sqliteAttempted = false;

/// Probes sqlite by opening and closing a real in-memory database.
bool get sqliteAvailable {
  if (_sqliteAttempted) return _sqliteReady;
  _sqliteAttempted = true;
  try {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    db.customStatement('SELECT 1');
    // ignore: unawaited_futures
    db.close();
    _sqliteReady = true;
  } catch (_) {
    _sqliteReady = false;
  }
  return _sqliteReady;
}

/// Reason string to pass to `test(..., skip: ...)`.
String? get sqliteSkipReason => sqliteAvailable
    ? null
    : 'SQLite native assets are unavailable on this host.';
