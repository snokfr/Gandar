import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/storage/app_directory.dart';
import 'package:gandar/playback/audio_engine/playback_temp.dart';
import 'package:path/path.dart' as p;

/// These tests are about one failure mode: the platform lookup for the app's
/// data directory returns nothing, and everything that stores a file — the
/// library database, the log, imports, playback — has to keep working.
void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('gandar-appdir');
    AppDirectory.lastChoice = null;
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  group('AppDirectory.pick', () {
    test('takes the first candidate it can write to', () async {
      final first = Directory(p.join(sandbox.path, 'first'));
      final second = Directory(p.join(sandbox.path, 'second'));

      final picked = await AppDirectory.pick(<Directory>[first, second]);

      expect(picked.path, first.path);
      expect(first.existsSync(), isTrue, reason: 'it creates what it adopts');
      expect(
        first.listSync(),
        isEmpty,
        reason: 'the writability probe is cleaned up after itself',
      );
      expect(
        AppDirectory.lastChoice,
        first.path,
        reason:
            'the log should name the directory without calling it a '
            'fallback when it was the first choice',
      );
    });

    test('falls past a candidate it cannot write to, and says which', () async {
      // A path whose parent is a file can never be created.
      final blocker = File(p.join(sandbox.path, 'not-a-directory'))
        ..writeAsStringSync('x');
      final unusable = Directory(p.join(blocker.path, 'inside'));
      final usable = Directory(p.join(sandbox.path, 'usable'));

      final picked = await AppDirectory.pick(<Directory>[unusable, usable]);

      expect(picked.path, usable.path);
      expect(AppDirectory.lastChoice, contains(usable.path));
      expect(
        AppDirectory.lastChoice,
        contains('fell back past'),
        reason: 'a silent fallback is how the temp-directory bug hid',
      );
      expect(AppDirectory.lastChoice, contains(unusable.path));
    });

    test('keeps the system temp directory as an honest last resort', () async {
      final blocker = File(p.join(sandbox.path, 'blocker'))
        ..writeAsStringSync('x');

      final picked = await AppDirectory.pick(<Directory>[
        Directory(p.join(blocker.path, 'one')),
        Directory(p.join(blocker.path, 'two')),
      ]);

      expect(picked.path, Directory.systemTemp.path);
      expect(AppDirectory.lastChoice, contains('nothing was writable'));
    });
  });

  group('PlaybackTemp.ensure', () {
    test('hands playback a writable directory of its own', () async {
      final prepared = await PlaybackTemp.ensure();

      expect(
        prepared.writable,
        isTrue,
        reason:
            'every candidate failed on a machine whose own data directory '
            'works, which is the state that produced "Access is denied" for '
            'every track: ${prepared.status}',
      );
      expect(
        prepared.directory.path,
        isNot(Directory.systemTemp.path),
        reason: 'the system temp directory is the one that refuses the write',
      );

      final written = await prepared.withTempDirectory(
        () async => Directory.systemTemp.path,
      );
      expect(written, prepared.directory.path);
    });
  });
}
