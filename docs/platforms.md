# Other platforms: what is possible, and what is not

An honest assessment, written against the state of this checkout rather than
from a wish list. Nothing here has been implemented.

---

## 32-bit Windows: not possible, and not for want of trying

**There is no 32-bit Windows target for Flutter, and there is not going to be
one.** The request exists upstream and the answer is in
[flutter/flutter#37777](https://github.com/flutter/flutter/issues/37777): *"At
this time we have no plans to add support for 32-bit Windows as a target."*
Flutter's Windows desktop toolchain emits x64 and arm64 only; `flutter build
windows` has no `--target-platform`, because there is nothing to choose between
— the output directory is named for the only architecture it can be
(`build/windows/x64/runner/Release`). A 32-bit build is therefore not a
configuration change in this repository; it would mean replacing the UI toolkit,
the audio stack and the whole build system.

### What *is* available instead

| Target | Status | How |
| --- | --- | --- |
| Windows x64 | shipped | this is the current release artifact |
| Windows arm64 | supported by Flutter | must be built on an arm64 Windows host; `build/windows/arm64/` |
| Any 32-bit Windows | **not supported by Flutter** | — |

So the closest thing to what "32-bit" was reaching for — a build for machines
that the common x64 release does not serve — is **arm64**, not x86. That one is
genuinely available, and would need a second CI job on an arm64 runner plus a
line in `docs/building.md`; it has not been added, because it cannot be verified
on an x64 development machine and an unverified release artifact is worse than
an honestly missing one.

If the real goal is "runs on the old laptop", the useful facts are these: the
release build is a self-contained folder with no installer and no runtime to
install, and the only hard system requirement beyond x64 Windows 10 is a
Microsoft Visual C++ runtime, which Flutter's build embeds.

---

## macOS and Linux: possible, and closer than they look

The app was written to be cross-platform, and most of it already is. What is
missing is a small, specific, enumerable list — which is the good kind of
answer.

### What already works unchanged

| Piece | Why it is fine |
| --- | --- |
| `media_kit` playback | libmpv, which is a supported backend on macOS and Linux |
| EQ, normalization, mono, gapless | these are mpv **audio filters**, not platform code — `applyFilters` sets `af` on a `NativePlayer`, which is the same on all three |
| `drift` + `sqlite3_flutter_libs` | both support macOS and Linux |
| `window_manager` | supports macOS and Linux |
| `http`/`dio`, `youtube_explode_dart`, `file_picker`, `shared_preferences`, `path_provider` | pure Dart or platform-supported |
| The Dart UI, themes, state, search, imports | no platform branches at all |

### The blockers, in the order they would bite

1. **No platform scaffolding.** `macos/` and `linux/` do not exist — only
   `windows/` and `android/`. `flutter create --platforms=macos,linux .` would
   generate them. Everything after this point assumes it has been run.

2. **No audio backend for either platform.** `pubspec.yaml` depends on
   `media_kit_libs_windows_audio` and nothing else. Without
   `media_kit_libs_macos_audio` (or `media_kit_libs_linux_audio`) there is no
   libmpv in the bundle and the app builds but plays silence. On Linux there is
   the extra wrinkle that the packaged libmpv links against system libraries
   that must be declared in the packaging metadata, or the AppImage/deb installs
   and then fails at runtime.

3. **The window chrome is hand-written Win32.** `windows/runner/win32_window.cpp`
   claims the caption as client area in `WM_NCCALCSIZE` and answers
   `WM_NCHITTEST` so the top strip still drags. That is why the sidebar draws
   its own Mac-style traffic lights and the window has no title bar. macOS
   cannot use that code; it needs either the real `NSWindow` title-bar
   treatment, or `window_manager`'s `TitleBarStyle.hidden` plus the same
   drag regions. Linux needs its own answer again, because GNOME's client-side
   decorations and KDE's server-side ones do not agree. This is the single
   largest piece of genuinely new work, and it is per-platform.

4. **The Discord transport is Windows-only.** `discord_ipc.dart` opens a
   *unix domain socket* on macOS and Linux, and `dart:io` cannot open one of
   those any more than it can open a named pipe — `Socket.connect` is TCP and
   UDP only. The candidate-path logic already handles `XDG_RUNTIME_DIR`; what is
   missing is a `connect(2)` over `AF_UNIX` on the same `dart:ffi` footing as the
   `CreateFileW` path. The settings UI already says so rather than pretending
   otherwise.

5. **Two small platform branches to check.** `app_directory.dart` has a
   Windows-only branch for where data goes, and the log/export directory in
   `settings_page.dart` already handles macOS. Both are small, and both are
   written to fail soft.

6. **Distribution is a separate project on each.** macOS needs a Developer ID
   certificate and notarisation, or Gatekeeper refuses the app for everyone
   without an "open anyway" dance. Linux has no one packaging format: an
   AppImage is the least friction, a `.deb` plus a Flatpak is the well-behaved
   answer. `release.yml` currently builds Windows and Android only.

### Rough shape of the work

| Piece | Size |
| --- | --- |
| Scaffolding + audio libs + a window that opens and plays | small — mostly configuration |
| macOS window chrome and drag regions | moderate, and untestable from Windows |
| Linux window chrome | moderate, and worse than macOS because of the WM split |
| Discord over a unix socket | small, if the FFI seam holds up as expected |
| Signing, notarisation, packaging | its own task, mostly non-code |

None of it is architectural. The parts that usually make a desktop app
unportable — a bespoke audio engine, a native UI, a Windows-only database — are
not present here: playback is mpv, the UI is Flutter, and storage is SQLite.

### What can be checked today, without a Mac or a Linux box

- Linux: `flutter build linux` requires a Linux host, so it cannot be run from
  this checkout. **Not verified.**
- macOS: same, and additionally requires Xcode for a release build.
- Anything claimed above about dependency support is documented by those
  packages rather than observed here, and should be treated as a plan to verify
  rather than a result.
