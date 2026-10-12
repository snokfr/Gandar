// Why will Discord not talk to Gandar?
//
// The app's answer used to be a guess: a pipe that exists and refuses is blamed
// on mismatched privilege levels between the two programs. That is one possible
// cause and it is not the only one — Windows refuses a pipe open for reasons
// that have nothing to do with elevation, most of all a pipe that belongs to
// another user account entirely. A message that names the wrong cause sends
// someone to change a program that was never the problem.
//
// This probe measures instead of guessing. In one run it reports:
//
//   * who this process is — user SID, elevation, integrity level;
//   * which `discord-ipc-N` pipes exist and what each one answers when opened;
//   * for a pipe that refuses, who owns it, read straight from its security
//     descriptor, compared with this process's own user;
//   * optionally, a real handshake and SET_ACTIVITY, so the protocol itself is
//     checked against the running client rather than against a document.
//
// It imports nothing from `package:gandar/...` on purpose: those reach Flutter
// through `path_provider`, which a plain `dart run` cannot compile.
//
//   dart run tool/discord_probe.dart [--activity <clientId>] [--seconds]
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Win32
// ---------------------------------------------------------------------------

/// `kernel32.dll`.
class Kernel32 {
  Kernel32(this._lib) {
    createFile = _lib.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Uint32, Uint32, IntPtr, Uint32, Uint32, IntPtr),
      int Function(Pointer<Utf16>, int, int, int, int, int, int)
    >('CreateFileW');
    closeHandle = _lib
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    getLastError =
        _lib.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
    getCurrentProcess = _lib
        .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
    peekNamedPipe = _lib.lookupFunction<
      Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>),
      int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>)
    >('PeekNamedPipe');
    readFile = _lib.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
    >('ReadFile');
    writeFile = _lib.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
    >('WriteFile');
  }

  final DynamicLibrary _lib;

  late final int Function(Pointer<Utf16>, int, int, int, int, int, int)
  createFile;
  late final int Function(int) closeHandle;
  late final int Function() getLastError;
  late final int Function() getCurrentProcess;
  late final int Function(
    int,
    Pointer<Void>,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>
  )
  peekNamedPipe;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
  readFile;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
  writeFile;

  static final Kernel32 instance = Kernel32(
    DynamicLibrary.open('kernel32.dll'),
  );

  static const int genericRead = 0x80000000;
  static const int genericWrite = 0x40000000;
  static const int readControl = 0x00020000;
  static const int openExisting = 3;
  static const int invalidHandle = -1;

  /// Opens [path], returning the handle or null with the Win32 error.
  (int, int) open(String path, int access) {
    final wide = path.toNativeUtf16();
    final handle = createFile(wide, access, 0, 0, openExisting, 0x80, 0);
    final error = handle == invalidHandle ? getLastError() : 0;
    malloc.free(wide);
    return (handle, error);
  }
}

/// `advapi32.dll`: tokens, security descriptors, and SID strings.
class Advapi32 {
  Advapi32(this._lib) {
    openProcessToken = _lib.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
      int Function(int, int, Pointer<IntPtr>)
    >('OpenProcessToken');
    getTokenInformation = _lib.lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
      int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
    >('GetTokenInformation');
    getSecurityInfo = _lib.lookupFunction<
      Uint32 Function(
        IntPtr,
        Int32,
        Uint32,
        Pointer<IntPtr>,
        Pointer<IntPtr>,
        Pointer<IntPtr>,
        Pointer<IntPtr>,
        Pointer<IntPtr>
      ),
      int Function(int, int, int, Pointer<IntPtr>, Pointer<IntPtr>, Pointer<IntPtr>, Pointer<IntPtr>, Pointer<IntPtr>)
    >('GetSecurityInfo');
    convertSidToStringSid =
        _lib.lookupFunction<
          Int32 Function(IntPtr, Pointer<IntPtr>),
          int Function(int, Pointer<IntPtr>)
        >('ConvertSidToStringSidW');
  }

  final DynamicLibrary _lib;

  late final int Function(int, int, Pointer<IntPtr>) openProcessToken;
  late final int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
  getTokenInformation;
  late final int Function(
    int,
    int,
    int,
    Pointer<IntPtr>,
    Pointer<IntPtr>,
    Pointer<IntPtr>,
    Pointer<IntPtr>,
    Pointer<IntPtr>
  )
  getSecurityInfo;
  late final int Function(int, Pointer<IntPtr>) convertSidToStringSid;

