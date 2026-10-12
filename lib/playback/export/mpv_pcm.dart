import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import 'export_cancelled.dart';
import 'pcm.dart';
import 'wav.dart';

/// The libmpv this app is bundled with, next to the executable.
///
/// media_kit loads the same file for playback; this looks it up by name for the
/// same reason that works there — Windows searches the directory the program
/// was loaded from before anywhere else.
const String defaultMpvLibrary = 'libmpv-2.dll';

/// Decodes one slice of one source into PCM, through mpv's PCM writer.
///
/// ## Why a second mpv, and why `ao=pcm`
///
/// The mix is normally made by one player per part, summed by the operating
/// system's mixer — see [MashupMixer]. That is right for playing and useless for
/// exporting, because the system mixer's output is a speaker, not a file. The
/// bundled libavfilter has no `amix` to sum with and no encoder to write MP3, so
/// the export cannot go through a filter graph either way.
///
/// What *is* there is mpv's `pcm` audio output, which decodes the source and
/// writes the samples into a WAV file instead of to a device. It needs no
/// filters, no encoder and no output device. So the export decodes each part's
/// slice to a WAV of its own, and the summing is done in Dart by [mixLayers],
/// where it is arithmetic that can be read and tested rather than a black box.
///
/// The decode runs on mpv's own thread; this function only polls for the end of
/// the file, which is why it is safe to call from a step that must not freeze
/// the interface — but it does block for up to [pollInterval] at a time, so the
/// app runs it in a background isolate (see `MashupExporter`).
PcmAudio decodeSliceToPcm({
  required String url,
  required Map<String, String> headers,
  required Duration start,
  required Duration? end,
  required File target,
  String library = defaultMpvLibrary,
  Duration timeoutPadding = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 20),
  bool Function()? isCancelled,
  bool trace = false,
}) {
  target.parent.createSync(recursive: true);
  final mpv = _Mpv.open(library);
  final handle = mpv.create();
  if (handle == nullptr) {
    throw StateError('mpv could not be created ($library)');
  }
  // Anything mpv writes into the file is read back by the caller, so the file
  // itself is part of the contract: it is deleted here on every path, including
  // the failing ones, so a refused part cannot leave a half-written WAV behind
  // that a later export might pick up.
  try {
    final options = <String, String>{
      // The whole point: write the decoded samples to this file instead of to a
      // sound device.
      'ao': 'pcm',
      'ao-pcm-file': target.path,
      'ao-pcm-waveheader': 'yes',
      // Each part gets its own file, and appending to a leftover one would mix
      // yesterday's export into today's.
      'ao-pcm-append': 'no',
      'vo': 'null',
      'vid': 'no',
      'audio-display': 'no',
      'config': 'no',
      // The slice, as a pair of file-local options set before the file is
      // loaded. They are what keeps the export to the part the user chose
      // without touching a filter — this build has no `atrim` — and they are set
      // here rather than passed to `loadfile`, because a fresh mpv is created
      // per part and there is nothing for the range to leak into. (mpv's
      // `loadfile` also takes an options string, but that is a second syntax to
      // get wrong for no gain.)
      'start': _seconds(start),
      if (end != null) 'end': _seconds(end),
      // Quiet by default — a decode that works has nothing to say — and noisy
      // when asked, because when one does not work, mpv's own account of why is
      // the only account there is.
      'terminal': trace ? 'yes' : 'no',
      'msg-level': trace ? 'all=v' : 'all=error',
      'keep-open': 'no',
      // The decode is not being listened to, so it is not paced to real time.
      'audio-pitch-correction': 'no',
    };
    if (headers.isNotEmpty) {
      options['http-header-fields'] = headers.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(',');
    }
    for (final entry in options.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      try {
        final result = mpv.setOption(handle, name, value);
        // An option this build does not know is not fatal in itself, but the
        // two that decide whether a single sample can be written are: a wrong
        // `ao` would send the audio to a speaker and hand back an empty file.
        if (result < 0 && (entry.key == 'ao' || entry.key == 'ao-pcm-file')) {
          throw StateError(
            'mpv refused --${entry.key}: ${mpv.errorText(result)}',
          );
        }
      } finally {
        malloc.free(name);
        malloc.free(value);
      }
    }

    final initialized = mpv.initialize(handle);
    if (initialized < 0) {
      throw StateError('mpv could not start: ${mpv.errorText(initialized)}');
    }

    final loaded = mpv.command(handle, <String>['loadfile', url, 'replace']);
    if (loaded < 0) {
      throw StateError('mpv could not open $url: ${mpv.errorText(loaded)}');
    }

    final deadline = DateTime.now().add(
      _expectedDuration(start, end) + timeoutPadding,
    );
    while (true) {
      final event = mpv.waitEvent(handle, pollInterval);
      // Cancellation is checked in this loop rather than between parts, so
      // abandoning an export stops the decode within one poll — and stops it
      // through the same `finally` below, which is the only place mpv and the
      // half-written file are let go.
      if (isCancelled?.call() ?? false) throw const ExportCancelled();
      if (event != nullptr) {
        final id = event.cast<Int32>().value;
        if (id == _Mpv.endFile) {
          // The second int of `mpv_event` is the error code: 0 is the end of
          // the file, anything else means nothing (or not everything) decoded.
          final error = event.cast<Int32>()[1];
          if (error != 0) {
            throw StateError(
              'mpv could not decode $url: ${mpv.errorText(error)}',
            );
          }
          break;
        }
        if (id == _Mpv.shutdown) {
          throw StateError('mpv shut down while decoding $url');
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'mpv did not finish decoding $url within '
          '${_expectedDuration(start, end) + timeoutPadding}',
        );
      }
    }

    final bytes = target.readAsBytesSync();
    if (bytes.length <= 44) {
      throw StateError('mpv wrote no audio for $url');
    }
    return readWavPcm(bytes);
  } finally {
    mpv.terminateDestroy(handle);
    if (target.existsSync()) target.deleteSync();
  }
}

