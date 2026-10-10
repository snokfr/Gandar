# Setup and release builds

Everything needed to go from a clean machine to a distributable Gandar build,
plus how the automated release pipeline works.

---

## 1. What you need

| Tool | Why | Notes |
| --- | --- | --- |
| **Flutter** (stable channel) | Builds the app | 3.47+ / Dart 3.13+. Project was developed and verified on Flutter 3.47.7 |
| **Visual Studio 2022 or later** | Windows desktop builds | Must include the **Desktop development with C++** workload |
| **Git** | Version control | 2.40+ |
| **Android SDK + JDK 21** | Android builds only | **Not needed for Phase 1** (desktop) |

Check everything at once:

```bash
flutter doctor -v
```

You want green ticks for *Flutter* and *Visual Studio*. An `[X] Android
toolchain` is expected and fine for desktop-only work.

### Installing Flutter on Windows

Any of these works:

```powershell
# Option A: winget
winget install --id Flutter.Flutter

# Option B: official ZIP — extract to C:\src\flutter
# https://docs.flutter.dev/get-started/install/windows
```

Then add `C:\src\flutter\bin` to `PATH` and confirm:

```bash
flutter --version
flutter config --enable-windows-desktop
```

> **If `flutter --version` appears to hang** on the very first run, it is
> building the `flutter_tools` snapshot and waiting on Flutter's first-run
> analytics prompt. Fix it by running non-interactively:
> `CI=true FLUTTER_SUPPRESS_ANALYTICS=true flutter --version`.
> If it still hangs with no CPU use, see *Troubleshooting* §9.

---

## 2. Get the project running (development)

```bash
cd path/to/Gandar

# 1. Resolve Dart/Flutter packages
flutter pub get

# 2. Generate the database code (drift)
#    Required after a fresh clone if *.g.dart is missing, and after any
#    change to lib/data/storage/app_database.dart.
dart run build_runner build

# 3. Run it
flutter run -d windows --dart-define=SPOTIFY_CLIENT_ID=your_client_id
```

`flutter run -d windows` gives you hot reload: press `r` to reload, `R` to
restart, `q` to quit.

### The Spotify client id

Gandar takes the client id from a **compile-time define**, not a file, so
nothing secret-shaped is ever committed:

```
--dart-define=SPOTIFY_CLIENT_ID=abc123...
```

Without it the app still runs — themes, playback settings and the cache all
work — and the sign-in screen tells you the variable is missing.

To stop typing it, add a `--dart-define-from-file` file. That filename is
already git-ignored, so there is nothing to remember:

```jsonc
// dart_defines.json  (in .gitignore — safe for your client id)
{ "SPOTIFY_CLIENT_ID": "your_client_id" }
```

```bash
flutter run -d windows --dart-define-from-file=dart_defines.json
```

