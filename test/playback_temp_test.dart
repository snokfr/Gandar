import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/playback/audio_engine/playback_temp.dart';
import 'package:path/path.dart' as p;

/// media_kit writes a playlist file into whatever `Directory.systemTemp` says
/// before every playback, so these tests are about the one question that
/// matters: can the app create that file where media_kit will look for it?
void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('gandar-temp-test');
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('adopts a directory it can write to, creating it if needed', () async {
    final target = Directory(p.join(scratch.path, 'nested', 'temp'));

    final result = await PlaybackTemp.forDirectory(target);

    expect(result.writable, isTrue);
    expect(result.directory.path, target.path);
    expect(target.existsSync(), isTrue);
    // The probe is cleaned up: nothing but media_kit's own files live here.
    expect(target.listSync(), isEmpty);
  });

  test('Directory.systemTemp answers with the adopted directory', () async {
    final target = Directory(p.join(scratch.path, 'temp'));
    final result = await PlaybackTemp.forDirectory(target);

    final seen = await result.withTempDirectory(
      () async => Directory.systemTemp.path,
    );

    expect(seen, target.path);
    // Outside the zone the real system temp directory is back in force.
    expect(Directory.systemTemp.path, isNot(target.path));
  });

  test('media_kit can create its playlist file inside the zone', () async {
    final target = Directory(p.join(scratch.path, 'temp'));
    final result = await PlaybackTemp.forDirectory(target);

    // Exactly what package:safe_local_storage does for media_kit: a bare UUID
    // name, created through the overwritten system temp directory.
    final file = await result.withTempDirectory(() async {
      final f = File(p.join(Directory.systemTemp.path, 'f1652055-probe'));
      await f.create_();
      return f;
    });

    expect(file.existsSync(), isTrue);
    expect(p.dirname(file.path), target.path);
  });

  test(
    'falls back to the system temp directory when it cannot write',
    () async {
      // A path whose parent is a file can never be created.
      final blocker = File(p.join(scratch.path, 'not-a-directory'))
        ..writeAsStringSync('x');
      final target = Directory(p.join(blocker.path, 'temp'));

      final result = await PlaybackTemp.forDirectory(target);

      expect(result.writable, isFalse);
      expect(result.directory.path, Directory.systemTemp.path);
      expect(result.status, contains('not writable'));
    },
  );
}

/// The subset of `safe_local_storage`'s extension that media_kit relies on.
extension on File {
  Future<void> create_() => create(recursive: true);
}
