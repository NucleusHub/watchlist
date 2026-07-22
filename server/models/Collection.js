import mongoose from 'mongoose'

// A user-defined grouping of watchlist items ("Marvel", "Rewatch", "With Dad").
// Membership itself lives on the item (WatchlistItem.collectionIds) so an item
// can belong to many collections and deleting a collection only detaches it —
// it never touches the items. The item count is derived (never stored) from
// that membership, so it can't drift.
//
// The schema is intentionally wider than the current UI: the fields below are
// stored but not yet surfaced, so the eventual cover-image / nesting / smart /
// manual-ordering features slot in without a migration.
const collectionSchema = new mongoose.Schema(
  {
    profileId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', required: true, index: true },
    name: { type: String, required: true, trim: true },
    description: { type: String, trim: true, default: '' },

    // Cover image (upload/URL), same convention as WatchlistItem.posterUrl.
    coverUrl: { type: String, default: null },
    // Items whose posters form the cover when no coverUrl is set (a "slash"
    // collage of their posters). Empty ⇒ fall back to an auto preview.
    coverItemIds: { type: [mongoose.Schema.Types.ObjectId], ref: 'WatchlistItem', default: [] },
    // How many posters the auto cover shows (1–8) when no image/titles are set.
    coverCount: { type: Number, default: 4, min: 1, max: 8 },

    // ── Forward-compatible fields (persisted, not yet surfaced in the UI) ──────
    // Nested collections: parent folder, null at the top level.
    parentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Collection', default: null, index: true },
    // 'manual' = membership set by the user; 'smart' = derived from `filter`.
    kind: { type: String, enum: ['manual', 'smart'], default: 'manual' },
    // Query for smart (dynamic) collections, e.g. { type: 'movie', favorite: true }.
    filter: { type: mongoose.Schema.Types.Mixed, default: null },
    // Explicit member order for manual sorting; undefined ⇒ fall back to a query sort.
    itemOrder: { type: [mongoose.Schema.Types.ObjectId], default: undefined },
    // Order among sibling collections (for manual collection sorting later).
    position: { type: Number, default: 0 },
  },
  { timestamps: true }
)

export default mongoose.model('Collection', collectionSchema)