See the [README](../README.md#1-register-a-spotify-application) for creating the
Spotify app and the exact redirect URI.

---

## 3. The development loop

Run all three before committing; CI runs exactly these.

```bash
dart format lib test                                                     # format
flutter analyze                                                          # static analysis
flutter test                                                             # 141 tests
```

CI additionally fails on unformatted code:

```bash
dart format --output=none --set-exit-if-changed lib test
```

---

## 4. Release build — Windows

```bash
flutter build windows --release --dart-define=SPOTIFY_CLIENT_ID=your_client_id
```

Output:

```
build/windows/x64/runner/Release/gandar.exe
```

**Ship the whole `Release/` directory, not just the `.exe`.** The executable
needs the DLLs next to it (`flutter_windows.dll`, `data/`, the media_kit mpv
libraries). Zipping just the exe produces a build that crashes on launch.

Smoke-test the build before you publish it:

```bash
cd build/windows/x64/runner/Release
./gandar.exe
```

A healthy launch prints two lines and stays up:

```
[IMPORTANT:...] Using the Impeller rendering backend (OpenGLESSDF).
package:media_kit_libs_windows_audio registered.
```

…and creates its database at
`%APPDATA%\com.gandar\gandar\gandar.sqlite`. If the process exits immediately,
run it from a terminal to read the error.

### Packaging

```powershell
Compress-Archive -Path build/windows/x64/runner/Release/* `
                 -DestinationPath gandar-windows-x64.zip -Force
```

An `.msix` installer can be produced later with the `msix` package; the ZIP is
the simplest portable artifact and is what the release workflow uploads.

---

## 5. Release build — Android (Phase 2)

> **Prerequisite that does not exist yet.** The project currently depends on
> `media_kit_libs_windows_audio` only. Before an Android APK will have any
> audio backend, add the Android libs:
>
> ```bash
> flutter pub add media_kit_libs_android_audio
> ```
>
> Phase 2 also still needs the background audio service, media notifications
> and lock-screen controls. Building an APK before that gives you a UI with no
> playback, so treat the steps below as the packaging recipe, not a finished
> feature.

```bash
flutter build apk --release --dart-define=SPOTIFY_CLIENT_ID=your_client_id
# -> build/app/outputs/flutter-apk/app-release.apk

# Or an App Bundle for Play:
flutter build appbundle --release --dart-define=SPOTIFY_CLIENT_ID=your_client_id
```

### Signing

`flutter build apk --release` uses the **debug** key unless you configure a
release keystore, which is not acceptable for distribution. Create one and
point Gradle at it:

```bash
keytool -genkey -v -keystore ~/gandar-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

```properties
# android/key.properties   — NEVER commit this file
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=C:/Users/you/gandar-upload.jks
```

Then wire it into `android/app/build.gradle.kts` (`signingConfigs.release`)
following the [Flutter Android signing guide](https://docs.flutter.dev/deployment/android#signing-the-app).
Both `android/key.properties` and `*.jks` are already git-ignored, so a keystore
cannot be committed by accident.

Also note: the OAuth flow uses a loopback HTTP redirect, which is the desktop
path. Android needs a custom-scheme redirect registered with Spotify, so the
sign-in round trip will not work on Android until Phase 2 lands.

---

## 6. Automated releases (GitHub Actions)

Two workflows ship with the repo.

### `.github/workflows/ci.yml`

Runs on every push to `main` and every pull request:

| Job | What it does |
| --- | --- |
| `analyze-and-test` (ubuntu) | `pub get` → `build_runner` → `dart format --set-exit-if-changed` → `analyze` → `test` |
| `build-windows` (windows) | builds the Windows release and uploads it as a temporary artifact |

CI needs **no secrets**. It compiles with a clearly fake placeholder client id
(`ci-placeholder`), which is enough to exercise the build path. That artifact
cannot sign in, which matches published releases — see below.

### `.github/workflows/release.yml`

Triggered by pushing a version tag, or manually from the Actions tab.

It builds **Windows** and an **Android APK**, then attaches both to a GitHub
Release with generated release notes.

Linux and macOS desktop jobs are deliberately absent: each needs its own
`media_kit_libs_*` package and a build that has actually been run once. Add them
together with those dependencies.

### Cutting a release

1. **No secret is needed, and none is configured.** The release workflow builds
   with **no Spotify client id**, so a download cannot sign in. Baking one in
   would hand your client id to every person who downloads a build, and that is
   not a trade worth making for a public repository.

   The sign-in screen in such a build explains what is missing. To get a build
   you can actually sign in with, users build locally with their own id:

   ```bash
   flutter build windows --release --dart-define=SPOTIFY_CLIENT_ID=their_own_id
   ```

   > A **runtime "Spotify client id" field in Settings** would remove this
   > limitation entirely: the id could be stored locally in
   > `shared_preferences` and used to construct the auth config at startup. That
   > is the recommended next step for this area.

2. Tag and push:

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. The workflow builds both artifacts and opens the release. Download them from
   the **Releases** page.

If you want to re-run a release for an existing tag, use **Actions → Release →
Run workflow** and pass the tag.

---

## 7. Where the app keeps its data

| Path | Contents |
| --- | --- |
| `%APPDATA%\com.gandar\gandar\gandar.sqlite` | Drift database: cached tracks/playlists, Spotify→YouTube mappings, cache index, play history |
| `%APPDATA%\com.gandar\gandar\shared_preferences.json` | Playback settings, active theme id, custom themes |

(On Linux/macOS these live under the equivalent application-support directory.)

To reset Gandar to a fresh state, delete that folder. Deleting only
`gandar.sqlite` clears the mapping and cache index but keeps your settings and
themes.

Tokens are **not** in either file — they are in the platform credential store
(Windows Credential Manager, macOS Keychain, libsecret on Linux) via
`flutter_secure_storage`.

---

## 8. Verifying a build

The checks that were actually run for the Phase 1 delivery, in order:

```bash
flutter analyze                                                  # exit 0, no issues
flutter test                                                     # exit 0, 141 passed
dart format --output=none --set-exit-if-changed lib test          # exit 0
flutter build windows --release                                  # exit 0
./build/windows/x64/runner/Release/gandar.exe                    # launches, DB created
```

One of those tests, [../test/docs_examples_test.dart](../test/docs_examples_test.dart),
decodes every file in [../examples/themes/](../examples/themes) with the shipped
codec and round-trips it through both formats. It is there so the theme file
format described in [styling.md](styling.md) cannot drift away from the code
that reads it.

For the database, confirm the schema rather than assuming:

```bash
python -c "import sqlite3;c=sqlite3.connect(r'%APPDATA%\com.gandar\gandar\gandar.sqlite');print([r[0] for r in c.execute(\"select name from sqlite_master where type='table'\")])"
# expect: cache_entries, mappings, play_history, playlists, tracks
```

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `flutter --version` hangs, no CPU use, no output | The `flutter_tools` app-jit snapshot build is deadlocked on the first-run prompt | Run `CI=true FLUTTER_SUPPRESS_ANALYTICS=true flutter --version`. If it still deadlocks, build a kernel snapshot instead (see below) |
| `Unable to locate Android SDK` from `flutter doctor` | Android SDK not installed | Expected for desktop work; install Android Studio to enable Android builds |
| `Could not find a suitable Visual Studio installation` | Missing the C++ workload | VS Installer → Modify → **Desktop development with C++** |
| `Target of URI doesn't exist: '...app_database.g.dart'` | Generated code missing | `dart run build_runner build` |
| Debug run logs `PathAccessException: ...media_kit.NativeReferenceHolder...` | media_kit's *debug-only* reference holder cannot write a temp lock file | Harmless, and it cannot happen in a release build — that code path returns immediately unless `kDebugMode` |
| Spotify sign-in returns 403 / "User not registered" | The app is in Development mode and your account is not allow-listed | Add your account under **User Management** in the Spotify developer dashboard |
| A track fails with a 403 or "All candidate videos failed" | YouTube changed its player responses, or this video has no usable audio-only stream | Expected fragility. Try another video for the same song; report the video id |
| `flutter build apk` succeeds but there is no sound | `media_kit_libs_android_audio` is not a dependency yet | `flutter pub add media_kit_libs_android_audio` (Phase 2) |
| Analyzer reports `strict_raw_types` / `strict_casts` errors | Expected — the project enables strict analysis on purpose | Fix the type; do not suppress it |

### Kernel-snapshot fallback for a hung Flutter install

If the snapshot build deadlocks and the standard fix does not help, you can
produce a runnable tool snapshot directly:

```bash
export FLUTTER_ROOT=/c/src/flutter
DART=$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart
"$DART" --snapshot="$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" \
        --snapshot-kind=kernel \
        --packages="$FLUTTER_ROOT/packages/flutter_tools/.dart_tool/package_config.json" \
        "$FLUTTER_ROOT/packages/flutter_tools/bin/flutter_tools.dart"
# then stamp it so Flutter does not rebuild:
printf '%s:' "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" > "$FLUTTER_ROOT/bin/cache/flutter_tools.stamp"
```

A kernel snapshot starts in a second instead of compiling for minutes, because
it does not run the tool's training pass.
