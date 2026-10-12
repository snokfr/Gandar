import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/storage/app_directory.dart';
import '../../data/mashup/mashup_store.dart';
import '../../domain/models/mashup.dart';
import '../../domain/models/resolved_stream.dart';
import '../../domain/models/track.dart';
import 'export_cancelled.dart';
import 'export_job.dart';
import 'mpv_pcm.dart';

/// What the mashup screen calls to write a mix to a file.
///
/// A function rather than an object, because that is the whole of what the
/// screen needs from an export and it can then be replaced wholesale in a test.
typedef MashupExport =
    Future<ExportOutcome> Function({
      required Mashup mashup,
      required String name,
      void Function(ExportProgress progress)? onProgress,
      bool Function()? isCancelled,
    });

/// Builds the real export: resolve every song, decode and sum them in a
/// background isolate, and leave a WAV in the exports folder.
///
/// ## Why an isolate
///
/// Decoding four minutes of audio and summing ten million samples is seconds of
/// solid arithmetic. On the interface's own isolate that is a frozen window with
/// no progress bar, which is indistinguishable from a crash. So the work runs in
/// an isolate of its own — and not through media_kit, which builds players
/// around an audio output on a device and has no way to ask for a file.
///
/// ## How cancelling works
///
/// The child cannot be interrupted by a message, because the job it is running
/// never returns to its event loop. So the signal is a *file*: the parent writes
/// one when the user asks to stop, and the child — which can check the file
/// system from inside the loop — notices within a poll and unwinds through the
/// same path as any other part, closing mpv and deleting its half-written WAV on
/// the way out. Killing the isolate instead would leave libmpv's own threads
/// running in the process with nothing left to stop them.
MashupExport buildMashupExporter({
  required Future<ResolvedStream> Function(Track track) resolve,
  Directory? exportsDirectory,
  String library = defaultMpvLibrary,
  SliceDecoder? decode,
}) {
  return ({
    required Mashup mashup,
    required String name,
    void Function(ExportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (mashup.parts.isEmpty) {
      throw StateError('there is nothing in this mix to export');
    }

    // Resolving is a small share of the work — usually a cache lookup, at worst
    // a YouTube extraction — so it owns the first slice of the bar and the job
    // owns the rest.
    const resolveShare = 0.05;
    final parts = <ExportPart>[];
    final skipped = <String>[];
    for (var index = 0; index < mashup.parts.length; index++) {
      final part = mashup.parts[index];
      onProgress?.call(
        ExportProgress(
          stage: 'Looking up “${part.title}”',
          partIndex: index + 1,
          partCount: mashup.parts.length,
          fraction: (index / mashup.parts.length) * resolveShare,
        ),
      );
      try {
        final stream = await resolve(part.track);
        parts.add(
          ExportPart(
            title: part.title,
            url: stream.url,
            headers: stream.headers,
            start: part.start,
            // A part whose source length was never known runs to wherever the
            // audio ends, exactly as it does when the mix is played.
            end: part.playsToTheEnd ? null : part.end,
            offset: part.offset,
            gain: part.gain,
          ),
        );
      } catch (e) {
        final reason = '$e'.replaceAll(RegExp(r'\s+'), ' ').trim();
        skipped.add('“${part.title}” could not be found: $reason');
        AppLogger.instance.warn(
          'mashup',
          'export: could not resolve "${part.title}"',
          error: e,
        );
      }
    }
    if (parts.isEmpty) {
      throw StateError(
        'none of the songs in this mix could be found, so there is nothing to '
        'export',
      );
    }

    final directory = exportsDirectory ?? await AppDirectory.exportsDirectory();
    final output = File(
      p.join(directory.path, '${MashupStore.safeName(name)}.wav'),
    );
    final scratch = Directory(p.join(directory.path, '.exporting'));
    // A leftover scratch folder is the debris of an interrupted export: cleared
    // here so a part from a previous run can never be read as this one's.
    if (scratch.existsSync()) {
      try {
        scratch.deleteSync(recursive: true);
      } catch (_) {
        // A file still held open by a dead export; the new parts have their own
        // names, so it can stay.
      }
    }
    scratch.createSync(recursive: true);
    final cancelFlag = File(p.join(scratch.path, 'cancelled'));
    if (cancelFlag.existsSync()) cancelFlag.deleteSync();
    if (isCancelled?.call() ?? false) throw const ExportCancelled();

    final progress = ReceivePort();
    final errors = ReceivePort();
    ExportOutcome? outcome;
    Object? failure;
    // An error that reaches the isolate boundary means the child died rather
    // than reported, so it is kept as the failure to explain.
    errors.listen((Object? message) {
      failure ??= StateError('the export stopped unexpectedly: $message');
    }, onError: (Object e) {
      failure ??= StateError('the export stopped unexpectedly: $e');
    });
    final isolate = await Isolate.spawn<_ExportRequest>(
      _runJobInIsolate,
      _ExportRequest(
        progress.sendPort,
        parts: parts,
        outputPath: output.path,
        scratchPath: scratch.path,
        library: library,
        decode: decode,
      ),
      onError: errors.sendPort,
      errorsAreFatal: false,
    );

    Timer? watcher;
    if (isCancelled != null) {
      watcher = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (!cancelFlag.existsSync() && isCancelled()) {
          cancelFlag.writeAsStringSync('cancel');
        }
      });
    }

    var cancelled = false;
    try {
      await for (final message in progress) {
        if (message is ExportProgress) {
          onProgress?.call(
            ExportProgress(
              stage: message.stage,
              partIndex: message.partIndex,
              partCount: message.partCount,
              fraction:
                  resolveShare + message.fraction * (1 - resolveShare),
            ),
          );
          continue;
        }
        if (message is ExportOutcome) {
          outcome = message;
          break;
        }
        if (message is _JobCancelled) {
          cancelled = true;
          break;
        }
        if (message is _JobFailure) {
          failure = StateError(message.message);
          break;
        }
      }
    } finally {
      watcher?.cancel();
      isolate.kill(priority: Isolate.immediate);
      progress.close();
      errors.close();
      try {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      } catch (_) {
        // Best effort: a part file still open by a dying mpv is not worth
        // failing an export that already succeeded over.
      }
    }

    if (cancelled) throw const ExportCancelled();
    final broke = failure;
    if (broke != null) throw broke;
    final finished = outcome;
    if (finished == null) {
      throw StateError('the export stopped without finishing');
    }
    for (final warning in skipped) {
      finished.warnings.insert(0, warning);
    }
    AppLogger.instance.info(
      'mashup',
      'exported "${finished.path}" — ${finished.duration.inMilliseconds} ms, '
          '${finished.sampleRate} Hz, peak ${finished.peak.toStringAsFixed(3)}, '
          '${finished.clippedSamples} clipped samples',
    );
    return finished;
  };
}