  static final Advapi32 instance = Advapi32(
    DynamicLibrary.open('advapi32.dll'),
  );

  static const int tokenQuery = 0x0008;
  static const int tokenUser = 1;
  static const int tokenElevation = 20;
  static const int tokenIntegrityLevel = 25;

  /// `SE_KERNEL_OBJECT`, which is what a named pipe is.
  static const int seKernelObject = 6;
  static const int ownerSecurityInformation = 0x00000001;
  static const int labelSecurityInformation = 0x00000010;

  /// The user SID of a token, as a string.
  String? sidOfToken(int token, int informationClass) {
    final size = calloc<Uint32>();
    try {
      // Asked once with no buffer to learn the size; the answer is not needed.
      getTokenInformation(token, informationClass, nullptr, 0, size);
      if (size.value == 0) return null;
      final buffer = calloc<Uint8>(size.value);
      try {
        if (getTokenInformation(
              token,
              informationClass,
              buffer.cast(),
              size.value,
              size,
            ) ==
            0) {
          return null;
        }
        // Both TOKEN_USER and TOKEN_MANDATORY_LABEL begin with a
        // SID_AND_ATTRIBUTES, whose first field is the SID pointer.
        final sid = buffer.cast<IntPtr>().value;
        if (sid == 0) return null;
        return sidToString(sid);
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(size);
    }
  }

  /// The last subauthority of a SID — for an integrity SID, its level.
  int? integrityRid(int token) {
    final size = calloc<Uint32>();
    try {
      getTokenInformation(token, tokenIntegrityLevel, nullptr, 0, size);
      if (size.value == 0) return null;
      final buffer = calloc<Uint8>(size.value);
      try {
        if (getTokenInformation(
              token,
              tokenIntegrityLevel,
              buffer.cast(),
              size.value,
              size,
            ) ==
            0) {
          return null;
        }
        final sid = buffer.cast<IntPtr>().value;
        if (sid == 0) return null;
        final sidView = Pointer<Uint8>.fromAddress(sid);
        final count = sidView[1];
        if (count == 0) return null;
        final last = Pointer<Uint32>.fromAddress(sid + 8 + (count - 1) * 4).value;
        return last;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(size);
    }
  }

  String? sidToString(int sid) {
    final out = calloc<IntPtr>();
    try {
      if (convertSidToStringSid(sid, out) == 0) return null;
      final text = out.value == 0 ? null : Pointer<Utf16>.fromAddress(out.value).toDartString();
      return text;
    } finally {
      calloc.free(out);
    }
  }
}

/// What this process is, as Windows sees it.
class Identity {
  Identity(this.sid, this.elevated, this.integrityRid, this.integrityName);

  final String? sid;
  final bool elevated;
  final int? integrityRid;
  final String integrityName;

  @override
  String toString() =>
      'sid=${sid ?? 'unknown'} elevated=$elevated integrity=$integrityName';

  static Identity read() {
    final kernel32 = Kernel32.instance;
    final advapi = Advapi32.instance;
    final token = calloc<IntPtr>();
    try {
      if (advapi.openProcessToken(
            kernel32.getCurrentProcess(),
            Advapi32.tokenQuery,
            token,
          ) ==
          0) {
        return Identity(null, false, null, 'unknown');
      }
      final elevation = calloc<Uint32>();
      bool elevated = false;
      try {
        final written = calloc<Uint32>();
        if (advapi.getTokenInformation(
              token.value,
              Advapi32.tokenElevation,
              elevation.cast(),
              sizeOf<Uint32>(),
              written,
            ) !=
            0) {
          elevated = elevation.value != 0;
        }
        calloc.free(written);
      } finally {
        calloc.free(elevation);
      }
      final rid = advapi.integrityRid(token.value);
      return Identity(
        advapi.sidOfToken(token.value, Advapi32.tokenUser),
        elevated,
        rid,
        _integrityName(rid),
      );
    } finally {
      if (token.value != 0) kernel32.closeHandle(token.value);
      calloc.free(token);
    }
  }

  static String _integrityName(int? rid) => switch (rid) {
    0x0000 => 'untrusted',
    0x1000 => 'low',
    0x2000 => 'medium',
    0x2100 => 'medium plus',
    0x3000 => 'high',
    0x4000 => 'system',
    _ => rid == null ? 'unknown' : '0x${rid.toRadixString(16)}',
  };
}

/// Who owns a pipe, read from its security descriptor.
///
/// This is the measurement the whole probe exists for. `GetSecurityInfo` needs
/// a handle that was opened with `READ_CONTROL`, which is a *different* request
/// from the read/write one Discord refuses — so a pipe that will not let us talk
/// to it will often still say who it belongs to.
String? pipeOwner(String path) {
  final kernel32 = Kernel32.instance;
  final advapi = Advapi32.instance;
  final (handle, _) = kernel32.open(path, Kernel32.readControl);
  if (handle == Kernel32.invalidHandle) return null;
  final owner = calloc<IntPtr>();
  final descriptor = calloc<IntPtr>();
  try {
    if (advapi.getSecurityInfo(
          handle,
          Advapi32.seKernelObject,
          Advapi32.ownerSecurityInformation,
          owner,
          nullptr,
          nullptr,
          nullptr,
          descriptor,
        ) !=
        0) {
      return null;
    }
    if (owner.value == 0) return null;
    return advapi.sidToString(owner.value);
  } finally {
    calloc.free(owner);
    calloc.free(descriptor);
    kernel32.closeHandle(handle);
  }
}

String errorName(int error) => switch (error) {
  0 => 'opened',
  2 => 'ERROR_FILE_NOT_FOUND (nothing listening)',
  5 => 'ERROR_ACCESS_DENIED (it is there and refused)',
  231 => 'ERROR_PIPE_BUSY',
  _ => 'error $error',
};

// ---------------------------------------------------------------------------
// The protocol, as the app sends it
// ---------------------------------------------------------------------------

Uint8List frame(int opcode, Object? payload) {
  final body = utf8.encode(jsonEncode(payload ?? const <String, Object?>{}));
  final out = Uint8List(8 + body.length);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, opcode, Endian.little);
  view.setUint32(4, body.length, Endian.little);
  out.setRange(8, out.length, body);
  return out;
}

void main(List<String> args) {
  final clientIdIndex = args.indexOf('--activity');
  final clientId = clientIdIndex >= 0 && args.length > clientIdIndex + 1
      ? args[clientIdIndex + 1]
      : null;
  final seconds = args.contains('--seconds');

  // ---- Who are we? -------------------------------------------------------
  final me = Identity.read();
  stdout.writeln('this process: $me');
  stdout.writeln(
    '  ${me.elevated ? 'a high process — this is the "run as administrator" case' : 'an ordinary, non-elevated process'}',
  );

  // ---- The pipes ---------------------------------------------------------
  final pipes = <String>[for (var i = 0; i < 10; i++) '\\\\.\\pipe\\discord-ipc-$i'];
  String? openable;
  for (final path in pipes) {
    final (handle, error) = Kernel32.instance.open(
      path,
      Kernel32.genericRead | Kernel32.genericWrite,
    );
    if (handle != Kernel32.invalidHandle) {
      Kernel32.instance.closeHandle(handle);
      stdout.writeln('$path: opened');
      openable ??= path;
      continue;
    }
    if (error == 2) continue; // nothing on this name: the usual answer
    stdout.writeln('$path: ${errorName(error)}');
    if (error == 5) {
      final owner = pipeOwner(path);
      stdout.writeln(
        '    owner: ${owner ?? 'unreadable (READ_CONTROL refused too)'}',
      );
      if (owner != null && me.sid != null) {
        stdout.writeln(
          owner == me.sid
              ? '    owner is this same Windows account — so this is NOT a '
                    'sign-in mismatch, and it is not the documented '
                    'lower-integrity-writer rule either, because this process '
                    '${me.elevated ? 'is above it' : 'is not above it'}'
              : '    owner is a DIFFERENT Windows account from this process '
                    '(${me.sid}): the refusal is the pipe belonging to someone '
                    'else, not elevation',
        );
      }
    }
  }
  if (openable == null) {
    stdout.writeln('\nnothing to talk to: no discord-ipc-N pipe accepted a connection');
    exitCode = 1;
    return;
  }

  if (clientId == null) {
    stdout.writeln(
      '\nopenable pipe: $openable. Pass --activity <clientId> to handshake and '
      'set a real activity.',
    );
    return;
  }

  // ---- A real conversation ----------------------------------------------
  final kernel32 = Kernel32.instance;
  final (handle, error) = kernel32.open(
    openable,
    Kernel32.genericRead | Kernel32.genericWrite,
  );
  if (handle == Kernel32.invalidHandle) {
    stdout.writeln('\ncould not open $openable: ${errorName(error)}');
    exitCode = 1;
    return;
  }

  void write(List<int> bytes) {
    final buffer = malloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      // ignore: avoid_print
      print('  > ${utf8.decode(bytes.sublist(8))}');
      if (kernel32.writeFile(handle, buffer, bytes.length, written, nullptr) == 0) {
        stdout.writeln('  write failed: ${errorName(kernel32.getLastError())}');
      }
    } finally {
      calloc.free(written);
      malloc.free(buffer);
    }
  }

