# Gandar architecture

Gandar is organized as a set of concentric layers. Dependencies only ever point
inward: `features` → `state` → `data`/`playback` → `domain` → `core`. Nothing in
`domain` or `core` knows about Flutter widgets, HTTP, or libmpv.

```
┌──────────────────────────────────────────────────────────────┐
│ features/   screens: library, playlists, search, player,     │
│             settings, themes, auth                           │
├──────────────────────────────────────────────────────────────┤
│ state/      Riverpod providers, AppDependencies,             │
│             PlaybackController                               │
├──────────────────────────────────────────────────────────────┤
│ data/       SpotifyClient + PKCE auth · YouTube resolver ·    │
│             drift database · cache manager                   │
│ playback/   AudioEngine (media_kit) · filters · crossfade ·   │
│             queue + shuffle · preloader                      │
├──────────────────────────────────────────────────────────────┤
│ domain/     Track, Playlist, ResolvedStream, CacheEntry,      │
│             repository interfaces                            │
├──────────────────────────────────────────────────────────────┤
│ core/       theme engine + codec, playback settings, motion   │
└──────────────────────────────────────────────────────────────┘
```

## Why these choices

### `media_kit` (libmpv) for audio

The advanced playback menu is the reason. Equalization, loudness
normalization, mono downmix and gapless playback are all **native mpv audio
filters**:

```dart
af = 'equalizer=f=31:t=q:w=1.0:g=6.0,loudnorm=I=-16.0:TP=-1.5:LRA=11,pan=mono|c0=0.5*c0+0.5*c1'
gapless-audio = yes
```

`just_audio` can only do EQ and loudness enhancement on Android, which would
mean one implementation on Android and none elsewhere. With mpv, the same
`AudioFilters.buildAf(settings)` output drives every platform, and it is a pure
function that unit tests can assert on without an audio device.

### `youtube_explode_dart` behind `AudioResolver`

Extracting audio from YouTube is a moving target (signature deciphering, PO
tokens, SABR-only responses, 403s). Rather than let that instability leak into
the player, resolution sits behind one interface:

```dart
abstract class AudioResolver {
  Future<ResolvedStream> resolve(Track track);
}
```

`YoutubeExplodeResolver` is the default implementation. It:
1. checks the permanent Spotify→YouTube mapping cache first,
2. otherwise searches for `"primary artist + title"`,
3. tries several extraction clients in order
   (`androidSdkless`, `tv`, `androidMusic`, `mweb`),
4. picks a stream with `AudioStreamSelector` (m4a preferred, highest bitrate),
5. tries the next candidate video if one yields nothing usable.

Because resolution is behind an interface, a `yt-dlp` or NewPipe-backed
implementation can be dropped in without touching `PlaybackController`.

**Stream URLs are treated as temporary.** They are signed and short-lived, so
they are never persisted; only the *video id* mapping is cached permanently.

### Hand-rolled PKCE instead of an auth plugin

Desktop and mobile clients cannot keep a client secret, so Spotify's
Authorization Code + PKCE flow is the correct one. Implementing it directly
means:
- no native plugin to keep working across Windows/Linux/macOS/Android,
- the loopback redirect listener and token exchange are ordinary Dart that
  tests can drive with a fake browser and a fake HTTP transport,
- tokens live in `flutter_secure_storage` and nowhere else.

`OAuthBrowser` is an interface specifically so tests never open a real browser.

### `drift` for the database

Four of the five tables exist for speed, not storage:

| Table | Purpose |
| --- | --- |
| `mappings` | Permanent `spotify_track_id → video_id` cache: instant replay |
| `cache_entries` | LRU bookkeeping keyed by `last_played_at` |
| `tracks`, `playlists` | Offline-first library listing |
| `play_history` | Feeds smart shuffle's "recently played" set |

Cache eviction orders by **last played**, not download time, so songs you
replay survive while one-off listens age out.

### The playback controller

`PlaybackController` is the single seam between UI and audio. Screens call
transport methods; they never touch the engine. It owns:

- the queue and its shuffle order (`PlaybackQueue` + `ShuffleService`),
- pre-fetching (`StreamPreloader`) so the next track is warm,
- filter application whenever settings change,
- play-history recording,
- auto-advance on `EngineState.completed`.

It exposes position and duration as `ValueNotifier`s rather than through
`notifyListeners`, so the seek bar repaints ~10x/second without rebuilding the
app chrome.

### Motion

Gesture behaviour follows physical-interface practice: springs rather than
fixed durations, an upward flick on the mini-player opens the full player using
release velocity, and `Motion.adaptiveDuration` shortens transitions when the
platform requests reduced motion.

## Testing strategy

Platform edges are faked, logic is not:

- `FakeAudioEngine` replaces libmpv for transport tests.
- `FakeHttpAdapter` replaces Dio's transport for Spotify tests.
- `FakeOAuthBrowser` replaces the system browser for auth tests.
- `FakeFileStore` replaces the disk for eviction tests.
- drift repositories are tested against a real in-memory SQLite database.

Everything else — filters, crossfade curves, shuffle, momentum projection,
theme codecs, cache policy — is pure enough to test directly.

## Roadmap

**Phase 2 — Android.** Add `media_kit_libs_android_audio`, an
`audio_service`-style foreground service for background playback, MediaSession
notifications and lock-screen controls, and an Android custom-scheme redirect
for OAuth (the loopback listener becomes the desktop path).

**Phase 3 — Releases.** GitHub Actions build Windows and Android artifacts on
version tags and attach them to a GitHub Release.