/// How long a slice is expected to take, used only to bound the wait.
///
/// An unknown end is a part that plays to the end of its source, which could be
/// anything, so the wait is generous rather than exact: the cost of waiting
/// longer than necessary is nothing, and the cost of cutting off a slow download
/// is a half-written part.
Duration _expectedDuration(Duration start, Duration? end) {
  if (end == null) return const Duration(minutes: 20);
  final length = end - start;
  return length > Duration.zero ? length : const Duration(minutes: 20);
}

String _seconds(Duration duration) {
  final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  return (seconds < 0 ? 0.0 : seconds).toStringAsFixed(3);
}

/// The handful of libmpv entry points an export needs.
///
/// Deliberately not media_kit: its player is built around an audio output on a
/// device, and its public surface has no way to ask for a file. These calls are
/// the documented client API, and the option strings are the documented options
/// of mpv's PCM writer.
class _Mpv {
  _Mpv(this._lib) {
    _create = _lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'mpv_create',
        );
    _setOptionString = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
    >('mpv_set_option_string');
    _initialize = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('mpv_initialize');
    _command = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>),
      int Function(Pointer<Void>, Pointer<Pointer<Utf8>>)
    >('mpv_command');
    _waitEvent = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Double),
      Pointer<Void> Function(Pointer<Void>, double)
    >('mpv_wait_event');
    _errorString = _lib.lookupFunction<
      Pointer<Utf8> Function(Int32),
      Pointer<Utf8> Function(int)
    >('mpv_error_string');
    _terminateDestroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('mpv_terminate_destroy');
  }

  /// `MPV_EVENT_END_FILE`.
  static const int endFile = 7;

  /// `MPV_EVENT_SHUTDOWN`.
  static const int shutdown = 1;

  static final Map<String, _Mpv> _loaded = <String, _Mpv>{};

  /// Loads the library once per path, so a mix of six parts opens one module.
  static _Mpv open(String path) {
    final cached = _loaded[path];
    if (cached != null) return cached;
    try {
      return _loaded[path] = _Mpv(DynamicLibrary.open(path));
    } catch (e) {
      throw StateError(
        'could not load $path: $e\n'
        'The export needs the libmpv next to the app; when running from a '
        'checkout, point GANDAR_LIBMPV at the built libmpv-2.dll.',
      );
    }
  }

  final DynamicLibrary _lib;

  late final Pointer<Void> Function() _create;

  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
  _setOptionString;

  late final int Function(Pointer<Void>) _initialize;

  late final int Function(Pointer<Void>, Pointer<Pointer<Utf8>>) _command;

  late final Pointer<Void> Function(Pointer<Void>, double) _waitEvent;

  late final Pointer<Utf8> Function(int) _errorString;

  late final void Function(Pointer<Void>) _terminateDestroy;

  /// Makes a player. Null when there is no memory for one.
  Pointer<Void> create() => _create();

  /// Sets an option, which must happen before [initialize].
  int setOption(Pointer<Void> handle, Pointer<Utf8> name, Pointer<Utf8> value) =>
      _setOptionString(handle, name, value);

  int initialize(Pointer<Void> handle) => _initialize(handle);

  /// Runs [args] as an mpv command, returning its error code.
  int command(Pointer<Void> handle, List<String> args) {
    final argv = calloc<Pointer<Utf8>>(args.length + 1);
    try {
      for (var i = 0; i < args.length; i++) {
        argv[i] = args[i].toNativeUtf8();
      }
      argv[args.length] = nullptr;
      try {
        return _command(handle, argv);
      } finally {
        for (var i = 0; i < args.length; i++) {
          malloc.free(argv[i]);
        }
      }
    } finally {
      calloc.free(argv);
    }
  }

  /// Polls for the next event, waiting up to [timeout]. Null when there is
  /// nothing to report yet.
  ///
  /// The returned pointer is an `mpv_event`, and only its first two fields are
  /// read — the event id and the error code, which are two 32-bit ints at its
  /// start. Nothing else in the struct is touched, so a change to its layout
  /// further along cannot turn a decoded part into garbage.
  Pointer<Void> waitEvent(Pointer<Void> handle, Duration timeout) => _waitEvent(
    handle,
    math.max(0, timeout.inMicroseconds) / Duration.microsecondsPerSecond,
  );

  /// Shuts mpv down and frees it. Safe to call once per created handle.
  void terminateDestroy(Pointer<Void> handle) => _terminateDestroy(handle);

  String errorText(int error) {
    if (error >= 0) return 'no error';
    final text = _errorString(error);
    if (text == nullptr) return 'mpv error $error';
    return text.toDartString();
  }
}
