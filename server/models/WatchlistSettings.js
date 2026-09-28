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
    searchSources: { type: [String], default: ['tmdb'] },
    pluginPlacements: { type: Map, of: String, default: () => ({}) },
    tmdbApiKey: { type: String, default: '', maxlength: 256 },
  },
  { timestamps: true }
)

export default mongoose.model('WatchlistSettings', watchlistSettingsSchema)
