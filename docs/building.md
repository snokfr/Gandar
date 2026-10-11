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
flutter run -d windows
```

`flutter run -d windows` gives you hot reload: press `r` to reload, `R` to
restart, `q` to quit.

### There is nothing to configure

No client id, no token, no secret, no `--dart-define`. Gandar has no Spotify
account: it reads public playlist pages and the library files you export
yourself, both of which need no credentials. The library starts empty, so the
first thing to do in a fresh run is open **Import**.

---

## 3. The development loop

Run all three before committing; CI runs exactly these.

```bash
dart format lib test                                                     # format
flutter analyze                                                          # static analysis
flutter test                                                             # 209 tests
```

CI additionally fails on unformatted code:

```bash
dart format --output=none --set-exit-if-changed lib test
```

---

## 4. Release build — Windows

```bash
flutter build windows --release
# …copy the finished bundle somewhere fixed:
./tool/build_release.sh
```

`tool/build_release.sh` is the recommended path: it clears the stale output
directory first, builds, and then copies the whole bundle to **`dist/Gandar/`**,
so the app is always at the same path no matter how often `build/` is cleaned:

```
dist/Gandar/Gandar.exe      <- run this
dist/Gandar/flutter_windows.dll, libmpv-2.dll, data/, …
```

Add `--zip` for a `dist/gandar-windows-x64.zip` as well.

**Ship the whole folder, not just the `.exe`.** The executable needs the DLLs
next to it (`flutter_windows.dll`, `data/`, the media_kit mpv libraries). An exe
on its own crashes on launch.

The raw `flutter build` output lives at
`build/windows/x64/runner/Release/`, which `flutter clean` deletes; that is why
the release script copies out of it.

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
`%APPDATA%\Roaming\com.gandar\gandar\gandar.sqlite`. If the process exits
immediately, run it from a terminal to read the error, and check the newest file
in `%APPDATA%\Roaming\com.gandar\gandar\logs\`.

### Packaging

```powershell
Compress-Archive -Path dist/Gandar/* `
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
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk

# Or an App Bundle for Play:
flutter build appbundle --release
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

---

## 6. Automated releases (GitHub Actions)

Two workflows ship with the repo.

### `.github/workflows/ci.yml`

Runs on every push to `main` and every pull request:

| Job | What it does |
| --- | --- |
| `analyze-and-test` (ubuntu) | `pub get` → `build_runner` → `dart format --set-exit-if-changed` → `analyze` → `test` |
| `build-windows` (windows) | builds the Windows release and uploads it as a temporary artifact |


CI needs **no secrets and no configuration**: the app has no account, so
`flutter build` is the whole story.

### `.github/workflows/release.yml`

Triggered by pushing a version tag, or manually from the Actions tab.

It builds **Windows** and an **Android APK**, then attaches both to a GitHub
Release with generated release notes.

Linux and macOS desktop jobs are deliberately absent: each needs its own
`media_kit_libs_*` package and a build that has actually been run once. Add them
together with those dependencies.

### Cutting a release

1. **No secret is needed, and none is configured.** The release workflow needs
   no credentials at all: the published build is functionally identical to a
   local one.

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
| `%APPDATA%\Roaming\com.gandar\gandar\gandar.sqlite` | Drift database: the imported library and playlists, `track → video id` mappings, cache index, play history |
| `%APPDATA%\Roaming\com.gandar\gandar\shared_preferences.json` | Playback settings, active theme id, custom themes |
| `%APPDATA%\Roaming\com.gandar\gandar\logs\` | One log file per day |
| `%APPDATA%\Roaming\com.gandar\gandar\temp\` | media_kit's temporary playlists — see the `PathAccessException` row in Troubleshooting |

(On Linux/macOS these live under the equivalent application-support directory.)

Two things are worth knowing about the library folder. It is a *copy*: deleting
it removes nothing from Spotify, only from Gandar. And it contains no
credentials, because the app has none — there is no token store to clear and no
sign-out to perform.

---

## 8. Verifying a build

The checks that were actually run for the Phase 1 delivery, in order:

```bash
flutter analyze                                                  # exit 0, no issues
flutter test                                                     # exit 0, 209 passed
dart format --output=none --set-exit-if-changed lib test          # exit 0
./tool/build_release.sh                                          # exit 0, dist/Gandar/ refreshed
dist/Gandar/Gandar.exe                                          # launches, DB created
```

One of those tests, [../test/docs_examples_test.dart](../test/docs_examples_test.dart),
decodes every file in [../examples/themes/](../examples/themes) with the shipped
codec and round-trips it through both formats. It is there so the theme file
format described in [styling.md](styling.md) cannot drift away from the code
that reads it.

When playback problems need explaining, the probes work without the app — they
resolve and play the way Gandar does, with every message printed:

```bash
# which extraction clients still answer, what the CDN serves for each of their
# URLs, and how they rate on a full-file range. This is how the VISIONOS client
# was found, and it is the first thing to re-run when YouTube changes.
dart run tool/client_matrix.dart "<videoId or search query>"
# resolve one track the way the app does, then play it through mpv and watch
# the position move: the end-to-end check that audio actually comes out
LIBMPV_LIBRARY_PATH=dist/Gandar/libmpv-2.dll \
  dart run tool/visionos_probe.dart "<search query>"
# is the player itself fine? (no network involved)
dart run tool/mpv_probe.dart --local 'C:\Windows\Media\Ring01.wav'
```

For the database, confirm the schema rather than assuming:

```bash
python -c "import sqlite3;c=sqlite3.connect(r'%APPDATA%\Roaming\com.gandar\gandar\gandar.sqlite');print([r[0] for r in c.execute(\"select name from sqlite_master where type='table'\")])"
# expect: cache_entries, mappings, play_history, playlist_tracks, playlists, tracks
```

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `flutter --version` hangs, no CPU use, no output | The `flutter_tools` app-jit snapshot build is deadlocked on the first-run prompt | Run `CI=true FLUTTER_SUPPRESS_ANALYTICS=true flutter --version`. If it still deadlocks, build a kernel snapshot instead (see below) |
| `Unable to locate Android SDK` from `flutter doctor` | Android SDK not installed | Expected for desktop work; install Android Studio to enable Android builds |
| `Could not find a suitable Visual Studio installation` | Missing the C++ workload | VS Installer → Modify → **Desktop development with C++** |
| `Target of URI doesn't exist: '...app_database.g.dart'` | Generated code missing | `dart run build_runner build` |
| Pressing play does nothing, and the log shows `PathAccessException: Cannot create file, path = '\?\<temp>\<uuid>' (Access is denied, errno = 5)` | media_kit writes a temporary playlist into `Directory.systemTemp` before every playback, and something on the machine — an endpoint-protection or backup rule — refuses new files in `%TEMP%` from an unsigned binary | Gandar works around this: `[startup] playback temp: writable: <support>	emp` in the log means it found a directory it can write to and pointed media_kit there. If that line says *not writable* instead, allow new files in `%TEMP%` or run the build from a folder Windows trusts |
| Playback produces no sound, and the log's last line is `resolved "…" in N ms` | The stream resolved but the engine never accepted it | Read the whole `[playback]` sequence in the log; the engine reports its state and names the track |
| The Import screen opens no data, or `Spotify did not return the playlist data` | The link is private, made-for-you (Discover Weekly and friends), or Spotify changed its embed page | Public and collaborative playlists work; private ones do not. Export them instead, and re-check `parse` in `lib/data/spotify/spotify_public.dart` against a fresh page |
| Only 50 tracks arrived from a playlists link | `open.spotify.com/embed/...` carries one page of tracks, and that is the limit of the account-free route | Expected, and the UI says so. Use the Exportify CSV for the whole list |
| The library or playlists never leave the error state | A file that cannot be parsed is an answer, not a hiccup, so it is not retried — `gandarProviderRetry` in `lib/state/retry_policy.dart` returns null for it | Fix the cause and use the button in the error state; transport failures retry themselves |
| The log shows `Failed to open https://…googlevideo.com/…` for every track, and reading the URL shows the first megabyte is served while everything after it is `403` | The client that resolved the track handed out a URL googlevideo will not serve in full. Measured October 2026 with `tool/client_matrix.dart`: `android` and `ios` answer upstream, but on their URLs `bytes=0-1023` → 206 while `bytes=0-` and any range past ~1 MB → 403, because those URLs carry no PO token. No player can stream from that | Gandar asks only the `VISIONOS` client (`visionOsClient()` in [../lib/data/youtube/youtube_explode_resolver.dart](../lib/data/youtube/youtube_explode_resolver.dart)), whose URLs serve the whole file. If this returns, re-run `dart run tool/client_matrix.dart <videoId>` and switch the resolver to whichever client is serving full files |
| Resolution fails with `RequestLimitExceededException`, or the log says YouTube is asking Gandar to prove it is not a bot | The player request itself was rejected, and it will be rejected for every track in a row | Nothing to fix locally: a refusal is a refusal. Gandar pauses extraction for five minutes, says so in the log, and never reports a refused stream as a finished track. Waiting is the only fix |
| A track fails with "No video for this track yielded a playable audio stream" | YouTube changed its player responses, or this video genuinely has no usable audio-only stream | Expected fragility. Try another video for the same song; report the video id. `dart run tool/client_matrix.dart <videoId>` prints what each client answered and what the CDN serves for each of its URLs |
| The queue skips through tracks with no sound | Fixed behaviour, kept honest: mpv reports "completed" for a refused URL too. The engine now treats a completion with no decoded audio as an error, so playback stops with a message instead of advancing | If it still happens, the log has `playback ended at 0 ms of 0 ms` for the track to report |
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
