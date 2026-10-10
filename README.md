# Gandar

A cross-platform audio player that uses **Spotify for your library** and
**open YouTube extraction for the audio**.

Gandar reads your liked songs and playlists from the Spotify Web API, then
resolves a direct, ad-free audio stream for each track at play time. Metadata
comes from Spotify; the audio never does.

> **Status: Phase 1 (desktop foundation).** The desktop app is complete and
> runs on Windows. Android adaptation (background audio service, media
> notifications, lock-screen controls) and the release pipeline are Phase 2/3.

---

## Features

**Library**

- Spotify OAuth sign-in using Authorization Code + **PKCE** (no client secret
  is ever embedded in the app).
- Read liked songs and playlists; unlike / re-like tracks from inside Gandar.
- Virtualized lists, so a library of thousands of tracks scrolls smoothly.

**Advanced playback settings** — modeled on Spotify's playback menu

- 10-band equalizer with 13 presets (Flat, Bass Boost, Rock, Pop, Classical,
  Jazz, Hip-Hop, Dance, Electronic, Acoustic, Loudness, Vocal, Bass Reducer)
  and per-band custom gain (`-12 … +12 dB`).
- Crossfade from `0` to `12` seconds, plus an Automix toggle for smoother
  transitions.
- Volume normalization (EBU R128 `loudnorm`) with Quiet / Normal / Loud
  targets.
- Mono audio downmix.
- Gapless playback.
- Shuffle modes: **Off**, **Standard** (uniform Fisher-Yates) and **Smart**
  (avoids replaying tracks you heard recently).
- Pre-fetch the next track's stream for a gapless hand-off.

**Themes**

- Two built-in themes: **Spotify Classic** (`#1DB954` on near-black) and
  **Earthy Brown** (warm charcoal, espresso, mahogany and amber).
- Import and export themes as `.json` **or** `.yaml`.
- Quick customization of the accent colour and corner radius; custom themes are
  saved and selectable.

**Smart cache**

- Cached audio is tracked by **last played**, not download time.
- Automatic eviction by maximum disk usage and by idle days (LRU).
- Permanent `Spotify track → YouTube video` mapping cache, so a song you have
  played once resolves instantly forever after.

---

## Getting started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (stable channel,
  Dart 3.13+)
- For Windows builds: Visual Studio with the **Desktop development with C++**
  workload
- For Android builds (Phase 2): the Android SDK

```bash
flutter doctor -v
```

### 1. Register a Spotify application

1. Go to the [Spotify developer dashboard](https://developer.spotify.com/dashboard)
   and create an app.
2. Add this **Redirect URI** exactly:

   ```
   http://127.0.0.1:8888/callback
   ```

   (Spotify allows any port on a loopback IP, but the path must match.)
3. Under **User Management**, add the Spotify account(s) you will sign in with.
   New Spotify apps are in *Development mode*, which only allows allow-listed
   accounts to authorize.
4. Copy the **Client ID**. You do **not** need the client secret.

### 2. Run Gandar

```bash
flutter pub get
dart run build_runner build          # generates the drift database code
flutter run -d windows --dart-define=SPOTIFY_CLIENT_ID=your_client_id_here
```

Without `SPOTIFY_CLIENT_ID` the app still runs — themes, playback settings and
the cache all work locally — but the sign-in screen will explain what is
missing.

### 3. Build

```bash
flutter build windows --release --dart-define=SPOTIFY_CLIENT_ID=your_client_id_here
flutter build apk --release --dart-define=SPOTIFY_CLIENT_ID=your_client_id_here   # Phase 2
```

---

## Architecture

Gandar is split into strict layers. Details in
[docs/architecture.md](docs/architecture.md).

```
lib/
  app/         Router and the responsive shell (desktop rail / mobile nav)
  core/        Theme engine, playback settings, motion, errors
  domain/      Pure models and repository interfaces
  data/        Spotify API + PKCE auth, YouTube resolution, drift storage, cache
  playback/    Audio engine, filter math, crossfade, queue and shuffle
  features/    One folder per screen
  state/       Riverpod providers + the dependency graph
  widgets/     Shared UI building blocks
```

Notable choices:

| Concern | Choice | Why |
| --- | --- | --- |
| Audio backend | `media_kit` (libmpv) | EQ, loudness normalization, mono and gapless are native mpv audio filters — one implementation for every platform |
| State | Riverpod | Compile-safe, testable, no `BuildContext` coupling |
| Database | `drift` (SQLite) | Typed queries and migrations for the mapping/cache/history tables |
| Auth | Hand-rolled PKCE + loopback server | Pure Dart, no native plugin, fully unit-testable |
| Extraction | `youtube_explode_dart` behind an interface | YouTube extraction is fragile; swap in `yt-dlp` or NewPipe without touching playback |

---

## Testing

```bash
flutter analyze
flutter test
```

136 tests cover the theme codec (JSON + YAML round-trips and validation),
playback settings and persistence, mpv filter-string generation, equal-power
crossfade math, momentum projection, both shuffle strategies, the playback
queue, LRU/idle cache eviction, stream pre-fetching, PKCE and the OAuth flow,
the Spotify API client (including the deprecated-endpoint fallbacks) and the
drift repositories.

---

## Known limitations

- **YouTube extraction is inherently fragile.** YouTube changes its player
  responses regularly, so a stream that resolves today may return 403
  tomorrow. Gandar isolates this behind `AudioResolver`, tries several
  extraction clients and multiple candidate videos, and never trusts a cached
  stream URL — but individual failures are expected. Please report them with
  the video id.
- **Spotify Development mode.** Until your app is granted Extended Quota mode,
  only allow-listed accounts can sign in, and some endpoints may be rate
  limited. Gandar surfaces a 403 with that explanation rather than failing
  silently.
- **Debug builds log a media_kit warning.** `media_kit`'s debug-only native
  reference holder tries to write a lock file into `%TEMP%`. Its failure is
  harmless (the code path returns immediately when not in debug mode) and does
  not occur in release builds.
- **Linux/macOS desktop** need their `media_kit_libs_*` packages added before
  they will build; Phase 1 targets Windows.

## Legal

Gandar is a metadata and playback front-end. It does not host, distribute or
bundle any audio, and it is not affiliated with or endorsed by Spotify or
YouTube. Respect the terms of service of any service you connect to and the
copyright of the music you listen to.

## License

[MIT](LICENSE)
