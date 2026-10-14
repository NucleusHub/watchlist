import mongoose from 'mongoose'

const openDefaultSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      enum: ['tmdb', 'csfd', 'google', 'custom'],
      default: 'tmdb',
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

const watchlistSettingsSchema = new mongoose.Schema(
  {
    profileId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Profile',
      required: true,
      unique: true,
      index: true,
    },
    openDefaults: {
      movie: { type: openDefaultSchema, default: () => ({}) },
      show: { type: openDefaultSchema, default: () => ({}) },
    },
    // Free strings, not an enum: the client ignores unknown source ids.
    searchSources: { type: [String], default: ['tmdb'] },
    // Used by clients that call TMDb directly (iOS, web); the web falls back to its build-time key.
    tmdbApiKey: { type: String, default: '' },
    accent: {
      type: new mongoose.Schema(
        { id: { type: String, required: true }, custom: { type: String, default: null }, updatedAt: { type: Date, default: Date.now } },
        { _id: false }
      ),
      default: null,
    },
    // Plugin id -> 'tab' | 'panel' | 'hidden'; free strings so stale keys are harmless.
    pluginPlacements: { type: Map, of: String, default: () => ({}) },
    // { enabled, entries: {key: entry}, notInterested: {key: {name, genres, at}} }, stored as the clients send it.
    movieDNA: { type: mongoose.Schema.Types.Mixed, default: null },
  },
  { timestamps: true }
)

export default mongoose.model('WatchlistSettings', watchlistSettingsSchema)
