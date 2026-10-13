# CoffitivityLocal — Design Spec

- **Date:** 2026-10-13
- **Status:** Approved (design); pending implementation plan
- **Author:** apps@joystudios.xyz (with Claude Code)

## Overview

A tiny native macOS **menu-bar app** that plays the 9 free ambience tracks from
Coffitivity's free library (<https://coffitivity.com/library/free>). Click the
menu-bar icon, pick a sound, and it loops as background ambience. A sound is
downloaded and cached to disk the first time it is played; every play after
that works fully offline.

The app is deliberately minimal: native Swift + AppKit + AVFoundation, no
third-party dependencies, no Dock icon, no window.

## Goals

- Play any of the 9 free Coffitivity sounds from the macOS menu bar.
- Loop the selected sound continuously until stopped.
- Work offline for any track that has been played at least once (cache-on-first-play).
- Independent volume control, persisted across launches.
- Be lightweight: a small self-contained `.app`, no runtime beyond macOS itself.

## Non-goals (YAGNI)

Explicitly out of scope for this version:

- Mixing / playing multiple sounds at once (Coffitivity's premium feature).
- Premium or account-gated sounds; any login or network API beyond fetching the mp3 files.
- Equalizer, fades, timers, sleep mode.
- Launch-at-login, auto-resume of the last sound on launch.
- "Download all upfront" — caching is lazy, per track, on first play.

These are easy to add later; they are left out to keep the first version small.

## The sounds (concrete data)

The free library is served as direct `.mp3` files on `audios.coffitivity.com`
(verified: HTTP range requests supported, `audio/mpeg`). The list is hardcoded
in the app — there is no runtime catalog API.

Each sound has a **display name** and an **id** equal to the mp3 file stem. The
id is used both to build the URL (`https://audios.coffitivity.com/<id>.mp3`) and
as the on-disk cache filename (`<id>.mp3`).

| Display name          | id (file stem)         | Size    |
|-----------------------|------------------------|---------|
| Morning Murmur        | morning-murmur         | 33.3 MB |
| Lunchtime Lounge      | lunchtime-lounge       | 30.2 MB |
| University Undertones | university-undertones  | 20.8 MB |
| Sunny Day Café        | tuesday-at-tarihi      | 10.9 MB |
| Bird Songs            | bird-songs             | 6.2 MB  |
| Heavy Wind            | heavy-wind             | 5.3 MB  |
| Creek                 | creek                  | 5.0 MB  |
| Blue Noise            | blue-noise             | 0.7 MB  |
| White Noise           | white-noise            | 0.3 MB  |

Note: "Sunny Day Café" has an id (`tuesday-at-tarihi`) that differs from its
display name; using the file stem as the id avoids any slug/filename mismatch.

## Architecture

Menu-bar-only app:

- `NSApplication` activation policy `.accessory` + `LSUIElement` in `Info.plist`
  → no Dock icon, no main window.
- An `NSStatusItem` shows a coffee-cup icon via the SF Symbol
  `cup.and.saucer.fill` (so there are **no image assets** to ship).
- Clicking the status item opens an `NSMenu`: the 9 sounds, a separator, a
  volume slider, a separator, and Quit.
- Playback uses `AVAudioPlayer` on a **local cached file** with
  `numberOfLoops = -1` for a seamless infinite loop.

## Components

Each is a small, single-purpose Swift file with a clear interface.

### `Sound.swift`
- `struct Sound { let name: String; let id: String; var url: URL }`
  where `url` = `https://audios.coffitivity.com/<id>.mp3`.
- `static let all: [Sound]` — the 9 free sounds from the table above, in that order.
- This is the single place the Coffitivity URLs live.

### `AudioCache.swift`
Owns `~/Library/Application Support/CoffitivityLocal/`.
- `cacheDir: URL` — created on first use.
- `localURL(for: Sound) -> URL` → `<cacheDir>/<id>.mp3`.
- `isCached(_ sound: Sound) -> Bool`.
- `download(_ sound: Sound, completion: (Result<URL, Error>) -> Void)` —
  `URLSession` download to a temp file, then **atomically move** it to
  `localURL` only on success, so the cache never contains a partial file.
  Completion is delivered on the main queue.

### `Player.swift`
Thin wrapper over a single `AVAudioPlayer`.
- `play(localURL: URL, volume: Float)` — loads, sets `numberOfLoops = -1`,
  sets volume, plays.
- `stop()`.
- `setVolume(_ v: Float)` — live.
- `nowPlaying: String?` — id of the currently playing sound, or `nil`.

### `StatusItemController.swift`
Builds and owns the menu and wires everything together.
- Builds `NSStatusItem` and the `NSMenu`.
- Each sound is an `NSMenuItem`; shows a ✓ (`.on` state) on the playing track
  and a "downloading…" affordance (disabled + title suffix) on an in-flight one.
- Click handling:
  - clicking the playing sound → `Player.stop()`;
  - clicking another sound → if cached, play immediately; else mark
    "downloading…", call `AudioCache.download`, then play on success or show an
    error alert on failure.
- Hosts an `NSSlider` in a custom menu-item view for volume; forwards changes to
  `Player.setVolume` and persists to `UserDefaults` (`volume`, default e.g. 0.7).
- Quit item.

### `AppDelegate.swift` / `main.swift`
- Bootstrap: set `.accessory` activation policy, create the `StatusItemController`.

## Data flow

1. User clicks the menu-bar icon → menu opens with current state (✓ on playing track, slider at saved volume).
2. User clicks a sound:
   - **Playing track** → stop, clear ✓.
   - **Cached track** → `Player.play(localURL, volume)`, set ✓.
   - **Uncached track** → item shows "downloading…"; `AudioCache.download` runs;
     on success → play + ✓; on failure → revert item + error alert.
3. Volume slider → `Player.setVolume` live + persist to `UserDefaults`.

After a track's first successful play it is on disk, so all later plays need no network.

## Error handling

- **First-play download failure** (offline, 4xx/5xx, interrupted): `NSAlert`
  "Couldn't download *<name>* — check your connection." Item reverts to idle;
  nothing is cached; a later click retries cleanly (atomic move guarantees no
  partial file is left behind).
- **Playback failure**: guarded; logged; no crash.
- **Cache directory creation failure**: surfaced via the same alert path on the
  first operation that needs it.

## Build & packaging

No Xcode project file. Lightweight and transparent:

- **`Package.swift`** — Swift Package with:
  - one **executable target** (`CoffitivityLocal`) — the app sources;
  - one **test target** (`CoffitivityLocalTests`) — pure-logic unit tests.
- **`make-app.sh`** (~15 lines) — `swift build -c release`, then assemble
  `CoffitivityLocal.app/Contents/{MacOS/CoffitivityLocal, Info.plist}`. The
  `Info.plist` sets `LSUIElement = true`, bundle id, display name, and bundle
  version. Output is a small self-contained `.app` droppable into `/Applications`.
- **`README.md`** — how to build (`./make-app.sh`), where the app lands, and how
  to run it.

No third-party dependencies.

## Testing strategy

TDD the pure, deterministic logic via `swift test`:

- **`Sound`**: exactly 9 sounds; all ids unique; every `url` is
  `https://audios.coffitivity.com/<id>.mp3`; names non-empty.
- **`AudioCache`**: `localURL(for:)` maps id → `<cacheDir>/<id>.mp3`;
  `isCached` is false then true around a file being placed; the temp→cache move
  is atomic (no partial file on simulated failure). Use a temp cache directory
  injected into `AudioCache` so tests never touch the real Application Support dir.

The AppKit menu and `AVAudioPlayer` are verified by a **manual smoke test**
(launch, play a sound, confirm it loops, adjust volume, quit and relaunch to
confirm persisted volume, disable network and confirm a cached track still
plays) — UI/audio TDD here would be ceremony against YAGNI.

## File layout

```
coffitivity-local/
  Package.swift
  make-app.sh
  README.md
  Sources/CoffitivityLocal/
    main.swift
    AppDelegate.swift
    Sound.swift
    AudioCache.swift
    Player.swift
    StatusItemController.swift
  Tests/CoffitivityLocalTests/
    SoundTests.swift
    AudioCacheTests.swift
  docs/superpowers/specs/
    2026-10-13-coffitivity-menu-bar-design.md
```

To make `AudioCache` testable, its cache directory is injectable (defaults to
Application Support; tests pass a temp dir).
