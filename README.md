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
| [docs/discord.md](docs/discord.md) | **Discord Rich Presence.** Portal setup, the art assets and their exact names, what each profile slot shows, and how to verify it against a real client |
| [docs/platforms.md](docs/platforms.md) | Why a 32-bit Windows build is not possible, what Windows arm64 would need, and a platform-by-platform assessment of macOS and Linux |
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
- **Make your own playlists** and add songs to them from a picker that stays
  open while you build the list. **Delete any playlist** — including imported
  ones — and rename any of them. Deleting a playlist never deletes the music:
  a playlist is a view over the library, never the library itself.
- **Albums**, grouped from the album names your import carries.
- Remove tracks you no longer want with one click.
- Virtualized lists everywhere, so a library of thousands of tracks — or a
  queue of 1,787 — scrolls without building a single row you cannot see.

**Player**

- **Lyrics on a button in the playback bar.** One tap opens the words for
  whatever is playing, from [LRCLIB](https://lrclib.net) — free, open and
  keyless.
- **The current line is highlighted as it is sung** when the source is
  time-synced, following the player's own clock: seeking moves the highlight
  with the audio, pausing holds it, and nothing is lit up during a long
  instrumental intro. Times when the track has only plain words, and says which
  of the two it is rather than pretending. A missing lyric is a sentence, not an
  empty box.
- **Elapsed, total length and time remaining** on the playback bar, all three,
  so you can see how far in you are *and* decide whether there is time for
  another track.
- **Share** any track as a YouTube or a Spotify link, whichever service knows
  it. A track that came from Spotify also offers its resolved YouTube video,
  because that mapping is already stored locally. Every list row is
  right-clickable for the same menu.
- **The whole queue is visible and tappable**, so any track in it can be jumped
  to directly.

**Advanced playback settings** — modeled on Spotify's playback menu

- **Interactive 10-band equalizer**: drag the curve instead of nudging ten
  sliders. It ships with 13 presets (Flat, Bass Boost, Rock, Pop, Classical,
  Jazz, Hip-Hop, Dance, Electronic, Acoustic, Loudness, Vocal, Bass Reducer)
  and you can **save your own presets by name** — the curve is saved with them
  and kept in your settings.
- **Audio quality per track** — *Data saver*, *Balanced* or *Best* — which
  decides which of YouTube's several published audio streams is fetched.
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
- **A live theme editor.** Every colour in the token set and all three corner
  radii are editable in the app, with a colour picker (swatches, hex, RGB) and
  the whole app repainting as you change things. Editing a built-in preset
  saves a copy, so the presets stay pristine, and any theme can be saved under
  a name of its own.

**Feed**

- A **Feed** tab listing recent uploads from the artists you actually listen
  to — ranked by play history, not by how many songs are filed under a name.
  Tapping any entry plays the feed as a queue starting there.
- It reads each artist's **public YouTube channel feed**, which needs no
  account. Finding the channel is a search, so the channel behind a name is a
  labelled best guess, and the whole list is best-effort by construction.

**Mashup**

- A **Mashup** tab that blends two or more tracks into one continuous set:
  pick the songs, choose how long each one takes to become the next, and play.
  The blend is saved as a real playlist if you want it again.
- Be clear about what it is: a player runs one stream at a time, so this
  *blends* records into a gapless set — it does not layer two songs on top of
  each other, which would need two decoders and a beat grid.

**Savings**

- A **What you have saved** card built on a model of how a free, ad-supported
  service actually behaves: ad breaks every ten to fifteen minutes of
  *listening time*, ads up to 30 seconds, and an audio CPM in the $15–$25
  range. All of it is adjustable and every assumption is printed with it.
- It reports the subscription you did not buy, the **advertising spend a free
  listener would have generated** (per hour and in total), the ad time skipped,
  and the estimated artist payouts your plays represent — with the sources
  listed underneath, because none of these numbers is published by Spotify.

**Smart cache**

- Cached audio is tracked by **last played**, not download time.
- Automatic eviction by maximum disk usage and by idle days (LRU).
- Permanent `track → YouTube video` mapping cache, so a song you have played
  once resolves instantly forever after.

**Discord Rich Presence**

- Show **what you are playing, with the artist and album**, on your Discord
  profile — and **how long you have spent in Gandar**, counted from launch
  rather than from playback.
- The track line carries a **live progress timer** while playing and drops it
  while paused, because Discord's clock keeps running on its own.
- Configurable in Settings: the Application ID, whether the song is shown at
  all, and whether the time in Gandar appears.
- It fails soft in every direction. No Discord, no signed-in client, no
  Application ID — the app plays music exactly as it did and the card says which
  of those it is. Retries back off from five seconds to five minutes.
- The client is written against `dart:ffi` rather than `dart:io`, because
  `dart:io` cannot open a Windows named pipe at all: see
  [docs/discord.md](docs/discord.md).

**Artwork that does not leave holes**

- Covers are looked up per track from Apple's public catalogue, at about twenty
  requests a minute. When a track has no cover of its own, the pass now falls
  back to **the picture it is filed under**: a cover already stored for another
  track on the same album is borrowed locally and instantly, and failing that
  the album itself is looked up once per album rather than once per track.

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

**The finished app is `dist/Gandar/Gandar.exe`.** Double-click that file; the
rest of the folder has to stay next to it, because it is what the exe loads
the Flutter engine, libmpv and SQLite from. Building by hand instead —
`flutter build windows --release` — puts the same bundle somewhere else,
`build/windows/x64/runner/Release/`, which `flutter clean` deletes; that path
is a build artefact, `dist/Gandar/` is the one to point people at.

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

### Why a playlist stops at 50 tracks

This is Spotify's ceiling, not Gandar's, and it is worth being precise about
it. The embed page Spotify serves its own widget carries at most 50 track
entries. Checked directly, it returns exactly 50 for a playlist with thousands,
and Spotify's ordinary playlist page carries no track data at all — it is
rendered in the browser. The one route past 50 would be an authenticated
token, and the endpoint that used to hand one out anonymously now answers
`403 URL Blocked`.

So the honest options are:

- **Playlists up to 50 tracks:** paste the link, and they import whole.
- **Longer playlists, or your own liked songs:** export once from
  [exportify.net](https://exportify.net) and import the CSV. That path has no
  cap at all, because the file is yours.
- Gandar removes its *own* caps: a library search no longer stops at 50
  results, and the queue renders every track it holds.

Two more honest caveats. This is **not a supported interface**: Spotify can
change or close that page at any time, and each failure is reported as a
sentence rather than a crash. And it only ever reads what any browser can
already see — your liked songs are account data, are not public, and can only
arrive through a file you export yourself.

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
               lyrics, artist feeds, YouTube resolution, drift storage, cache
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
| Lyrics | LRCLIB | Free and documented, no account or key, and it returns both plain and time-synced lyrics |
| Feed | YouTube channel Atom feeds, parsed by hand | A channel's uploads are a public feed, and four element names did not justify an XML dependency |

### Startup

Time to the first frame is measured in a release build, from a cold launch, and
logged on every run:

```
INFO [startup] data directory resolved at 13 ms
INFO [startup] window chrome: 20 ms
INFO [startup] first frame in 122 ms
```

The window handshake used to be awaited on the critical path even though the
native runner shows the window itself from `SetNextFrameCallback`
(`windows/runner/flutter_window.cpp`), which meant the app could not draw until
two platform round-trips had finished. Making it non-blocking took a release
build from a **272 ms median to a 122 ms median** across four runs each. What
remains is the data-directory probe, the settings read and Flutter's own engine
draw — all of which happen inside the process before anything is on screen.

---

## Testing

```bash
flutter analyze
flutter test
```

305 tests cover the theme codec (JSON + YAML round-trips, validation, and every
example theme file that ships in [examples/themes/](examples/themes) — so the
documented format cannot drift from the code), the theme token accessors the
editor writes through, playback settings and persistence, mpv filter-string
generation, equal-power crossfade math, momentum projection, both shuffle
strategies, the playback queue, LRU/idle cache eviction, stream pre-fetching,
the audio stream selector at all three quality levels, the public-page importer
against pages recorded from the real site, CSV/JSON library files, the artwork
pass including its album fallback, YouTube channel feed parsing, the lyrics
payload parser, share-link construction, the time-based savings arithmetic,
the host politeness governor, the provider retry policy, the failure wording on
screen, and the drift repositories (including making, editing and deleting a
playlist).

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
- **Lyrics come from a community database.** LRCLIB has none for a fair share
  of tracks, and those say so rather than showing an empty panel. Highlighting
  needs the source's timestamps: for a track whose lyrics are plain text there
  is nothing to follow, and the sheet says so instead of guessing. The sync is
  also the lyric's own, so a DJ edit, a live version or a track played from a
  different master can drift.
- **The feed's channel matching is a heuristic.** It searches YouTube for the
  artist and prefers the first result whose channel name contains the artist's,
  so a short or common name can pick the wrong channel. It is labelled as a
  guess wherever it is shown.
- **A mashup blends, it does not layer.** Its own tab says so: one stream plays
  at a time, so two songs cannot be superimposed.
- **The savings figures are third-party estimates, not Spotify's numbers.**
  Spotify publishes its per-subscriber revenue (~€4.89/month in Q2 2026) but
  not a per-hour ad figure or a per-stream rate. The card therefore models the
  ad load from external observations, prints every assumption, and lists its
  sources on screen. Treat the totals as an illustration, not an accounting.
- **Discord Rich Presence needs an application you create.** The app half is
  built and verified, but the presence is silent until you register an
  application on the Discord Developer Portal, paste its Application ID into
  Settings → Discord, and upload the three art assets under their exact names.
  Until the art is uploaded Discord accepts the presence and silently drops the
  image keys. It is also **Windows-only** so far: the transport reaches a pipe
  on Windows, and macOS/Linux would need a unix-domain-socket equivalent. See
  [docs/discord.md](docs/discord.md).
- **Time in Gandar counts from launch, not from playback**, and is written to
  disk once a minute. A process that is killed loses up to that minute, and a
  machine that sleeps is not counted as listening — a single tick is capped at
  90 seconds so a suspended laptop cannot add eight hours at once.
- **Light themes are less battle-tested than dark ones.** The default is dark;
  [Paper Light](examples/themes/paper_light.gandar-theme.json) is the only light
  example, and contrast is not automatic outside the accent pair.
- **Debug builds log a media_kit warning.** `media_kit`'s debug-only native
  reference holder tries to write a lock file into `%TEMP%`. Its failure is
  harmless (the code path returns immediately when not in debug mode) and does
  not occur in release builds.
- **No 32-bit Windows build exists, and none can.** Flutter's Windows desktop
  toolchain emits x64 and arm64 only, and upstream has no plans to change that.
  Windows arm64 is the available alternative and needs an arm64 build host.
  See [docs/platforms.md](docs/platforms.md).
- **Linux/macOS desktop** would need their `media_kit_libs_*` packages, the
  platform scaffolding, a per-platform window chrome and (on macOS) signing and
  notarisation before they would build and ship. Most of the app is already
  portable; the specific blockers are enumerated in
  [docs/platforms.md](docs/platforms.md).

## Legal

Gandar is a metadata and playback front-end. It does not host, distribute or
bundle any audio, and it is not affiliated with or endorsed by Spotify or
YouTube. Respect the terms of service of any service you connect to and the
copyright of the music you listen to.

## License

[MIT](LICENSE)
