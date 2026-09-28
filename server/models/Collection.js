import mongoose from 'mongoose'

const collectionSchema = new mongoose.Schema(
  {
    profileId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', required: true, index: true },
    name: { type: String, required: true, trim: true },
    description: { type: String, trim: true, default: '' },

    coverUrl: { type: String, default: null },
    coverItemIds: { type: [mongoose.Schema.Types.ObjectId], ref: 'WatchlistItem', default: [] },
    coverCount: { type: Number, default: 4, min: 1, max: 8 },

    parentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Collection', default: null, index: true },
    kind: { type: String, enum: ['manual', 'smart'], default: 'manual' },
    filter: { type: mongoose.Schema.Types.Mixed, default: null },
    itemOrder: { type: [mongoose.Schema.Types.ObjectId], default: undefined },
    position: { type: Number, default: 0 },
  },
  { timestamps: true }
)

export default mongoose.model('Collection', collectionSchema)
