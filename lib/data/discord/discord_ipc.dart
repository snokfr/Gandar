import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../core/logging/app_logger.dart';

/// Discord's IPC opcodes. The protocol is a local one: the desktop client
/// listens on a socket and answers with the same framing.
abstract final class DiscordOpcode {
  /// Client -> server, once, before anything else.
  static const int handshake = 0;

  /// Both directions: a JSON command or an event.
  static const int frame = 1;

  static const int close = 2;
  static const int ping = 3;
  static const int pong = 4;
}

/// Encodes one IPC frame.
///
/// The framing is an 8-byte header — a 4-byte little-endian opcode and a 4-byte
/// little-endian payload length — followed by UTF-8 JSON. Pure, so the two
/// tests that matter (the byte layout, and the length being the *byte* length
/// rather than the character count) do not need a pipe.
Uint8List encodeDiscordFrame(int opcode, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final out = Uint8List(8 + body.length);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, opcode, Endian.little);
  view.setUint32(4, body.length, Endian.little);
  out.setRange(8, out.length, body);
  return out;
}

/// Reads the 8-byte header of a frame.
({int opcode, int length}) decodeDiscordHeader(Uint8List header) {
  if (header.length < 8) {
    throw ArgumentError.value(header.length, 'header', 'needs 8 bytes');
  }
  final view = ByteData.view(
    header.buffer,
    header.offsetInBytes,
    header.length,
  );
  return (
    opcode: view.getUint32(0, Endian.little),
    length: view.getUint32(4, Endian.little),
  );
}

/// Raised when Discord cannot be reached at all.
///
/// Not an error condition worth showing anyone: the desktop client simply is
/// not running, which is the normal state of most machines most of the time.
class DiscordUnavailable implements Exception {
  DiscordUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A two-way byte channel to the Discord client.
///
/// Deliberately narrow: everything above it is protocol, and the only platform
/// difference between Windows and Unix is how this object is obtained.
abstract interface class DiscordTransport {
  /// The pipe or socket that was opened, for the log.
  String get description;

  void write(Uint8List bytes);

  /// How many bytes are waiting, without consuming any.
  int available();

  /// Reads between 1 and [max] bytes.
  Uint8List read(int max);

  void close();
}

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------

/// The Win32 calls the transport needs, resolved once.
///
/// Held in a class with a lazy static so nothing touches `kernel32.dll` until a
/// pipe is actually opened — the analyze and test jobs run on Linux, and this
/// file is imported by the settings screen there.
class _Kernel32 {
  _Kernel32(this._lib) {
    createFile = _lib
        .lookupFunction<
          IntPtr Function(
            Pointer<Utf16>,
            Uint32,
            Uint32,
            IntPtr,
            Uint32,
            Uint32,
            IntPtr,
          ),
          int Function(Pointer<Utf16>, int, int, int, int, int, int)
        >('CreateFileW');
    readFile = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Void>,
          ),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
        >('ReadFile');
    writeFile = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Void>,
          ),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
        >('WriteFile');
    peekNamedPipe = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          ),
          int Function(
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          )
        >('PeekNamedPipe');
    closeHandle = _lib
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'CloseHandle',
        );
    waitNamedPipe = _lib
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, int)
        >('WaitNamedPipeW');
    getLastError = _lib.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
    getCurrentProcess = _lib.lookupFunction<IntPtr Function(), int Function()>(
      'GetCurrentProcess',
    );
  }

  final DynamicLibrary _lib;
  late final int Function(Pointer<Utf16>, int, int, int, int, int, int)
  createFile;
  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  readFile;
  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  writeFile;
  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
  peekNamedPipe;
  late final int Function(int) closeHandle;
  late final int Function(Pointer<Utf16>, int) waitNamedPipe;
  late final int Function() getLastError;

  /// The pseudo-handle for this process. It never needs closing.
  late final int Function() getCurrentProcess;

  static _Kernel32? _instance;

  /// Loaded on demand, and only on Windows.
  static _Kernel32 get instance =>
      _instance ??= _Kernel32(DynamicLibrary.open('kernel32.dll'));

  // CreateFileW arguments.
  static const int genericRead = 0x80000000;
  static const int genericWrite = 0x40000000;
  static const int openExisting = 3;
  static const int fileAttributeNormal = 0x80;
  static const int invalidHandleValue = -1;
  static const int errorPipeBusy = 231;
  static const int errorFileNotFound = 2;

  /// The pipe is there and free, but this process is not allowed to open it.
  ///
  /// Windows decides this with the mandatory integrity label a named pipe
  /// carries, and it is not about the user account: two processes of the *same*
  /// user cannot talk through a pipe when one is elevated and the other is not.
  /// Discord's own pipe is refused to a process on the wrong side of that line,
  /// which surfaces here as a bare 5.
  static const int errorAccessDenied = 5;
}

