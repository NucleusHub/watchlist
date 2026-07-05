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

const watchlistItemSchema = new mongoose.Schema(
  {
    profileId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', index: true },
    title: { type: String, required: true, trim: true },
    type: { type: String, enum: ['movie', 'show'], required: true },
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
    rating: { type: Number, min: 1, max: 10, default: null },
    year: { type: Number, default: null },
    runtime: { type: Number, default: null },
    seasons: { type: Number, default: null },
    episodes: { type: Number, default: null },
    showRuntime: { type: Number, default: null },
    seasonProgress: { type: [seasonProgressSchema], default: undefined },
    dateAdded: { type: Date, default: Date.now },
    notes: { type: String, trim: true, default: '' },
  },
  { timestamps: true }
)

export default mongoose.model('WatchlistItem', watchlistItemSchema)
