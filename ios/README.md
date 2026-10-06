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
The UI uses [NucleusUI](https://github.com/NucleusHub/nucleus-native-ui), the design system shared with Shell.
To work on it alongside the app, point `NucleusUI` in `project.yml` at a local checkout with `path:`.

## Plugins

Search sources and the "Jump back in" section are plugins. `NucleusPlugins` (`nucleus-native-plugins`) is the shared
loader, `WatchlistPluginKit` (`../plugin-kit`) is Watchlist's contract (`SearchSource`, `HomeSection`), and the plugins are
`plugins/anime-source` and `plugins/jump-back-in`. All are local packages in `project.yml`. `WatchlistApp` installs plugins; Settings → Plugins switches them, Settings → Search sources
picks which sources the add screen searches.

## Layout

| Folder | What's in it |
| --- | --- |
| `Watchlist/Model` | The document, items, collections, settings, and the merge |
| `Watchlist/Store` | The on-device store, backups, Keychain, preferences, and the one-time migration from the Capacitor app |
| `Watchlist/Account` | Nucleus ID sign-in (PKCE) and cloud sync (`/api/v1/app-data/watchlist`) |
| `Watchlist/Services` | TMDb, search sources (`Sources.swift`), "Open on" links, watching progress, image helpers |
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

`-resetAll`, `-sampleData`, `-sampleJump` (three titles to jump back into), `-skipWelcome`, `-appearance light|dark`, `-grid list|big|small`,
`-animeSource` (search Kitsu too), `-route settings|sources|plugins|stats|item|collection|add|edit|seasons|tour`. `ScreenshotTests` uses them to capture every screen
(set `TEST_RUNNER_SHOT_DIR` to keep the images).