/// `advapi32.dll`, for asking whether this process is elevated.
///
/// Loaded the same lazy way as [_Kernel32], and only on Windows.
class _Advapi32 {
  _Advapi32(this._lib) {
    openProcessToken = _lib
        .lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
          int Function(int, int, Pointer<IntPtr>)
        >('OpenProcessToken');
    getTokenInformation = _lib
        .lookupFunction<
          Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
          int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
        >('GetTokenInformation');
  }

  final DynamicLibrary _lib;
  late final int Function(int, int, Pointer<IntPtr>) openProcessToken;
  late final int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
  getTokenInformation;

  static _Advapi32? _instance;

  static _Advapi32 get instance =>
      _instance ??= _Advapi32(DynamicLibrary.open('advapi32.dll'));

  /// `TOKEN_QUERY`, the only access [isRunningElevated] needs.
  static const int tokenQuery = 0x0008;

  /// `TokenElevation`. Its answer is one `DWORD`: non-zero means elevated.
  static const int tokenElevation = 20;
}

/// Whether this process is running elevated, or null when that cannot be told
/// (anywhere but Windows, or if Windows refuses the question).
///
/// This exists because "access denied" on Discord's pipe is not about the user
/// account — the same user's processes cannot talk through a named pipe when
/// one is elevated and the other is not — and the advice that fixes it depends
/// on which side Gandar is on. Guessing that wrong sends someone to change the
/// wrong program.
bool? isRunningElevated() {
  if (!Platform.isWindows) return null;
  try {
    final kernel32 = _Kernel32.instance;
    final advapi32 = _Advapi32.instance;
    final token = calloc<IntPtr>();
    try {
      if (advapi32.openProcessToken(
            kernel32.getCurrentProcess(),
            _Advapi32.tokenQuery,
            token,
          ) ==
          0) {
        return null;
      }
      final value = calloc<Uint32>();
      final written = calloc<Uint32>();
      try {
        if (advapi32.getTokenInformation(
              token.value,
              _Advapi32.tokenElevation,
              value.cast(),
              sizeOf<Uint32>(),
              written,
            ) ==
            0) {
          return null;
        }
        return value.value != 0;
      } finally {
        calloc.free(value);
        calloc.free(written);
      }
    } finally {
      if (token.value != 0) kernel32.closeHandle(token.value);
      calloc.free(token);
    }
  } catch (_) {
    // A missing dll or a refused token is not worth an exception on the path
    // to drawing a settings screen; "unknown" is already handled everywhere.
    return null;
  }
}

/// What to tell someone whose Discord pipe exists but was refused.
///
/// Pure, so the three ways round — Gandar elevated, Discord elevated, or no
/// idea — are tested without a pipe, an administrator, or a second process.
/// [elevated] is the answer from [isRunningElevated].
String discordPipeRefusedAdvice({
  required String path,
  required bool? elevated,
}) {
  // What is measured and what is inferred are kept apart here. Gandar's own
  // level is a fact this process can read; Discord's is not, and claiming it
  // would be inventing the one thing the reader needs to be true. Windows'
  // documented rule is about the security descriptor of the pipe and the
  // token of the caller, which is why the level has to match — but which side
  // is high is only known on Gandar's side.
  final which = switch (elevated) {
    true =>
      'Gandar is running as administrator. A pipe is only open to a program '
          'at the same level as the one that made it, and Discord\u2019s own '
          'level cannot be read from here',
    false =>
      'Discord is most likely running as administrator and Gandar is not, so '
          'Windows will not let them talk to each other',
    null =>
      'One of the two is running as administrator and the other is not, so '
          'Windows will not let them talk to each other',
  };
  // The remedy is spelled out, because "start both the same way" is only
  // advice if you already know which way each one went. When Gandar is the
  // elevated one, the ordinary way to match is to stop elevating *Gandar*:
  // starting Discord as administrator as well works, but it is not the thing
  // to suggest first.
  final fix = switch (elevated) {
    true =>
      'Close Gandar and open it normally (not as administrator), or start '
          'Discord as administrator as well, so both are the same',
    false =>
      'Start Discord normally, or start Gandar as administrator as well, so '
          'both are the same',
    null => 'Start both the same way (normally is best) and it will connect',
  };
  return '$path exists but refuses Gandar — $which. $fix. There is nothing '
      'to fix in Gandar: this is Windows keeping two programs apart.';
}

