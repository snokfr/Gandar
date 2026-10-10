# Theming internals (for contributors)

**Looking for how to write a theme file?** See
[styling.md](styling.md) — that is the user-facing guide for custom theme
files. This document is the implementation behind it: how tokens become a
Material theme, and the rules that keep user-authored themes working.

---

## 1. The pipeline

```
ThemeTokens  ──►  ThemeEngine.build()  ──►  ThemeData  ──►  widgets
 (pure data)        (mapping)                (Flutter)      (read from Theme)
      ▲
      │
ThemeCodec  ◄──►  .json / .yaml theme files
```

Three ideas make this work:

1. **Tokens are plain data.** `ThemeTokens` is an immutable value object with
   no Flutter dependency beyond `Color`/`Brightness`. It is trivially
   serializable, comparable and testable.
2. **There is exactly one mapping.** `ThemeEngine.build()` is the *only* place
   that turns tokens into a `ThemeData`. Widgets never read tokens to pick a
   colour; they read the `ThemeData` built from them.
3. **Tokens are still reachable.** A `ThemeExtension` exposes the raw
   `ThemeTokens` as `context.gandarTokens` for widgets that need a token
   Material has no equivalent for (the radius scale).

## 2. The token set

Source: [`lib/core/theme/theme_tokens.dart`](../lib/core/theme/theme_tokens.dart)

| Token | Type | Meaning |
| --- | --- | --- |
| `id` | `String` | Stable machine identifier, e.g. `spotify_classic` |
| `name` | `String` | Label shown in the theme picker |
| `brightness` | `Brightness` | `dark` or `light` — drives the whole `ColorScheme` |
| `backgroundPrimary` | `int` (ARGB) | Scaffold / page background |
| `backgroundSecondary` | `int` | Navigation rail and sheet chrome |
| `surface` | `int` | Cards, list tiles |
| `surfaceElevated` | `int` | Player bar, dialogs, bottom sheets, inputs |
| `textPrimary` | `int` | Headings and body |
| `textSecondary` | `int` | Supporting copy, icons |
| `accent` | `int` | Primary action colour |
| `accentAlt` | `int` | Secondary accent (logo gradient, hover) |
| `border` | `int` | Dividers, card outlines, inactive track |
| `radiusSm` / `radiusMd` / `radiusLg` | `double` | Corner radius scale |

Colours are stored as **ARGB ints**, not `Color` objects, so they survive a JSON
round-trip losslessly and can be compared with `==`.

### Legibility guard: `onSurfaceAccent`

An imported theme may set an accent that is nearly the same as its background
(a very dark green on black). `onSurfaceAccent` detects that case and lightens
the accent so accent-coloured text stays readable. It is the only computed
colour in the token set, and it exists so a bad theme degrades rather than
disappears.

## 3. From tokens to `ThemeData`

Source: [`lib/core/theme/theme_engine.dart`](../lib/core/theme/theme_engine.dart)

### 3.1 `ColorScheme` mapping

| `ColorScheme` slot | Token |
| --- | --- |
| `primary` / `onPrimary` | `accent` / auto-contrast black or white |
| `secondary` / `onSecondary` | `accentAlt` / auto-contrast |
| `surface` / `onSurface` | `surface` / `textPrimary` |
| `surfaceContainerHighest` | `surfaceElevated` |
| `onSurfaceVariant` | `textSecondary` |
| `outline` / `outlineVariant` | `border` |
| `error` | fixed `#E5484D` |

`onPrimary`/`onSecondary` are computed from luminance, so a light accent gets
black text and a dark accent gets white text without the theme author having to
specify it.

### 3.2 Global surfaces

`scaffoldBackgroundColor` and `canvasColor` become `backgroundPrimary`, so every
screen is themed even if it never mentions a colour.

### 3.3 Component themes

Overridden so Material defaults never leak an off-theme colour: `appBarTheme`,
`cardTheme`, `dialogTheme`, `bottomSheetTheme`, `navigationRailTheme`,
`navigationBarTheme`, `sliderTheme`, `switchTheme`, `inputDecorationTheme`,
`dividerTheme`, `scrollbarTheme`, `listTileTheme`, `tooltipTheme`,
`progressIndicatorTheme`, `snackBarTheme`.

This is the layer that makes the app feel designed rather than default: the rail
indicator, slider thumb, switch track and focused input border all derive from
`accent` and `border`.

### 3.4 Typography

- **Size-specific tracking.** Large display text gets **negative** letter
  spacing (`-1.5 … -0.5`); small labels stay near `0`.
- **Inverse leading.** Large headings use tight line-height (`1.05–1.15`); body
  copy is looser (`1.45`).
- **Weight as hierarchy.** Emphasis comes from weight plus size, not size alone.

`titleLarge` is `w700`, `titleMedium` `w600`, and `bodyMedium` renders in
`textSecondary` so supporting copy recedes automatically.

## 4. Consuming the theme in a widget

### 4.1 `Theme.of(context)` — the default

```dart
final theme = Theme.of(context);
Text('Liked Songs', style: theme.textTheme.titleLarge);
Card(child: ListTile(...));   // picks up cardTheme and listTileTheme
```

Prefer built-in widgets (`Card`, `ListTile`, `Slider`, `Switch`,
`NavigationBar`) — they inherit the component themes from §3.3.

### 4.2 `context.gandarTokens` — the radius/colour escape hatch

