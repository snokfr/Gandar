import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// What Windows knows about who is who, for the one question Gandar cannot
/// answer by itself: why a pipe that exists refuses to open.
///
/// Nothing here is about Discord's protocol. It exists because "access denied"
/// on `\\.\pipe\discord-ipc-N` has several possible causes that look identical
/// from the outside, and until this file existed the app picked one of them and
/// stated it as fact:
///
///  * the pipe belongs to a **different Windows account** — the answer is to
///    sign in as that account, and elevation has nothing to do with it;
///  * the pipe belongs to an **elevated** Discord — a process that is not
///    elevated cannot write to it, and the fix is to stop elevating Discord;
///  * neither of those — and then the honest answer is that this is not an
///    administrator problem at all, whatever the message used to say.
///
/// What it must not do is pretend. Every function here returns null or an empty
/// answer rather than throwing, so a machine that refuses to be measured gets
/// the careful wording instead of a wrong one.
///
/// Measurements taken on a real machine while writing this, for the record:
/// an elevated (high-integrity) process opened `\\.\pipe\discord-ipc-0` owned by
/// an ordinary Discord without any trouble, and completed a handshake and a
/// `SET_ACTIVITY`. So an elevated Gandar is *not* by itself a reason for a
/// refusal, and the advice no longer says it is.

/// A Discord process on this machine, as Windows describes it.
class DiscordProcessInfo {
  const DiscordProcessInfo({
    required this.pid,
    required this.executable,
    this.userSid,
    this.elevated,
    this.integrity,
  });

  final int pid;
  final String executable;

  /// The account the process runs as, or null when that could not be read.
  final String? userSid;

  /// Whether the process is elevated, or null when that could not be read.
  final bool? elevated;

  /// `medium`, `high`, …, or null when that could not be read.
  final String? integrity;

  @override
  String toString() =>
      '$executable (pid $pid, ${userSid ?? 'unknown user'}, '
      '${elevated == null ? 'unknown elevation' : elevated! ? 'elevated' : 'ordinary'}'
      '${integrity == null ? '' : ', $integrity integrity'})';
}

/// Whether this process is running elevated, or null when that cannot be told
/// (anywhere but Windows, or if Windows refuses the question).
bool? isRunningElevated() {
  final token = _ownToken();
  if (token == null) return null;
  try {
    return _elevatedOf(token);
  } finally {
    _Kernel32.instance.closeHandle(token);
  }
}

/// The SID of the account this process runs as, or null.
String? currentUserSid() {
  final token = _ownToken();
  if (token == null) return null;
  try {
    return _Advapi32.instance.sidOfToken(token, _Advapi32.tokenUser);
  } finally {
    _Kernel32.instance.closeHandle(token);
  }
}

/// The integrity level this process runs at (`medium`, `high`, …), or null.
String? currentIntegrityName() {
  final token = _ownToken();
  if (token == null) return null;
  try {
    return _integrityName(_Advapi32.instance.integrityRid(token));
  } finally {
    _Kernel32.instance.closeHandle(token);
  }
}

/// Every `Discord*.exe` running now, with who it is.
///
/// Returns an empty list when the machine has no Discord running, and **null**
/// when the processes could not be listed at all — the difference matters,
/// because "Discord is not running" is advice and "I could not look" is not.
List<DiscordProcessInfo>? discordProcesses() {
  if (!Platform.isWindows) return null;
  try {
    final kernel32 = _Kernel32.instance;
    final snapshot = kernel32.createToolhelp32Snapshot(_Kernel32.snapProcess, 0);
    if (snapshot == _Kernel32.invalidHandle) return null;

    final found = <DiscordProcessInfo>[];
    final entry = calloc<Uint8>(_ProcessEntry.size);
    try {
      entry.cast<Uint32>().value = _ProcessEntry.size;
      var ok = kernel32.process32First(snapshot, entry);
      while (ok != 0) {
        final pid = _ProcessEntry.pidOf(entry);
        final name = _ProcessEntry.nameOf(entry);
        if (name.toLowerCase().startsWith('discord') && pid != 0) {
          found.add(_describe(pid, name));
        }
        ok = kernel32.process32Next(snapshot, entry);
      }
    } finally {
      calloc.free(entry);
      kernel32.closeHandle(snapshot);
    }
    return found;
  } catch (_) {
    // A missing dll or a refused snapshot is not worth an exception; the caller
    // treats null as "no idea" and says so.
    return null;
  }
}