/// A `CreateFileW` failure, with the code so the caller can tell "nothing
/// there" apart from "there and we still could not open it".
class _Win32Failure implements Exception {
  _Win32Failure(this.path, this.error);

  final String path;
  final int error;

  @override
  String toString() => '$path: Win32 error $error';
}

/// A Windows named pipe carrying Discord's IPC.
///
/// This exists because `dart:io` cannot open one. `File.open` maps to
/// `CreateFileW` with `OPEN_ALWAYS`, which a pipe rejects with
/// `ERROR_GEN_FAILURE` (31), and there is no `FileMode` that grants read *and*
/// write on a single handle. Going through `CreateFileW` directly with
/// `OPEN_EXISTING` and `GENERIC_READ | GENERIC_WRITE` gives one handle that
/// can do both, which is exactly what the protocol needs.
class _WindowsPipe implements DiscordTransport {
  _WindowsPipe._(this._handle, this.description);

  final int _handle;

  @override
  final String description;

  bool _closed = false;

  /// Opens [path], or throws [_Win32Failure] carrying the Win32 error.
  ///
  /// Discord serves its pipe through a small pool of instances, so a client
  /// that arrives while they are all taken gets `ERROR_PIPE_BUSY` rather than a
  /// connection. That is a "wait a moment", not a "no": the documented answer
  /// is `WaitNamedPipe`, which blocks until an instance frees up. Doing it here
  /// is why opening the pipe works at all on a machine where another Rich
  /// Presence app already holds the only instance.
  static _WindowsPipe open(
    String path, {
    Duration busyTimeout = const Duration(seconds: 3),
  }) {
    final kernel32 = _Kernel32.instance;
    final elapsed = Stopwatch()..start();

    while (true) {
      final wide = path.toNativeUtf16();
      final handle = kernel32.createFile(
        wide,
        _Kernel32.genericRead | _Kernel32.genericWrite,
        0,
        0,
        _Kernel32.openExisting,
        _Kernel32.fileAttributeNormal,
        0,
      );
      // Read the error *before* freeing the path. `GetLastError` is per-thread
      // and any subsequent call — including the allocator's own `free`, which
      // lands in the Windows heap — is free to overwrite it, which reads as a
      // failure with error 0 and hides the real reason.
      final error = handle == _Kernel32.invalidHandleValue
          ? kernel32.getLastError()
          : 0;
      malloc.free(wide);

      if (handle != _Kernel32.invalidHandleValue) {
        return _WindowsPipe._(handle, path);
      }
      if (error != _Kernel32.errorPipeBusy || elapsed.elapsed >= busyTimeout) {
        throw _Win32Failure(path, error);
      }
      final wait = path.toNativeUtf16();
      kernel32.waitNamedPipe(wait, 500);
      malloc.free(wait);
    }
  }

  void _checkClosed() {
    if (_closed) throw StateError('the Discord pipe is closed');
  }

  @override
  void write(Uint8List bytes) {
    _checkClosed();
    final kernel32 = _Kernel32.instance;
    final buffer = malloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final ok = kernel32.writeFile(
        _handle,
        buffer,
        bytes.length,
        written,
        nullptr,
      );
      if (ok == 0) {
        throw DiscordUnavailable(
          'writing to Discord failed (Win32 error ${kernel32.getLastError()})',
        );
      }
      // A pipe write can be partial in theory; the protocol frames are small
      // enough that Discord's buffer always takes them whole, but reporting it
      // beats writing half a frame and having the client desynchronise.
      if (written.value != bytes.length) {
        throw DiscordUnavailable(
          'wrote ${written.value} of ${bytes.length} bytes to Discord',
        );
      }
    } finally {
      calloc.free(written);
      malloc.free(buffer);
    }
  }

  @override
  int available() {
    if (_closed) return 0;
    final kernel32 = _Kernel32.instance;
    final total = calloc<Uint32>();
    try {
      final ok = kernel32.peekNamedPipe(
        _handle,
        nullptr,
        0,
        nullptr,
        total,
        nullptr,
      );
      if (ok == 0) {
        throw DiscordUnavailable(
          'Discord closed the connection (Win32 error '
          '${kernel32.getLastError()})',
        );
      }
      return total.value;
    } finally {
      calloc.free(total);
    }
  }

  @override
  Uint8List read(int max) {
    _checkClosed();
    if (max <= 0) return Uint8List(0);
    final kernel32 = _Kernel32.instance;
    final buffer = malloc<Uint8>(max);
    final read = calloc<Uint32>();
    try {
      final ok = kernel32.readFile(_handle, buffer, max, read, nullptr);
      if (ok == 0) {
        throw DiscordUnavailable(
          'reading from Discord failed (Win32 error ${kernel32.getLastError()})',
        );
      }
      return Uint8List.fromList(buffer.asTypedList(read.value));
    } finally {
      calloc.free(read);
      malloc.free(buffer);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _Kernel32.instance.closeHandle(_handle);
  }
}

