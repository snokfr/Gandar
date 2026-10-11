# Gandar

A cross-platform audio player that uses **Spotify for your library** and
**open YouTube extraction for the audio**.

Gandar has no Spotify account and asks for no sign-in: it reads public playlist
pages and the library files you export yourself, keeps them on this machine,
and resolves a direct, ad-free audio stream for each track at play time.
Metadata comes from Spotify; the audio never does.

> **Status: Phase 1 (desktop foundation).** The desktop app is complete and
> runs on Windows. Android adaptation (background audio service, media
> notifications, lock-screen controls) is Phase 2; the CI and release workflows
> are written but have not been executed yet.

---

## Documentation

| Document | Contents |
| --- | --- |
| [docs/styling.md](docs/styling.md) | **Write your own theme.** The custom theme file format: field-by-field reference, colour formats, validation errors, worked examples, checklist |
| [docs/building.md](docs/building.md) | Install Flutter, run in debug, build a release, where the release build lands, packaging and signing, GitHub Actions releases, troubleshooting |
| [docs/architecture.md](docs/architecture.md) | Layer boundaries and the reasoning behind the audio engine, extraction, auth and database choices |
| [docs/theming-internals.md](docs/theming-internals.md) | Contributors only: how design tokens become a Material theme, and the rules that keep user themes working |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Where to add settings, themes, migrations and tests |

---

## Features

**Library**

- **Import your library** from an Exportify CSV or Spotify's own
  `YourLibrary.json`, and **import any public playlist, album or track** by
  pasting its link. No account, no client id, no Premium.
- Everything is stored locally in SQLite, so the library, the playlists and
  your play history work offline.
- Remove tracks you no longer want with one click.
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
- **Bring your own:** a theme is a small JSON or YAML file describing every
  colour and corner radius. Import it and the whole app restyles instantly — no
  code, no rebuild. See [docs/styling.md](docs/styling.md) and the ready-made
  files in [examples/themes/](examples/themes).
- Quick customization of the accent colour and corner radius from inside the
  app; custom themes are saved and selectable.

**Smart cache**

- Cached audio is tracked by **last played**, not download time.
- Automatic eviction by maximum disk usage and by idle days (LRU).
- Permanent `track → YouTube video` mapping cache, so a song you have played
  once resolves instantly forever after.

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

### 1. Run Gandar

```bash
flutter pub get
dart run build_runner build          # generates the drift database code
flutter run -d windows
```

There is nothing to configure and nothing to sign into. The library starts
empty; fill it from the **Import** screen (see below).

### 2. Build a release

```bash
./tool/build_release.sh          # builds, then copies to dist/Gandar/
```

That script builds the Windows release and copies the whole bundle to
`dist/Gandar/` — always the same path, so that folder is both the copy to run
and the one to ship. Details:
[Release build — Windows](docs/building.md#4-release-build--windows).

Full instructions, packaging and automated releases:
**[docs/building.md](docs/building.md)**.

---

## Getting music in

The **Import** screen (in the sidebar, or the button on either empty screen) is
how music arrives, because Spotify has no supported way for an app without a
Premium-owning developer account to read a library:

| Route | Gets you | Limits |
| --- | --- | --- |
| **Paste a link** — a public playlist, album or track | The collection's name, artwork and tracks; playable, stored locally | Spotify's public embed page carries at most **50 tracks** per playlist, so longer ones are imported in part |
| **Import a file** — Exportify CSV or Spotify's `YourLibrary.json` | *Your* liked songs, complete | The file has to be exported once by hand from [exportify.net](https://exportify.net) or Spotify's *Download your data* page |

How the link import works: it fetches `open.spotify.com/embed/<kind>/<id>` —
the same server-rendered page Spotify's own embed widget uses — and reads the
`__NEXT_DATA__` JSON out of it, falling back to Spotify's public oEmbed
endpoint for title and artwork. No account, no client id, no token.

Two honest caveats. It is **not a supported interface**: Spotify can change or
close that page at any time, and each failure is reported as a sentence rather
than a crash. And it only ever reads what any browser can already see — your
liked songs are account data, are not public, and can only arrive through a
file you export yourself.

Verified against the live site by
[test/live/spotify_public_live_test.dart](test/live/spotify_public_live_test.dart),
which is skipped unless you run it deliberately:

```bash
flutter test --dart-define=LIVE=true test/live/spotify_public_live_test.dart
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
  data/        Public-page reads, library-file imports, artwork lookup,
               YouTube resolution, drift storage, cache
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
| Library source | Public embed pages and exported files | Spotify refuses Web API calls from a Development-mode app whose owner has no Premium, so an account-based path would leave most users with an empty library |
| Extraction | `youtube_explode_dart` behind an interface | YouTube extraction is fragile; swap in `yt-dlp` or NewPipe without touching playback |
| Artwork | Apple's public iTunes Search API, throttled to ~20 requests a minute | Covers come from a public catalogue with no key or account; the pass is resumable and stoppable |
| Styling | Design tokens → one `ThemeEngine` mapping | No colour or radius literals in feature code, so a user-authored theme restyles everything |

---

## Testing

```bash
flutter analyze
flutter test
```

209 tests cover the theme codec (JSON + YAML round-trips, validation, and every
example theme file that ships in [examples/themes/](examples/themes) — so the
documented format cannot drift from the code), playback settings and
persistence, mpv filter-string generation, equal-power crossfade math, momentum
projection, both shuffle strategies, the playback queue, LRU/idle cache
eviction, stream pre-fetching, the public-page importer against pages recorded
from the real site, CSV/JSON library files, the artwork pass, the host
politeness governor, the provider retry policy, the failure wording on screen,
and the drift repositories.

---

## Known limitations

- **YouTube extraction is inherently fragile.** YouTube changes its player
  responses regularly, and it now demands a PO token from most players: the
  `android` and `ios` clients still answer, but the URLs they hand out cannot
  be fetched past their first megabyte, so nothing can play from them. Gandar
  therefore asks the one client whose URLs are still served in full —
  `VISIONOS`, which needs no PO token — and re-tests that choice with
  `dart run tool/client_matrix.dart "<videoId>"` when playback breaks. It also
  pauses extraction for five minutes after a refusal and refuses to call a
  refused stream "finished", so a broken stream stops playback with a message
  instead of marching through the queue in silence.
- **Every play resolves its video again.** Nothing streams from a stored URL:
  those expire and are bound to the address that asked for them. Resolving
  costs a player request (and a watch page), which is why tracks you have
  played before are remembered by id — `mappings` — rather than by URL.
- **Public-page imports are best-effort by nature.** They read a page Spotify
  serves its own embed widget, capped at 50 tracks per playlist, and Spotify
  may change it without notice. Long playlists and your own liked songs are
  covered by the file import instead.
- **Light themes are less battle-tested than dark ones.** The default is dark;
  [Paper Light](examples/themes/paper_light.gandar-theme.json) is the only light
  example, and contrast is not automatic outside the accent pair.
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