/// Who owns the named pipe at [path], as a SID string, or null.
///
/// The handle is asked for `READ_CONTROL` rather than for read and write, which
/// is the whole trick: a pipe that refuses to be talked to is often still
/// willing to say who owns it, and that single fact separates "another account"
/// from every other cause.
String? pipeOwnerSid(String path) {
  if (!Platform.isWindows) return null;
  try {
    final kernel32 = _Kernel32.instance;
    final handle = kernel32.openPath(path, _Kernel32.readControl);
    if (handle == _Kernel32.invalidHandle) return null;
    final owner = calloc<IntPtr>();
    final descriptor = calloc<IntPtr>();
    try {
      final result = _Advapi32.instance.getSecurityInfo(
        handle,
        _Advapi32.seKernelObject,
        _Advapi32.ownerSecurityInformation,
        owner,
        nullptr,
        nullptr,
        nullptr,
        descriptor,
      );
      if (result != 0 || owner.value == 0) return null;
      return _Advapi32.instance.sidToString(owner.value);
    } finally {
      calloc.free(owner);
      calloc.free(descriptor);
      kernel32.closeHandle(handle);
    }
  } catch (_) {
    return null;
  }
}

/// The last component of a SID — `-1001` — which is what distinguishes two
/// accounts on the same machine without printing a 40-character string at
/// someone.
String shortSid(String? sid) {
  if (sid == null || sid.isEmpty) return 'unknown';
  final index = sid.lastIndexOf('-');
  return index <= 0 ? sid : '…${sid.substring(index)}';
}

/// Opens this process's token, or null when it cannot be had.
int? _ownToken() {
  if (!Platform.isWindows) return null;
  try {
    final token = calloc<IntPtr>();
    final ok =
        _Advapi32.instance.openProcessToken(
          _Kernel32.instance.getCurrentProcess(),
          _Advapi32.tokenQuery,
          token,
        ) !=
        0;
    final value = token.value;
    calloc.free(token);
    if (!ok) return null;
    return value;
  } catch (_) {
    return null;
  }
}

/// Describes one process by opening it for the token, which is all this needs.
DiscordProcessInfo _describe(int pid, String executable) {
  String? sid;
  bool? elevated;
  String? integrity;
  final kernel32 = _Kernel32.instance;
  final process = kernel32.openProcess(
    _Kernel32.queryLimitedInformation,
    0,
    pid,
  );
  if (process != 0) {
    final token = calloc<IntPtr>();
    try {
      if (_Advapi32.instance.openProcessToken(
            process,
            _Advapi32.tokenQuery,
            token,
          ) !=
          0) {
        sid = _Advapi32.instance.sidOfToken(token.value, _Advapi32.tokenUser);
        elevated = _elevatedOf(token.value);
        integrity = _integrityName(
          _Advapi32.instance.integrityRid(token.value),
        );
      }
    } finally {
      calloc.free(token);
      kernel32.closeHandle(process);
    }
  }
  return DiscordProcessInfo(
    pid: pid,
    executable: executable,
    userSid: sid,
    elevated: elevated,
    integrity: integrity,
  );
}