/// The pipe names Discord tries, in order.
List<String> discordPipeCandidates() {
  if (Platform.isWindows) {
    return <String>[for (var i = 0; i < 10; i++) '\\\\.\\pipe\\discord-ipc-$i'];
  }
  final base =
      Platform.environment['XDG_RUNTIME_DIR'] ??
      Platform.environment['TMPDIR'] ??
      Platform.environment['TMP'] ??
      Platform.environment['TEMP'] ??
      '/tmp';
  final separator = base.endsWith('/') ? '' : '/';
  return <String>[
    for (var i = 0; i < 10; i++) '$base${separator}discord-ipc-$i',
  ];
}

/// Opens the first Discord endpoint that accepts a connection.
///
/// Windows is the only platform this is implemented for. The other two keep
/// their endpoints in the candidate list so the failure message names the real
/// reason — a unix domain socket, which is not something `dart:io` can dial —
/// rather than pretending Discord is absent.
Future<DiscordTransport> openDiscordTransport({
  List<String>? candidates,
  bool? elevated,
}) async {
  if (!Platform.isWindows) {
    throw DiscordUnavailable(
      'Discord Rich Presence is implemented on Windows only so far: the '
      'endpoint here is a unix domain socket, which dart:io cannot open.',
    );
  }
  final paths = candidates ?? discordPipeCandidates();
  final broken = <String>[];
  for (final path in paths) {
    try {
      return _WindowsPipe.open(path);
    } on _Win32Failure catch (failure) {
      // "Nothing on this name" is the expected case for nine of the ten
      // candidates; anything else is worth repeating, because it is the only
      // way to see why a pipe that does exist refused to open.
      if (failure.error == _Kernel32.errorAccessDenied) {
        // A raw "Win32 error 5" reads as a bug in Gandar. It is not: it means
        // this app and Discord are on opposite sides of an integrity boundary,
        // and Windows will not let them talk. Which way round that is changes
        // what helps, so it is asked of the process rather than assumed — the
        // one thing this message must not do is send someone to change the
        // wrong program.
        broken.add(
          discordPipeRefusedAdvice(
            path: failure.path,
            elevated: elevated ?? isRunningElevated(),
          ),
        );
      } else if (failure.error != _Kernel32.errorFileNotFound) {
        broken.add(
          failure.error == _Kernel32.errorPipeBusy
              ? '${failure.path} is there but every instance is busy'
              : failure.toString(),
        );
      }
    }
  }
  throw DiscordUnavailable(
    broken.isEmpty
        ? 'no Discord client is listening (nothing on any discord-ipc-0..9)'
        : 'could not open Discord\'s pipe — ${broken.join('; ')}',
  );
}

// ---------------------------------------------------------------------------
// The client
// ---------------------------------------------------------------------------

/// One frame received from Discord.
class DiscordMessage {
  const DiscordMessage({required this.opcode, required this.payload});

  final int opcode;
  final Map<String, Object?> payload;

  /// The event name, for the frames that carry one (`READY`, `ERROR`, …).
  String? get event => payload['evt']?.toString();

  String? get command => payload['cmd']?.toString();

  @override
  String toString() => 'DiscordMessage($opcode, ${jsonEncode(payload)})';
}

/// What the presence layer needs from a connection.
///
/// An interface rather than [DiscordIpc] itself so the controller's behaviour —
/// reconnect, fail soft, clear on pause — is testable without Discord running,
/// which is the only way that logic gets covered at all.
abstract interface class DiscordConnection {
  Future<void> setActivity(Map<String, Object?>? activity);

