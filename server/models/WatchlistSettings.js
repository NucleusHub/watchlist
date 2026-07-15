import mongoose from 'mongoose'

// One per-user preferences document for the Watchlist app, keyed uniquely by
// profileId and created lazily on first save. Currently holds the per-type
// "open in" defaults that used to live only in the browser's localStorage — so
// they reset every session and never followed the user across devices.
const openDefaultSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      enum: ['tmdb', 'csfd', 'google', 'custom'],
      default: 'tmdb',
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
    // Metadata sources searched by the add/edit search box. 'tmdb' is built in
    // and always searched; plugins (e.g. anime-source) contribute more, opt-in
    // via a toggle in settings. Free strings, not an enum, so an uninstalled or
    // renamed source degrades gracefully (the client ignores unknown ids).
    searchSources: { type: [String], default: ['tmdb'] },
  },
  { timestamps: true }
)

export default mongoose.model('WatchlistSettings', watchlistSettingsSchema)
