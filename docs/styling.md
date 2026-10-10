# Writing a custom theme

A Gandar theme is a small text file — JSON or YAML — that describes every colour
and corner radius in the interface. Drop one in through the app and Gandar
restyles itself instantly. No code, no rebuild.

This page is the complete reference for that file. If you want to know how the
theming is implemented in Dart, read
[theming-internals.md](theming-internals.md) instead.

Ready-made files you can copy are in
[`examples/themes/`](../examples/themes).

---

## 1. Quick start

### Option A — copy an example

1. Open **Settings → Themes**.
2. Press **Import** and choose one of the files in
   [`examples/themes/`](../examples/themes).
3. It is applied immediately and saved.

### Option B — start from a template

Paste this into a new file, change the values, and import it:

```yaml
format: gandar.theme
version: 1
id: my_theme
name: My Theme
brightness: dark

colors:
  backgroundPrimary: "#0B0B0F"
  backgroundSecondary: "#121218"
  surface: "#17171F"
  surfaceElevated: "#22222C"
  textPrimary: "#F2F2F7"
  textSecondary: "#9A9AA8"
  accent: "#7C4DFF"
  accentAlt: "#B39DFF"
  border: "#2C2C38"

radius:
  sm: 6
  md: 12
  lg: 20
```

That is a complete, valid theme. Everything below explains each line.

### Option C — start from a built-in

Press **Export** to save the theme you are currently using, edit the file, and
import it back under a new `id`.

---

## 2. The file at a glance

```yaml
format: gandar.theme     # optional; must be this value if present
version: 1               # optional, informational
id: my_theme             # REQUIRED — machine identifier
name: My Theme           # REQUIRED by convention — shown in the picker
brightness: dark         # optional; "dark" (default) or "light"

colors:                  # REQUIRED — all nine keys
  backgroundPrimary: "#0B0B0F"
  backgroundSecondary: "#121218"
  surface: "#17171F"
  surfaceElevated: "#22222C"
  textPrimary: "#F2F2F7"
  textSecondary: "#9A9AA8"
  accent: "#7C4DFF"
  accentAlt: "#B39DFF"
  border: "#2C2C38"

radius:                  # optional — defaults to 6 / 12 / 20
  sm: 6
  md: 12
  lg: 20
```

The file extension does not matter. Gandar detects the format from the contents
(JSON first, then YAML), so `.json`, `.yaml`, `.yml` and `.gandar-theme.yaml` all
work.

---

## 3. Field reference

### Top level

| Field | Required | Default | Meaning |
| --- | --- | --- | --- |
| `format` | no | — | If present it must be exactly `gandar.theme`, otherwise the import is rejected. Use it to make a wrong file obvious. |
| `version` | no | — | Informational only. Currently `1`. |
| `id` | effectively yes | `custom` | The machine identifier. Also the **de-duplication key**: importing a theme with an existing `id` replaces it. Use lowercase words separated by underscores, e.g. `midnight_amber`. |
| `name` | no | `Custom Theme` | Label shown in the theme list and in the export dialog. |
| `brightness` | no | `dark` | `dark` or `light`. Anything else is treated as `dark`. See §7. |

### `colors` — all nine keys are required

This is the part of the file that actually paints the app. The right-hand column
is what you will see change.

| Key | What it paints |
| --- | --- |
| `backgroundPrimary` | The page background behind everything — the largest area on screen. |
| `backgroundSecondary` | The desktop navigation sidebar, and the backdrop of the full-screen player. Sits one step up from `backgroundPrimary`. |
| `surface` | Cards and list rows: playlist tiles, the "Storage & cache" card, each setting panel. |
| `surfaceElevated` | Anything floating above the page: the desktop playback bar, dialogs, bottom sheets, text input fields, tooltips, snackbars. Should be *lighter* than `surface` on a dark theme. |
| `textPrimary` | Headings, track titles, active labels. Also used for the label inside primary buttons. |
| `textSecondary` | Artist names under titles, descriptions under settings, section subtitles, inactive navigation icons. |
| `accent` | The primary action colour: play buttons, the "Play all" button, sliders, switch tracks, focused input borders, the selected navigation indicator, the progress bar, and the current track's title. |
| `accentAlt` | Secondary accent: the gradient on the Gandar logo mark, and the darker end of accent gradients. |
| `border` | Card outlines, dividers, inactive slider tracks, unchecked switch tracks. |

A theme that gets `backgroundPrimary`, `surface`, `textPrimary` and `accent`
right will already look deliberate; the other five refine it.

### `radius` — optional

| Key | Default | Used for |
| --- | --- | --- |
| `sm` | `6` | Artwork thumbnails, chips, scrollbars, tooltips. |
| `md` | `12` | Cards, list tiles, buttons, input fields, the mini player. |
| `lg` | `20` | Dialogs, bottom sheets, the now-playing artwork. |

Set all three to `0` for a hard-edged, square interface, or to `20 / 28 / 36`
for a very soft one.

### Unknown keys

Anything Gandar does not recognise is ignored. That means a typo in a key name
fails **silently** — the theme imports successfully and simply does not apply
that colour. If a value does not seem to take effect, check the spelling
against the tables above.

---

## 4. Colour formats

Every colour accepts any of these:

| Form | Example | Notes |
| --- | --- | --- |
| 6-digit hex | `"#1DB954"` | Assumed fully opaque. **The form to prefer.** |
| 8-digit hex | `"#FF1DB954"` | First two digits are alpha. |
| Bare hex | `"1DB954"` | The `#` is optional. |
| `0x` prefix | `"0xFF1DB954"` | |
| Integer | `0xFF1DB954` | Only valid in JSON, not YAML. |

