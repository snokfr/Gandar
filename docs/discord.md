# Discord Rich Presence — what you do, and what Gandar does

This document is the setup half of Discord Rich Presence. The app half is
built — Settings → **Discord** holds the Application ID and the toggles, and
`lib/data/discord/` holds the client — but the part below cannot be done from
inside Gandar, because it happens on Discord's website.

## First: what "register an application" even means

Nothing is installed. No code is uploaded. No account is created. Discord's
**Developer Portal** is a form that lets you *name a thing*, and it hands that
name a long number called an **Application ID**.

Discord needs this because of who draws what: Discord draws the activity, on
Discord's servers, next to your username. So Discord has to know which name to
print and which little picture belongs beside it. Registering is how you tell
it. Gandar never talks to the portal; it only tells the Discord client on your
machine "show this activity as application *1558961358882607236*", and Discord
looks up the rest.

That is the whole concept. It is five minutes of filling in a web form, and it
is the only part Gandar cannot do for you.

---

## Where each piece goes

There are exactly two things to move, and **they go to different places**.
This is the bit that is easiest to get backwards:

| What | Where it goes | Why |
| --- | --- | --- |
| The three PNGs in [`assets/discord/`](../assets/discord/) | **Uploaded to Discord**, on your application's art page | Discord serves the picture. Gandar only ever sends the *name* of it |
| The **Application ID** | **Pasted into Gandar**: Settings → Discord | Gandar sends it in the local handshake, so Discord knows whose artwork to use |

The PNG files do **not** go into the Gandar folder, and nothing about the art is
compiled in. `lib/data/discord/discord_presence.dart` refers to `gandar`,
`playing` and `paused` as plain strings; Discord resolves those names on its
own side. That is why the presence starts working the moment you paste the ID,
and the picture shows up a minute or two after the art is uploaded.

---

## What you get, once it is wired up

Your Discord profile shows:

- **Gandar** as the activity, with the artwork you upload below.
- The **track and artist** you are playing, refreshed as it changes.
- A **live timer** counting from the moment the track started.
- **Time in Gandar** — the hours this app has been open — as a second line,
  which is why a session/lifetime counter is part of the work.

---

## Step 1 — register the application

1. Open <https://discord.com/developers/applications> in a browser, signed in as
   yourself.
2. Click **New Application**.
3. Type `Gandar` as the name and accept the terms, then **Create**. If the name
   is already taken by somebody else, use any other name — it is a label that
   appears on your profile, not a username and not unique to you.
4. You are now on the application's **General Information** page. Under
   **Application ID**, click **Copy**. It is a long number, something like
   `1558961358882607236`.
5. Open Gandar → **Settings → Discord**, paste it into the **Application ID**
   field, click **Save**, then turn on **Show what I am playing**.

The chip beside the word *Discord* should move from **No ID** to **Connecting**
and settle on **Connected**. The presence is now live — with no picture yet.

> Discord's portal renames its menu items every so often. The two things that
> actually matter are unchanged: the **Application ID** on General Information,
> and the **asset names** below.

The Application ID is **public**. It is not a secret, it is not a token, and no
client secret is involved: Rich Presence talks to the Discord client on your own
machine over a local socket, and that connection authenticates with nothing but
this id. It is safe in a settings field and safe to commit.

## Step 2 — add the artwork (optional, but it is the picture)

1. Still in the portal with your application selected, open **Rich Presence →
   Art Assets** in the left sidebar.
2. Upload these three files from this repository:

| Upload this file | Asset name must be | It appears as |
| --- | --- | --- |
| [`assets/discord/gandar.png`](../assets/discord/gandar.png) | `gandar` | the large image beside the activity |
| [`assets/discord/playing.png`](../assets/discord/playing.png) | `playing` | the small badge while playing |
| [`assets/discord/paused.png`](../assets/discord/paused.png) | `paused` | the small badge while paused |

3. Give Discord a minute. Art is cached on their side, and a presence set just
   before an upload can keep showing nothing for a short while.

Discord names an asset after the file it came from, minus the extension — which
is why the files are already named `gandar.png`, `playing.png` and `paused.png`.
If your upload dialog offers a separate name field, use the same three names. If
it offers to replace an existing asset, that is the same thing as renaming: the
name is the contract, not the image.

To see exactly what you are uploading before you upload it — and at the size
Discord actually draws the badges — open the proof sheet, which inlines the
images so it works from anywhere:

```bash
python tool/generate_icon.py --discord-assets assets/discord \
  --proof build/icon-proof.html
```

Until the art exists, Discord accepts the presence and **silently drops the
image keys** — the activity still appears, with no picture. That is what a real
round-trip looked like before they were uploaded:

```json
{"cmd":"SET_ACTIVITY","data":{"details":"Posed 2","state":"sxprano",
 "assets":{"large_text":"Topic","small_text":"12 h 30 m in Gandar"},
 "name":"Gandar","application_id":"…"}}
```