  void close();

  bool get isOpen;
}

/// A connected, handshaken Discord IPC client.
///
/// The connection is polled rather than read with a blocking call: every 40 ms
/// the pipe is asked how many bytes are waiting and only reads when there are
/// some. That keeps the whole thing on the main isolate — `PeekNamedPipe` never
/// blocks — and means closing the client actually stops it, which a thread
/// parked inside `ReadFile` would not.
class DiscordIpc implements DiscordConnection {
  DiscordIpc._(this._transport);

  final DiscordTransport _transport;

  /// Bytes received but not yet consumed by [_pump]. Appended to and sliced
  /// rather than held in a [BytesBuilder], whose drain-and-reuse behaviour is
  /// easy to get subtly wrong.
  Uint8List _buffer = Uint8List(0);
  final StreamController<DiscordMessage> _messages =
      StreamController<DiscordMessage>.broadcast();

  /// Replies being waited on, keyed by nonce.
  final Map<String, Completer<DiscordMessage>> _pending =
      <String, Completer<DiscordMessage>>{};

  Timer? _poll;
  bool _closed = false;
  int _nonce = 0;

  /// Discord closes a frame whose payload is larger than this, and a presence
  /// payload is a few hundred bytes at its largest.
  static const int _maxFrameBytes = 64 * 1024;

  /// How often the pipe is asked whether anything arrived.
  static const Duration pollInterval = Duration(milliseconds: 40);

  /// Every frame Discord sends, including event pushes.
  Stream<DiscordMessage> get messages => _messages.stream;

  String get description => _transport.description;

  /// Connects, handshakes, and waits for Discord's `READY`.
  ///
  /// [clientId] is the Application ID from the Discord Developer Portal. It is
  /// public: nothing else authenticates this connection, and Discord's local
  /// socket is the whole trust boundary.
  static Future<DiscordIpc> connect({
    required String clientId,
    Duration timeout = const Duration(seconds: 5),
    List<String>? candidates,
  }) async {
    final transport = await openDiscordTransport(candidates: candidates);
    final client = DiscordIpc._(transport);
    try {
      await client._handshake(clientId, timeout);
    } catch (_) {
      // A failed handshake must not leave a handle and a timer behind.
      client.close();
      rethrow;
    }
    return client;
  }

  Future<void> _handshake(String clientId, Duration timeout) async {
    final ready = Completer<DiscordMessage>();
    late final StreamSubscription<DiscordMessage> sub;
    sub = messages.listen((message) {
      if (message.event == 'READY') {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message.event == 'ERROR') {
        if (!ready.isCompleted) {
          ready.completeError(DiscordUnavailable(_errorText(message)));
        }
      }
    });

    _transport.write(
      encodeDiscordFrame(DiscordOpcode.handshake, <String, Object?>{
        'v': 1,
        'client_id': clientId,
      }),
    );
    _startPolling();

    try {
      await ready.future.timeout(
        timeout,
        onTimeout: () => throw DiscordUnavailable(
          'Discord accepted the connection but never said READY. Check that '
          'the Application ID matches the app in the Developer Portal.',
        ),
      );
      AppLogger.instance.info(
        'discord',
        'connected to ${_transport.description} as client $clientId',
      );
    } finally {
      await sub.cancel();
    }
  }

  static String _errorText(DiscordMessage message) {
    final data = message.payload['data'];
    if (data is Map) {
      final code = data['code'];
      final text = data['message'];
      if (text != null) return 'Discord refused the handshake: $text ($code)';
    }
    return 'Discord refused the handshake: ${jsonEncode(message.payload)}';
  }

