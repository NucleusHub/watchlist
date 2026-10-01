# Watchlist for iOS and Apple Watch

The native SwiftUI app (iOS 17+) and its Apple Watch app. Signing in with Nucleus ID syncs the watchlist
between devices; without an account it stays on the phone.

## Build

```sh
brew install xcodegen          # once
xcodegen generate              # after adding or moving files
open Watchlist.xcodeproj
```

Run the **Watchlist** scheme on an iPhone, or **WatchlistWatch** on a watch simulator paired with that iPhone.
The UI uses [NucleusUI](https://github.com/NucleusHub/nucleus-ui), the design system shared with Shell
(for now from `../../../nucleus-ui`, see `project.yml`).

## Layout

| Folder | What's in it |
| --- | --- |
| `Watchlist/Model` | The document, items, collections, settings, and the merge |
| `Watchlist/Store` | The on-device store, backups, Keychain, preferences, and the one-time migration from the Capacitor app |
| `Watchlist/Account` | Nucleus ID sign-in (PKCE) and cloud sync (`/api/v1/app-data/watchlist`) |
| `Watchlist/Services` | TMDb, "Open on" links, watching progress, image helpers |
| `Watchlist/Features` | The screens |
| `Watchlist/Watch` | The phone's side of WatchConnectivity |
| `WatchlistWatch` | The watch app |

## Compatibility with the earlier app

The first version of Watchlist was a Vue app in Capacitor. This app takes over its bundle id, its on-device
data and sign-in (`Store/Migration.swift`) and its sync format, so existing documents keep working.

- Records are kept as their JSON objects, so fields this app doesn't know survive a round trip.
- `WatchlistTests/MergeTests` checks the Swift merge against the original JavaScript one, kept in
  `WatchlistTests/Fixtures/reference-localDb.js`. After changing the merge, run
  `node WatchlistTests/Fixtures/generate.mjs` and the tests.
- Timestamps are written like JavaScript's `toISOString()`; ids are 24 hex characters.

## Translations

English strings are in the Swift code. Czech is in `design/cs.py`; edit it and run `python3 design/cs.py`.

## Debug launch arguments

`-resetAll`, `-sampleData`, `-skipWelcome`, `-appearance light|dark`, `-grid list|big|small`,
`-route settings|stats|item|collection|add|edit|seasons`. `ScreenshotTests` uses them to capture every screen
(set `TEST_RUNNER_SHOT_DIR` to keep the images).
