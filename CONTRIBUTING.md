# Contributing to Gandar

Thanks for helping out. Gandar is MIT-licensed and welcomes issues and pull
requests.

## Before you start

```bash
flutter pub get
dart run build_runner build     # required after changing the drift schema
flutter analyze
flutter test
```

Both `flutter analyze` and `flutter test` must pass. The analyzer runs with
`strict-casts`, `strict-inference` and `strict-raw-types` enabled, so please fix
type warnings rather than suppressing them.

## Ground rules

- **Keep the layers honest.** `domain/` and `core/` must not import
  `package:flutter/material.dart`, `dio`, or `media_kit`. If you need a
  platform capability, add an interface and fake it in tests.
- **No `print`.** Lint rule `avoid_print` is on; surface user-facing problems in
  the UI instead.
- **Test the logic, fake the platform.** New behaviour should be testable
  without a real audio device, a real browser, or the network.
- **Never commit credentials.** The Spotify client id is passed with
  `--dart-define=SPOTIFY_CLIENT_ID=...`; there is no config file to check in.
  Tokens belong in `flutter_secure_storage`.

## Changing the database

1. Edit the tables in `lib/data/storage/app_database.dart`.
2. Bump `schemaVersion`.
3. Add a migration step in `MigrationStrategy`.
4. Re-run `dart run build_runner build`.
5. Add a repository test in `test/local_repositories_test.dart`.

## Changing playback settings

Playback settings flow in one direction:

```
SettingsPage → PlaybackSettingsController.update()
             → SettingsRepository.savePlayback()      (persist)
             → PlaybackController.updateSettings()    (apply to engine)
             → AudioFilters.buildAf()                 (pure, testable)
```

Add the field to `PlaybackSettings` (with `copyWith`, `toJson`, `fromJson` and
`sanitized` bounds), then to `AudioFilters.buildAf` if it maps to an mpv filter,
then to the UI, then to `test/playback_settings_test.dart`.

## Adding a theme

Built-in themes live in `lib/core/theme/theme_presets.dart`. User themes are
imported at runtime; the on-disk shape is documented in
`lib/core/theme/theme_codec.dart` and looks like this:

```yaml
format: gandar.theme
version: 1
id: my_theme
name: My Theme
brightness: dark
colors:
  backgroundPrimary: "#101010"
  backgroundSecondary: "#181818"
  surface: "#202020"
  surfaceElevated: "#2A2A2A"
  textPrimary: "#F5F5F5"
  textSecondary: "#AAAAAA"
  accent: "#00AAFF"
  accentAlt: "#0088CC"
  border: "#333333"
radius:
  sm: 4
  md: 10
  lg: 18
```

## Reporting playback failures

If a track will not play, please include:

- the Spotify track / YouTube video id,
- the error text shown in **Settings → Engine**,
- whether a different video for the same song works.

YouTube extraction breakage is expected from time to time; a reproducible video
id is what makes it fixable.
