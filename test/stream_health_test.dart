import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/youtube/stream_health.dart';

/// A stand-in for googlevideo that can behave the way the real one does,
/// including the behaviour that started all of this: serving the first
/// megabyte and refusing everything after it.
class _FakeVideoServer {
  _FakeVideoServer(this._respond);

  /// Answers one request. Returns the status code to send back.
  final int Function(int? rangeStart, int? rangeEnd) _respond;

  late HttpServer _server;
  final List<String?> ranges = <String?>[];
  int _requests = 0;

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      _requests++;
      final header = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(header);
      var start = <int?>[null, null];
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(header ?? '');
      if (match != null) {
        start = <int?>[
          int.tryParse(match.group(1)!),
          match.group(2)!.isEmpty ? null : int.tryParse(match.group(2)!),
        ];
      }
      final status = _respond(start[0], start[1]);
      if (status == 0) return; // Hang: never answer, for the timeout case.
      request.response.statusCode = status;
      if (status == 206 || status == 200) {
        request.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');
        request.response.add(List<int>.filled(1024, 0));
      }
      await request.response.close();
    });
    return 'http://127.0.0.1:${_server.port}/videoplayback';
  }

  int get requests => _requests;

  Future<void> stop() => _server.close(force: true);
}

void main() {
  const oneMegabyte = 1024 * 1024;

  group('StreamHealth.check', () {
    test('asks for bytes past the first megabyte', () async {
      final server = _FakeVideoServer((_, _) => 206);
      final url = await server.start();
      addTearDown(server.stop);

      await const StreamHealth().check(url);

      expect(
        server.ranges.single,
        'bytes=$oneMegabyte-${oneMegabyte + 1023}',
        reason: 'a range inside the first megabyte is served even by a URL '
            'YouTube is not really serving, so it proves nothing',
      );
    });

    test('a stream that serves the whole file is servable', () async {
      final server = _FakeVideoServer((_, _) => 206);
      final url = await server.start();
      addTearDown(server.stop);

      expect(await const StreamHealth().check(url), StreamVerdict.serves);
    });

    test('the first-megabyte-only URL YouTube hands out is a refusal', () async {
      // What android and ios URLs really do: fine up to one megabyte, 403 after.
      final server = _FakeVideoServer(
        (start, _) => (start ?? 0) < oneMegabyte ? 206 : 403,
      );
      final url = await server.start();
      addTearDown(server.stop);

      expect(await const StreamHealth().check(url), StreamVerdict.refused);
    });

    test('a file shorter than the probe offset is servable', () async {
      // 416 means the whole file is inside the window we can reach.
      final server = _FakeVideoServer((_, _) => 416);
      final url = await server.start();
      addTearDown(server.stop);

      expect(await const StreamHealth().check(url), StreamVerdict.serves);
    });

    test('a server error is unknown, not a refusal', () async {
      final server = _FakeVideoServer((_, _) => 500);
      final url = await server.start();
      addTearDown(server.stop);

      expect(
        await const StreamHealth().check(url),
        StreamVerdict.unknown,
        reason: 'marking a client dead because of a bad moment would throw '
            'away the only thing that works',
      );
    });

    test('a server that never answers is unknown', () async {
      final server = _FakeVideoServer((_, _) => 0);
      final url = await server.start();
      addTearDown(server.stop);

      // The probe's own timeout is what ends this, well inside the test's.
      expect(await const StreamHealth().check(url), StreamVerdict.unknown);
    });

    test('an unresolvable URL is unknown rather than a crash', () async {
      expect(
        await const StreamHealth().check('https://127.0.0.1:1/nothing'),
        StreamVerdict.unknown,
      );
    });
  });
}
