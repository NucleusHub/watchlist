# Watchlist API for the iOS app

Base: `https://<host>/api/watchlist` (JSON). The web Watchlist's Mongo data is the primary store; iOS reads and writes it here.

## Auth
- `Authorization: Bearer <NucleusID access token>`; client_id `watchlist`, scope `data`. The account is the token's profile; every route is scoped to it.
- `401` missing/invalid/expired token (refresh and retry). `403` token valid but wrong client or scope, or the app is disabled for the account (`requireAppEnabled`). Error bodies: `{ "error": "msg" }` (or `{ "error": { code, message } }` from core). `404` unknown id, `400` validation failure.
- Cross-app `/api/v1/{app-data,files,views,apps,commands}` is also served (`appDataRouter`); iOS keeps publishing the `library` view and handling `markWatched`/`unmarkWatched` commands through it.

## Endpoints
| Method, path | Body | Response |
|---|---|---|
| GET `/` (`?status=&type=&collection=`) | | `[Item]` newest first |
| POST `/` | Item fields (title, type required) | `201 Item`; `completedAt` set if status is completed. A valid `_id` in the body is kept. |
| PATCH `/:id` | partial Item | `Item`. `completedAt` is server-derived from status changes. |
| DELETE `/:id` | | `{message}` |
| GET `/collections` | | `[Collection]` + `itemCount`, `previewPosters`, `coverPosters` (read-only extras) |
| POST `/collections` | `name` (required), `description`, `coverUrl`, `coverItemIds`, `coverCount` (1-8) | `201 Collection` |
| PATCH `/collections/:id` | same fields, partial | `Collection` |
| PUT `/collections/:id/order` | `{ itemIds: [] }` | `Collection` (sets `itemOrder`) |
| POST `/collections/:id/items` | `{ itemIds: [] }` | `{ items, modified }` (adds membership) |
| DELETE `/collections/:id` | | `{message}`; removes it from items |
| GET / PUT `/settings` | PUT: `movie`, `show` (OpenTarget), `searchSources`, `pluginPlacements`, `tmdbApiKey`, `accent`, `movieDNA` (all optional) | `{ openDefaults:{movie,show}, searchSources, pluginPlacements, tmdbApiKey, accent, movieDNA }` |

Item membership is stored on the item (`collectionIds`); change it with PATCH `collectionIds` or the collection `/items` call.

## Item fields
`_id, title, type (movie|show), tmdbId, status (planned|watching|completed), posterUrl, tmdbRating, watchLink, streamingProvider, streamingLogo, rating (0.5-10), genres[] (max 12), favorite, year, runtime, seasons, episodes, showRuntime, seasonProgress[{seasonNumber,name,episodeCount,watched}], openTarget{type tmdb|csfd|google|custom, customUrl, titleFormat raw|lower|kebab|snake|pascal|camel}|null, collectionIds[], dateAdded, completedAt, notes, createdAt, updatedAt`
iOS-origin (new, all nullable): `overview, trailerUrl, customCredits[{name, role, cast(bool), personId, photo}], source, lastPage, lastWatchedAt (ISO date), playback{url, position, duration>0}|null`.
Collection: `_id, name, description, coverUrl, coverItemIds[], coverCount, parentId, kind (manual|smart), filter, itemOrder[], position, createdAt, updatedAt`.
Settings `accent`: `{ id, custom?, updatedAt }`. `tmdbApiKey` is returned to the owner only; the web client ignores it.
Settings `movieDNA` (null until first set; PUT replaces it whole, `null` clears it): `{ enabled (default true), entries: { <key>: { kind genre|title|person, name, strength? (-100..100), hidden?, boosts?[ISO], genres?[], poster?, followed? } }, notInterested: { <key>: { name, genres[], at (ISO) } } }`. Keys: `genre:<lowercased name>`, `movie:<tmdbId>`, `show:<tmdbId>`, `person:<tmdbId>`, `item:<_id>` (untracked titles). Only what the person set is stored; the learned part is computed on each client from the library.

## iOS record <-> API mapping
Field names are identical (iOS stores the web JSON as-is: `raw[...]`), so no renames. Notes:
| iOS | API |
|---|---|
| `_id` | `_id` (24-hex ObjectId string; ids created on iOS must be valid ObjectIds to be accepted on POST, else omit and use the returned id) |
| ISO strings (`createdAt`, `dateAdded`, `lastWatchedAt`, `completedAt`) | same ISO-8601 |
| `details` (WatchCollection) | `description` |
| `WatchlistDocument.deleted` tombstones | not needed: DELETE is authoritative; locally-tombstoned ids -> DELETE |
| `Item.overview` empty -> `.null` | `overview: null` |
| `settings.openDefaults.movie/show` | PUT `/settings` `{movie, show}`, read back as `openDefaults` |
| `settings.movieDNA` | PUT/GET `/settings` `movieDNA`, same shape |

## First sign-in choice
Offer when both device and server hold data. Load server state with GET `/`, GET `/collections`, GET `/settings` and diff by `_id` (compare `updatedAt`).
- **Merge**: newest `updatedAt` wins per `_id`. Server-newer -> take locally. Device-newer -> PATCH. Device-only -> POST (collections first, then items with remapped `collectionIds`). Server-only -> keep.
- **Keep web**: replace local records with the GET results; upload nothing.
- **Keep iOS**: DELETE every server item and collection (list first, delete by id), then POST collections, then items (remap `collectionIds` to returned collection ids), then PUT `/settings`.
- **Cherry-pick**: show the diff; apply only the chosen records with the merge calls above (POST/PATCH for pushes, local write for pulls, DELETE for chosen removals).
- **Start empty**: discard local data, use GET results only (or, to also clear the web, DELETE everything as in Keep iOS without uploading; confirm explicitly).
After any choice, send later edits as single-record POST/PATCH/DELETE; no whole-document upload exists.
