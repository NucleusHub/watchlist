import mongoose from 'mongoose'

const seasonProgressSchema = new mongoose.Schema(
  {
    seasonNumber: { type: Number, required: true },
    name: { type: String, default: '' },
    episodeCount: { type: Number, default: 0 },
    watched: { type: Number, default: 0, min: 0 },
  },
  { _id: false }
)

const openTargetSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      enum: ['tmdb', 'csfd', 'google', 'custom'],
      required: true,
    },
    customUrl: { type: String, default: '' },
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
    genres: { type: [String], default: [] },
    favorite: { type: Boolean, default: false },
    year: { type: Number, default: null },
    runtime: { type: Number, default: null },
    seasons: { type: Number, default: null },
    episodes: { type: Number, default: null },
    showRuntime: { type: Number, default: null },
    seasonProgress: { type: [seasonProgressSchema], default: undefined },
    openTarget: { type: openTargetSchema, default: null },
    collectionIds: { type: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Collection' }], default: [], index: true },
    dateAdded: { type: Date, default: Date.now },
    // Null for items completed before this field existed; consumers fall back to updatedAt.
    completedAt: { type: Date, default: null },
    notes: { type: String, trim: true, default: '' },
  },
  { timestamps: true }
)

export default mongoose.model('WatchlistItem', watchlistItemSchema)