  /// Sends one command and waits for Discord's reply with the same nonce.
  ///
  /// Rich Presence is fire-and-forget in spirit, but Discord answers every
  /// command — and the answer is the only way to learn that the activity was
  /// rejected (an unapproved image asset, say, comes back as an error rather
  /// than showing nothing).
  Future<DiscordMessage?> send(
    String command,
    Map<String, Object?> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_closed) throw StateError('the Discord connection is closed');
    final nonce = '${_nonce++}';
    final completer = Completer<DiscordMessage>();
    _pending[nonce] = completer;
    _transport.write(
      encodeDiscordFrame(DiscordOpcode.frame, <String, Object?>{
        'cmd': command,
        'args': args,
        'nonce': nonce,
      }),
    );
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      // A missing reply is reported as "no answer" rather than turned into a
      // connection failure — the activity may well be showing — but it is
      // logged, because silence is a real failure mode that is otherwise
      // indistinguishable from success: a Discord client sitting on an error
      // screen accepts the connection and then never answers anything. Without
      // this line that machine looks exactly like a working one.
      AppLogger.instance.warn(
        'discord',
        'Discord did not answer $command within '
            '${timeout.inSeconds}s; the activity may not be showing',
      );
      return null;
    } finally {
      _pending.remove(nonce);
    }
  }

  /// Sets the activity shown on the profile, or clears it with null.
  @override
  Future<void> setActivity(Map<String, Object?>? activity) async {
    final reply = await send('SET_ACTIVITY', <String, Object?>{
      'pid': pid,
      'activity': activity,
    });
    final event = reply?.event;
    if (event == 'ERROR') {
      throw DiscordUnavailable(_errorText(reply!));
    }
  }

  void _startPolling() {
    _poll ??= Timer.periodic(pollInterval, (_) => _pump());
  }

  /// Moves whatever has arrived from the pipe into complete frames.
  void _pump() {
    if (_closed) return;
    try {
      final waitingBytes = _transport.available();
      if (waitingBytes > 0) {
        _append(_transport.read(waitingBytes));
      }
      while (_buffer.length >= 8) {
        final header = decodeDiscordHeader(_buffer);
        if (header.length > _maxFrameBytes) {
          throw DiscordUnavailable(
            'Discord announced a ${header.length}-byte frame, which is not '
            'something this protocol sends',
          );
        }
        final frameLength = 8 + header.length;
        // A pipe hands over what it has, which can be half a frame.
        if (_buffer.length < frameLength) return;
        final body = Uint8List.sublistView(_buffer, 8, frameLength);
        _buffer = _buffer.sublist(frameLength);
        _dispatch(header.opcode, body);
      }
    } on DiscordUnavailable catch (e) {
      _fail(e);
    } catch (e, stack) {
      AppLogger.instance.error(
        'discord',
        'IPC read failed',
        error: e,
        stackTrace: stack,
      );
      _fail(DiscordUnavailable('$e'));
    }
  }

  void _append(Uint8List chunk) {
    if (chunk.isEmpty) return;
    if (_buffer.isEmpty) {
      _buffer = chunk;
      return;
    }
    final merged = Uint8List(_buffer.length + chunk.length)
      ..setRange(0, _buffer.length, _buffer)
      ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);
    _buffer = merged;
  }

  void _dispatch(int opcode, Uint8List body) {
    if (opcode == DiscordOpcode.ping) {
      _transport.write(
        encodeDiscordFrame(DiscordOpcode.pong, const <String, Object?>{}),
      );
      return;
    }
    if (opcode == DiscordOpcode.close) {
      _fail(DiscordUnavailable('Discord closed the connection'));
      return;
    }
    if (opcode != DiscordOpcode.frame) return;

    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) return;
      payload = Map<String, Object?>.from(decoded);
    } catch (e) {
      AppLogger.instance.warn('discord', 'unreadable frame: $e');
      return;
    }

    final nonce = payload['nonce']?.toString();
    final waiter = nonce == null ? null : _pending[nonce];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(DiscordMessage(opcode: opcode, payload: payload));
      return;
    }
    if (!_messages.isClosed) {
      _messages.add(DiscordMessage(opcode: opcode, payload: payload));
    }
  }

  void _fail(DiscordUnavailable reason) {
    if (_closed) return;
    AppLogger.instance.debug('discord', 'connection ended: $reason');
    for (final waiter in _pending.values) {
      if (!waiter.isCompleted) waiter.completeError(reason);
    }
    _pending.clear();
    _teardown();
  }

  @override
  bool get isOpen => !_closed;

  void _teardown() {
    _poll?.cancel();
    _poll = null;
    if (!_closed) {
      _closed = true;
      try {
        _transport.close();
      } catch (_) {
        // Closing a pipe Discord already closed is not worth reporting.
      }
    }
    if (!_messages.isClosed) _messages.close();
  }

  /// Closes the connection, telling Discord first if it is still listening.
  @override
  void close() {
    if (!_closed) {
      try {
        _transport.write(
          encodeDiscordFrame(DiscordOpcode.close, const <String, Object?>{}),
        );
      } catch (_) {
        // Discord may already be gone; the handle still needs closing.
      }
    }
    _teardown();
  }
}
