import mongoose from 'mongoose'

// Per-season watch progress for shows. `episodeCount` is the season's total
// (from TMDb); `watched` is how many of those the user has finished.
const seasonProgressSchema = new mongoose.Schema(
  {
    seasonNumber: { type: Number, required: true },
    name: { type: String, default: '' },
    episodeCount: { type: Number, default: 0 },
    watched: { type: Number, default: 0, min: 0 },
  },
  { _id: false }
)

// Where this item opens when its poster is clicked. When unset (null), the
// app falls back to the per-type global default kept in the browser. `custom`
// uses `customUrl` with {title}/{year} placeholders.
const openTargetSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      enum: ['tmdb', 'csfd', 'google', 'custom'],
      required: true,
    },
    customUrl: { type: String, default: '' },
    // Shape of the {title} placeholder inside customUrl.
    titleFormat: {
      type: String,
      enum: ['raw', 'lower', 'kebab', 'snake', 'pascal', 'camel'],
      default: 'raw',
    },
  },
  { _id: false }
)

const watchlistItemSchema = new mongoose.Schema(
  {
    profileId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', index: true },
    title: { type: String, required: true, trim: true },
    type: { type: String, enum: ['movie', 'show'], required: true },
    // TMDb id of the chosen search result, when the item was added via TMDb.
    // Persisted so cross-user features (e.g. the In Common plugin) can match the
    // exact same title precisely rather than by fuzzy title. Null for manually
    // entered items or ones added from a non-TMDb source.
    tmdbId: { type: Number, default: null, index: true },
    status: {
      type: String,
      enum: ['planned', 'watching', 'completed'],
      default: 'planned',
    },
    posterUrl: { type: String, default: null },
    tmdbRating: { type: Number, default: null },
    watchLink: { type: String, default: null },
    streamingProvider: { type: String, default: null },
    streamingLogo: { type: String, default: null },
    rating: { type: Number, min: 0.5, max: 10, default: null },
    favorite: { type: Boolean, default: false },
    year: { type: Number, default: null },
    runtime: { type: Number, default: null },
    seasons: { type: Number, default: null },
    episodes: { type: Number, default: null },
    showRuntime: { type: Number, default: null },
    seasonProgress: { type: [seasonProgressSchema], default: undefined },
    openTarget: { type: openTargetSchema, default: null },
    // Collections this item belongs to (many-to-many; see models/Collection.js).
    // Membership lives here so assigning/removing reuses the normal item PATCH
    // and deleting a collection only $pulls its id — it never removes the item.
    collectionIds: { type: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Collection' }], default: [], index: true },
    dateAdded: { type: Date, default: Date.now },
    notes: { type: String, trim: true, default: '' },
  },
  { timestamps: true }
)

export default mongoose.model('WatchlistItem', watchlistItemSchema)
