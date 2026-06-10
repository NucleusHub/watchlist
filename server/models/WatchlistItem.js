import mongoose from 'mongoose'

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
    dateAdded: { type: Date, default: Date.now },
    notes: { type: String, trim: true, default: '' },
  },
  { timestamps: true }
)

export default mongoose.model('WatchlistItem', watchlistItemSchema)