  /// Reads whatever arrives for up to [timeout], printing each frame.
  List<Map<String, Object?>> readFrames(Duration timeout) {
    final deadline = DateTime.now().add(timeout);
    final frames = <Map<String, Object?>>[];
    var pending = Uint8List(0);
    while (DateTime.now().isBefore(deadline)) {
      final available = calloc<Uint32>();
      try {
        if (kernel32.peekNamedPipe(handle, nullptr, 0, nullptr, available, nullptr) == 0) break;
        if (available.value > 0) {
          final buffer = malloc<Uint8>(available.value);
          final read = calloc<Uint32>();
          try {
            if (kernel32.readFile(handle, buffer, available.value, read, nullptr) != 0) {
              final chunk = Uint8List.fromList(buffer.asTypedList(read.value));
              pending = Uint8List.fromList(<int>[...pending, ...chunk]);
            }
          } finally {
            calloc.free(read);
            malloc.free(buffer);
          }
        }
      } finally {
        calloc.free(available);
      }
      while (pending.length >= 8) {
        final view = ByteData.view(pending.buffer, pending.offsetInBytes);
        final opcode = view.getUint32(0, Endian.little);
        final length = view.getUint32(4, Endian.little);
        if (pending.length < 8 + length) break;
        final body = utf8.decode(pending.sublist(8, 8 + length));
        pending = pending.sublist(8 + length);
        // ignore: avoid_print
        print('  < [$opcode] $body');
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          frames.add(Map<String, Object?>.from(decoded));
        }
      }
      sleep(const Duration(milliseconds: 20));
    }
    return frames;
  }

  stdout.writeln('\nhandshaking on $openable…');
  write(frame(0, <String, Object?>{'v': 1, 'client_id': clientId}));
  final hello = readFrames(const Duration(seconds: 5));
  final ready = hello.any((f) => f['evt'] == 'READY');
  stdout.writeln(ready ? 'READY' : 'no READY arrived');
  if (!ready) {
    exitCode = 1;
    return;
  }

  final now = DateTime.now();
  final start = seconds
      ? now.millisecondsSinceEpoch ~/ 1000
      : now.millisecondsSinceEpoch;
  stdout.writeln(
    '\nsetting an activity (timestamps.start = $start, '
    '${seconds ? 'seconds' : 'milliseconds'})…',
  );
  write(
    frame(1, <String, Object?>{
      'cmd': 'SET_ACTIVITY',
      'args': <String, Object?>{
        'pid': pid,
        'activity': <String, Object?>{
          'details': 'Gandar probe',
          'state': 'checking the pipe',
          'timestamps': <String, Object?>{'start': start},
          'assets': <String, Object?>{'large_image': 'gandar', 'large_text': 'Gandar'},
        },
      },
      'nonce': '1',
    }),
  );
  final replies = readFrames(const Duration(seconds: 5));
  final refused = replies.any((f) => f['evt'] == 'ERROR');
  stdout.writeln(refused ? 'SET_ACTIVITY was refused' : 'SET_ACTIVITY was accepted');

  write(frame(2, const <String, Object?>{})); // CLOSE
  kernel32.closeHandle(handle);
  exitCode = refused || !ready ? 1 : 0;
}