```dart
final tokens = context.gandarTokens;
Container(
  decoration: BoxDecoration(
    color: tokens.surfaceColor,
    borderRadius: BorderRadius.circular(tokens.radiusMd),
    border: Border.all(color: tokens.borderColor),
  ),
);
```

[`lib/widgets/common.dart`](../lib/widgets/common.dart) (`GandarCard`,
`AlbumArt`, `TrackTile`, `EmptyState`, `GandarLogo`) is the reference; new shared
widgets should reuse those instead of re-deriving surfaces.

### 4.3 Never do this

```dart
// ✗ Hard-coded colour: breaks every theme, including the user's own.
color: const Color(0xFF1DB954)

// ✗ Hard-coded radius: ignores the user's radius scale.
borderRadius: BorderRadius.circular(8)
```

These two lines are the entire failure mode this architecture exists to prevent.

## 5. Runtime management

Source: [`lib/state/providers.dart`](../lib/state/providers.dart) (`ThemeController`)

```dart
class ThemeState {
  final ThemeTokens active;        // currently applied
  final List<ThemeTokens> custom;  // imported / tweaked themes
  List<ThemeTokens> get all => [...ThemePresets.all, ...custom];
}
```

| Action | Effect |
| --- | --- |
| `select(tokens)` | Make an existing theme active; saves `settings.theme.active.v1` |
| `importTheme(tokens)` | Add/replace by `id`, make active; saves the custom list and the active id |
| `removeCustom(id)` | Delete; falls back to a preset if it was active |

Persistence keys in [`settings_repository.dart`](../lib/core/settings/settings_repository.dart):

- `settings.theme.active.v1` → the active theme **id**
- `settings.theme.custom.v1` → a JSON array of encoded theme maps

Because the active theme is stored as an id, a built-in theme always resolves
even when the custom list is empty. An unrecognised id falls back to
`ThemePresets.defaultTheme` instead of failing.

The accent/radius editor in [`themes_page.dart`](../lib/features/themes/themes_page.dart)
writes a *derived* theme with id `<base>_custom`, so tweaking a preset never
overwrites the preset.

## 6. Motion, depth and materials

Source: [`lib/core/motion/motion.dart`](../lib/core/motion/motion.dart)

| Principle | Implementation |
| --- | --- |
| Springs, not durations | `Motion.standard` (critically damped) for ordinary UI; `Motion.momentum` (slightly under-damped) only where a gesture carried velocity |
| Momentum projection | `Motion.projectMomentum(v)` uses the exponential-decay form `(v/1000)·d/(1−d)`, `d = 0.998` — not `v²/2a` |
| Snap from the projection | `Motion.snapIndex(...)` picks the target nearest where the flick was *heading* |
| Soft boundaries | `Motion.rubberBand(...)` resists progressively instead of hard-stopping |
| Reduced motion | `Motion.adaptiveDuration(context)` shortens transitions when the platform asks for it |
| Translucent chrome | The player bar uses `surfaceElevated` at 96% alpha, so content reads as sitting under a floating layer |
| Material weight encodes hierarchy | Sidebar uses `backgroundSecondary`; the player bar and sheets use the lighter `surfaceElevated`, and the two are never stacked |
| Size-specific type | See §3.4 |

## 7. Adding a built-in theme

1. Add a `const ThemeTokens` to
   [`lib/core/theme/theme_presets.dart`](../lib/core/theme/theme_presets.dart)
   with a unique `id`.
2. Add it to `ThemePresets.all`.
3. Update the count assertion in
   [`test/theme_codec_test.dart`](../test/theme_codec_test.dart).

Nothing else is needed — the picker reads `ThemePresets.all`.

A theme that users should be able to author themselves does **not** need a code
change at all; ship it as a file in [`examples/themes/`](../examples/themes).

## 8. Rules to keep styling intact

1. **No colour literals in `lib/features/` or `lib/widgets/`.** Everything comes
   from `Theme.of(context)` or `context.gandarTokens`. The only permitted
   literals are `ColorScheme.error` and the accent swatch palette in the theme
   editor.
2. **No radius literals.** Use `tokens.radiusSm/Md/Lg`.
3. **Prefer Material components.** They inherit the component themes.
4. **New shared surfaces belong in [`common.dart`](../lib/widgets/common.dart).**
5. **Test both brightnesses** if you add a light theme; contrast is not automatic
   outside the accent pair.
6. **`ThemeEngine` is the only place that knows the token → Material mapping.**
   Do not branch on `ThemeTokens` inside feature code.

## 9. Where to look

| I want to… | File |
| --- | --- |
| Change the file format | [`theme_codec.dart`](../lib/core/theme/theme_codec.dart) |
| Add or change a token | [`theme_tokens.dart`](../lib/core/theme/theme_tokens.dart) |
| Change how tokens become Material | [`theme_engine.dart`](../lib/core/theme/theme_engine.dart) |
| Add a built-in theme | [`theme_presets.dart`](../lib/core/theme/theme_presets.dart) |
| Change theme selection/persistence | [`providers.dart`](../lib/state/providers.dart) |
| Change the theme screen | [`themes_page.dart`](../lib/features/themes/themes_page.dart) |
| Change springs / momentum | [`motion.dart`](../lib/core/motion/motion.dart) |
| Reuse a themed widget | [`common.dart`](../lib/widgets/common.dart) |