/// One export, described either side of the isolate boundary.
///
/// Plain data only, so it can be copied into the child — no players, no
/// repositories, nothing that belongs to the interface.
class _ExportRequest {
  _ExportRequest(
    this.replyTo, {
    required this.parts,
    required this.outputPath,
    required this.scratchPath,
    required this.library,
    this.decode,
  });

  final SendPort replyTo;
  final List<ExportPart> parts;
  final String outputPath;
  final String scratchPath;
  final String library;

  /// A stand-in decoder, for tests. It has to be a top-level function rather
  /// than a closure over test state, because it is sent to the child isolate and
  /// a closure that captures anything unsendable cannot be.
  final SliceDecoder? decode;
}

class _JobCancelled {
  const _JobCancelled();
}

class _JobFailure {
  _JobFailure(this.message);

  final String message;
}

/// The child isolate: run the job, and report progress and the outcome.
///
/// Every failure is sent back as a message rather than thrown at the isolate
/// boundary, so the parent always has something to say rather than an
/// unhandled-error dump.
void _runJobInIsolate(_ExportRequest request) {
  final cancelFlag = File(p.join(request.scratchPath, 'cancelled'));
  try {
    final outcome = runExportJob(
      parts: request.parts,
      outputPath: request.outputPath,
      scratch: Directory(request.scratchPath),
      library: request.library,
      onProgress: request.replyTo.send,
      isCancelled: cancelFlag.existsSync,
      decode: request.decode,
    );
    request.replyTo.send(outcome);
  } on ExportCancelled {
    request.replyTo.send(const _JobCancelled());
  } catch (e) {
    request.replyTo.send(_JobFailure('$e'));
  }
}