bool? _elevatedOf(int token) {
  final value = calloc<Uint32>();
  final written = calloc<Uint32>();
  try {
    if (_Advapi32.instance.getTokenInformation(
          token,
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
}

String? _integrityName(int? rid) => switch (rid) {
  0x0000 => 'untrusted',
  0x1000 => 'low',
  0x2000 => 'medium',
  0x2100 => 'medium plus',
  0x3000 => 'high',
  0x4000 => 'system',
  _ => rid == null ? null : '0x${rid.toRadixString(16)}',
};

/// `PROCESSENTRY32W` and where its fields live.
///
/// Read by offset rather than by declaring the struct, because the offsets move
/// between 32- and 64-bit Windows (a `ULONG_PTR` sits in the middle) and getting
/// that wrong reads a process id out of the executable name.
class _ProcessEntry {
  _ProcessEntry._();

  static final bool _wide = sizeOf<IntPtr>() == 8;

  /// Offset of `th32ProcessID`.
  static const int pidOffset = 8;

  /// Offset of `szExeFile`.
  static int get nameOffset => _wide ? 44 : 36;

  /// `sizeof(PROCESSENTRY32W)`, which the API insists on being told.
  static int get size => nameOffset + 260 * 2;

  static const int maxName = 260;

  static int pidOf(Pointer<Uint8> entry) =>
      (entry + pidOffset).cast<Uint32>().value;

  static String nameOf(Pointer<Uint8> entry) {
    final pointer = Pointer<Uint16>.fromAddress(
      entry.address + nameOffset,
    );
    final units = <int>[];
    for (var i = 0; i < maxName; i++) {
      final unit = pointer[i];
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }
}

/// `kernel32.dll`.
class _Kernel32 {
  _Kernel32(this._lib) {
    createFile = _lib.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Uint32, Uint32, IntPtr, Uint32, Uint32, IntPtr),
      int Function(Pointer<Utf16>, int, int, int, int, int, int)
    >('CreateFileW');
    openProcess = _lib.lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)
    >('OpenProcess');
    closeHandle = _lib
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    getCurrentProcess = _lib
        .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
    createToolhelp32Snapshot = _lib.lookupFunction<
      IntPtr Function(Uint32, Uint32),
      int Function(int, int)
    >('CreateToolhelp32Snapshot');
    process32First = _lib.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('Process32FirstW');
    process32Next = _lib.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('Process32NextW');
  }

  final DynamicLibrary _lib;

  late final int Function(Pointer<Utf16>, int, int, int, int, int, int)
  createFile;
  late final int Function(int, int, int) openProcess;
  late final int Function(int) closeHandle;
  late final int Function() getCurrentProcess;
  late final int Function(int, int) createToolhelp32Snapshot;
  late final int Function(int, Pointer<Uint8>) process32First;
  late final int Function(int, Pointer<Uint8>) process32Next;

  static _Kernel32? _instance;

  static _Kernel32 get instance =>
      _instance ??= _Kernel32(DynamicLibrary.open('kernel32.dll'));

  /// `READ_CONTROL`: enough to read who owns something, not enough to use it.
  static const int readControl = 0x00020000;

  static const int queryLimitedInformation = 0x1000;
  static const int snapProcess = 0x00000002;
  static const int openExisting = 3;
  static const int fileAttributeNormal = 0x80;
  static const int invalidHandle = -1;

  /// Opens [path] with [access], or returns [invalidHandle].
  int openPath(String path, int access) {
    final wide = path.toNativeUtf16();
    try {
      return createFile(wide, access, 0, 0, openExisting, fileAttributeNormal, 0);
    } finally {
      malloc.free(wide);
    }
  }
}

/// `advapi32.dll`, for tokens and security descriptors.
class _Advapi32 {
  _Advapi32(this._lib) {
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
      int Function(
        int,
        int,
        int,
        Pointer<IntPtr>,
        Pointer<IntPtr>,
        Pointer<IntPtr>,
        Pointer<IntPtr>,
        Pointer<IntPtr>
      )
    >('GetSecurityInfo');
    convertSidToStringSid = _lib.lookupFunction<
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

  static _Advapi32? _instance;

  static _Advapi32 get instance =>
      _instance ??= _Advapi32(DynamicLibrary.open('advapi32.dll'));

  static const int tokenQuery = 0x0008;
  static const int tokenUser = 1;
  static const int tokenElevation = 20;
  static const int tokenIntegrityLevel = 25;

  /// `SE_KERNEL_OBJECT`, which is what a named pipe is.
  static const int seKernelObject = 6;
  static const int ownerSecurityInformation = 0x00000001;

  /// The SID a token's [informationClass] points at.
  ///
  /// Both `TOKEN_USER` and `TOKEN_MANDATORY_LABEL` begin with a
  /// `SID_AND_ATTRIBUTES`, whose first field is the SID pointer, so one reader
  /// serves both.
  String? sidOfToken(int token, int informationClass) {
    final size = calloc<Uint32>();
    try {
      // Asked once with no buffer to be told how much room it needs.
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
        final sid = buffer.cast<IntPtr>().value;
        return sid == 0 ? null : sidToString(sid);
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(size);
    }
  }

  /// The last subauthority of a token's integrity SID — its level.
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
        // SID: revision, subauthority count, 6-byte authority, then the
        // subauthorities as 32-bit values — the last of which is the level.
        final count = (Pointer<Uint8>.fromAddress(sid) + 1).value;
        if (count == 0) return null;
        return Pointer<Uint32>.fromAddress(
          sid + 8 + (count - 1) * 4,
        ).value;
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
      if (out.value == 0) return null;
      return Pointer<Utf16>.fromAddress(out.value).toDartString();
    } finally {
      calloc.free(out);
    }
  }
}
