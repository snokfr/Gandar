# Discord Rich Presence — what you do, and what Gandar does

This document is the setup half of Discord Rich Presence. It is written as a
checklist because **none of it can be done from inside Gandar**: it needs an
application registered on the Discord Developer Portal, which only you can
create.

Nothing here is implemented in the app yet. The steps below are what has to
exist before the wiring can be written.

---

## What you get, once it is wired up

Your Discord profile shows:

- **Gandar** as the activity, with the artwork you upload below.
- The **track and artist** you are playing, refreshed as it changes.
- A **live timer** counting from the moment the track started.
- **Time in Gandar** — the hours this app has been open — as a second line,
  which is why a session/lifetime counter is part of the work.

---

## What you need to do

### 1. Create the Discord application

1. Go to <https://discord.com/developers/applications>.
2. **New Application**, and name it `Gandar`. The name is what people see next
   to the activity, so it is worth getting right.
3. On the **General Information** page, copy the **Application ID** (a long
   number). That is the only value Gandar needs.

The Application ID is **public**. It is not a secret, it is not a token, and
there is no client secret involved: Rich Presence talks to the Discord client
already running on your machine over a local socket, and that connection
authenticates with nothing but this id. So it is safe to send it to me, safe to
put in a settings field, and safe to commit.

### 2. Add artwork (optional, but it is what makes it look right)

On the same application, open **Rich Presence → Art Assets** and upload:

| Asset name | What it is | Where it shows |
| --- | --- | --- |
| `gandar` | The app logo, 512×512 PNG | The large image next to the activity |
| `playing` | A play symbol | Small badge while playing |
| `paused` | A pause symbol | Small badge while paused |

The **asset names** are what the code refers to, so they must match exactly
(`gandar`, not `Gandar.png`). Uploading a replacement later under the same name
takes effect on its own after a short cache delay.

### 3. Keep the Discord desktop app running

Rich Presence only works while the Discord **desktop client** is open and
signed in. On Windows it listens on a local named pipe
(`\\.\pipe\discord-ipc-0`), and a closed client simply means no presence —
Gandar should say that in the log and carry on, never fail because of it.

---

## What I will do once you have the Application ID

1. Add a **Discord** section to Settings with the Application ID, a
   **Show what I am playing** toggle, and a **Show time in Gandar** toggle.
   The id goes in settings rather than the source, so anybody can point Gandar
   at their own Discord application without a rebuild.
2. Implement the IPC client in Dart: connect to the local pipe, handshake with
   `{"v":1,"client_id":"…"}`, then push activity frames. No new dependency
   unless one proves better than a direct implementation.
3. Track **time in Gandar**: the current session and the lifetime total, the
   latter persisted alongside the play history. This feeds both the Discord
   state line and a new activity statistic in the app.
4. Fail soft in every direction: no Discord, no presence, no error dialog. The
   log records why, nothing else changes.

### What to send me

Just the **Application ID**, plus a note if you uploaded the art assets and
used different names for them.