`large_image` and `small_image` are absent from the echo because there was
nothing on Discord's side to resolve those names to. See
[The Discord profile line](#the-discord-profile-line) for what each slot shows.

### 3. Keep the Discord desktop app running

Rich Presence only works while the Discord **desktop client** is open and
signed in. On Windows it listens on a local named pipe
(`\\.\pipe\discord-ipc-0`), and a closed client simply means no presence —
Gandar should say that in the log and carry on, never fail because of it.

---

## What the app does with it

Everything below is in the build; this section is what it does, so behaviour can
be checked against it rather than guessed from.

1. **Settings → Discord** holds the Application ID and two toggles: *Show what I
   am playing* and *Show the song and artist*. The id lives in settings rather
   than in the source, so anybody can point Gandar at their own application
   without a rebuild.
2. The client connects to the local pipe, handshakes with
   `{"v":1,"client_id":"…"}`, and pushes activity frames as playback changes.
   It is written against `dart:ffi` rather than `dart:io`, for a reason worth
   recording: **`dart:io` cannot open a Windows named pipe.** `File.open` maps
   to `CreateFileW` with `OPEN_ALWAYS`, which a pipe rejects with
   `ERROR_GEN_FAILURE` (31), and no `FileMode` grants read *and* write on one
   handle. `lib/data/discord/discord_ipc.dart` therefore calls `CreateFileW`
   itself with `OPEN_EXISTING | GENERIC_READ | GENERIC_WRITE`.
3. Discord serves a small pool of pipe instances, so a client arriving when they
   are all taken gets `ERROR_PIPE_BUSY` rather than a connection. The documented
   answer is `WaitNamedPipe`, which the client does before retrying — without it
   the first connection fails on a machine where another Rich Presence app holds
   the instance.
4. **Time in Gandar** is counted from launch, including time with nothing
   playing, and persisted once a minute. It appears in the Discord profile line
   and in the app: the Discord card shows the session and the lifetime total,
   and the Savings card carries a *Time in Gandar* figure with the rest of the
   play statistics.
5. It fails soft in every direction: no Discord, no presence, no error dialog,
   just a status chip that says *Off*, *No ID*, *Connecting*, *Connected* or
   *Not connected*, with a sentence explaining the last of those. Retries back
   off from five seconds to five minutes so a machine without Discord does not
   spin.

## The Discord profile line

Discord gives an activity four places to put text, and all four are used:

| Slot | What Gandar puts there |
| --- | --- |
| `details` | the song title |
| `state` | the artists |
| `assets.large_text` | the album, or `Gandar` when there is none |
| `assets.small_text` | time spent in Gandar, once it is at least a minute |

The progress timer is anchored to when the track started, so Discord's own
countdown matches the player without further traffic. It is deliberately omitted
while paused: Discord keeps counting on its own, and a paused track with a
running timer is a lie.

## Verifying it

There is a live test that talks to the real client:

```bash
flutter test --dart-define=LIVE=true \
  --dart-define=DISCORD_CLIENT_ID=1558961358882607236 \
  test/live/discord_live_test.dart
```

It connects, sets a playing activity, sets a paused one, clears the presence and
reports every frame Discord sent back. It is skipped by default because it needs
Discord open and signed in — and note that **a Discord client showing an error
screen still accepts connections and then never answers the handshake**, which
is the failure this test was built to tell apart from a protocol bug.

## Checked against Discord's own documentation

This client is written to the published protocol rather than to remembered
tribal knowledge, so here is what was read and what it says, point by point.
Sources: [Discord RPC](https://docs.discord.com/developers/topics/rpc),
[Rich Presence](https://docs.discord.com/developers/platform/rich-presence),
and Discord's own implementation notes,
[discord-rpc: hard mode](https://github.com/discord/discord-rpc/blob/master/documentation/hard-mode.md).

| What the docs say | What Gandar does |
| --- | --- |
| The pipe is `\\?\pipe\discord-ipc-{n}`, and *n* runs **0 to 9** — "Discord can be on any pipe ranging from discord-ipc-0 to discord-ipc-9" | `discordPipeCandidates()` tries exactly `0…9` on Windows, in order, and takes the first that opens |
| The header is **two little-endian unsigned 32-bit integers**: the opcode, then the payload length in **bytes** | `encodeDiscordFrame` writes opcode and `body.length` with `Endian.little`, over UTF-8 bytes |
| "The pipe expects for frames to be written in a single byte array" | One `write` of the header and payload together |
| A session begins with a **HANDSHAKE (opcode 0)** carrying the RPC version and the application's client id | `{'v': 1, 'client_id': clientId}` |
| Discord answers the handshake with a **FRAME (opcode 1)** containing `READY` | The handshake future completes on the `READY` event, and times out with a sentence rather than hanging |
| Commands and events travel as **FRAME** payloads, with a `nonce` used to match a reply to its request | `send()` puts a nonce on the command and completes the waiting future when that nonce comes back |
| PING (3) must be answered, and CLOSE (2) means the session is over | Both handled in `_dispatch` |

### The one thing the documentation does not settle

The pipe being refused with **Win32 error 5** is an integrity-level problem, not
an account problem: two programs from the same user cannot talk through a named
pipe when one is elevated and the other is not. Microsoft documents the general
rule — access to both ends of a named pipe is decided by the pipe's security
descriptor and the caller's token
([Named Pipe Security and Access Rights](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights))
— but Discord does not publish the descriptor its client creates, and the
"both must match" behaviour is reported by users rather than guaranteed in any
Discord document.

So Gandar measures **its own** elevation (`isRunningElevated()`, via
`TokenElevation`) and reports only that. It cannot read Discord's, and the
message says so instead of asserting which side is high. The remedy it names is
the one that is in this app's control: **start Gandar normally** — or, if you
want both elevated, start Discord as administrator as well and restart Gandar
so the two match.