Quotes are recommended. In YAML a bare `#1DB954` would be read as a **comment** —
`accent: #1DB954` silently becomes `null`, which fails validation. Always quote
hex colours.

---

## 5. Validation and error messages

Gandar validates on import and tells you exactly what is wrong instead of
applying a half-broken theme. These are the rejections:

| Message | Cause | Fix |
| --- | --- | --- |
| `Theme file is empty.` | Nothing but whitespace | Check the file saved correctly |
| `Not valid JSON or YAML: …` | Unparseable | Usually an unquoted hex colour or a stray tab |
| `Theme root must be a mapping/object.` | The file is a list or a scalar | The top level must be key/value pairs |
| `Unknown format "x" (expected "gandar.theme").` | `format` is set to something else | Correct or delete the `format` line |
| `Missing "colors" mapping.` | No `colors:` block (or it was indented wrongly) | Add a `colors:` umbrella key |
| `Missing color(s): a, b.` | One or more of the nine keys is absent or null | Add them; the message names them |
| `Color "x" must be 6 or 8 hex digits, got "…"` | Wrong length, e.g. `#1DB95` | Use 6 or 8 digits |
| `Color "x" is not valid hex: "…"` | Non-hex characters | Use `0-9A-F` only |

Two failure modes are **silent** because they are not errors:

- an unknown extra key is ignored,
- `radius` values are not range-checked, so `md: 400` is accepted and produces
  an extremely round card.

---

## 6. Worked examples

### Dark: amber on near-black

[`examples/themes/midnight_amber.gandar-theme.yaml`](../examples/themes/midnight_amber.gandar-theme.yaml)

A warm, low-contrast dark theme. Note how `surfaceElevated` is clearly lighter
than `surface`, which is what makes the player bar read as a separate layer.

### Light: paper and ink

[`examples/themes/paper_light.gandar-theme.json`](../examples/themes/paper_light.gandar-theme.json)

The same structure with `brightness: light` and dark text on a warm off-white
base. Read §7 before writing your own light theme.

### Dark: deep forest

[`examples/themes/forest_deep.gandar-theme.yaml`](../examples/themes/forest_deep.gandar-theme.yaml)

A saturated green theme showing that `accent` does not have to be a bright
brand colour — a mid-tone accent with a lightened `accentAlt` keeps buttons
legible without glowing.

---

## 7. `brightness` — the one field that changes meaning

`brightness` does not change any colour you wrote. It changes how those colours
are **interpreted**:

1. It selects the Material light or dark `ColorScheme`, which affects system
   chrome (scrollbars, text selection, the caret, modal barriers).
2. It decides which way the **legibility guard** adjusts your accent.
   `accent` is used for text in a few places. If a dark theme's accent is
   almost black, or a light theme's accent is almost white, Gandar nudges the
   accent toward a readable luminance. On a dark theme it *lightens*; on a light
   theme it *darkens*. If your accent looks slightly different from the hex you
   wrote, this is why.

So: on a light theme, `backgroundPrimary`/`surface` must be **light** and
`textPrimary` **dark** — the opposite of the dark themes above. Everything else
is the same. A light theme is the quickest way to produce an unreadable result,
so use the paper example as a starting point rather than inverting a dark one
by eye.

---

## 8. Importing and exporting

**Import** — **Settings → Themes → Import**. The picker accepts `json`, `yaml`
and `yml`. On success the theme is applied instantly and persisted; on failure
an inline message explains what was wrong.

**Export** — **Settings → Themes → Export** writes the currently active theme as
pretty-printed JSON. If you dismiss the save dialog, Gandar also writes a copy
into the app documents folder so the theme is never lost. Exported files are
valid imports, so export → edit → import is a supported workflow.

**Update a theme** by importing a file with the same `id`; it replaces the
existing one. Importing a file with a **new** `id` adds it alongside.

**Remove** a custom theme with the trash icon on its row. The built-in themes
cannot be deleted.

**Tweak without a file** — use **Customize active theme** to pick an accent
swatch or drag the radius slider. This saves a *derived* theme with the id
`<original>_custom`, so the original is left untouched. Export it if you want to
keep the result as a file.

---

## 9. Checklist before you import

- [ ] Every hex value is **quoted**.
- [ ] All nine colour keys are present, spelled exactly as in §3.
- [ ] `surfaceElevated` is visibly a different layer from `surface` — lighter on a
      dark theme, subtly tinted or a touch darker on a light theme. This is what
      creates depth.
- [ ] `accent` has enough contrast against `surface` to be seen as a button.
- [ ] `textPrimary` and `textSecondary` are distinguishable from each other.
- [ ] `id` is lowercase with underscores and does not collide with a built-in
      (`spotify_classic`, `earthy_brown`) — a collision replaces that theme.
- [ ] For a light theme, read §7 first.

## 10. Sharing a theme

A theme is a single small text file with no references to anything outside
itself, so sharing is just sending the file. Export it, rename it to something
identifiable (the export uses `<id>.gandar-theme.json`), and include a
screenshot — the picker shows only the `name` and a row of colour swatches.

## 11. See also

| Topic | Document |
| --- | --- |
| How tokens become a Material theme | [theming-internals.md](theming-internals.md) |
| Adding a theme shipped *inside* the app | [theming-internals.md §7](theming-internals.md) |
| Building and running the app | [building.md](building.md) |
| Where the codec lives | [`lib/core/theme/theme_codec.dart`](../lib/core/theme/theme_codec.dart) |
