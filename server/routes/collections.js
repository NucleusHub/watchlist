import { Router } from 'express'
import mongoose from 'mongoose'
import Collection from '../models/Collection.js'
import WatchlistItem from '../models/WatchlistItem.js'
import { requireAuth } from '../middleware/auth.js'

const router = Router()
router.use(requireAuth)

const pickWritable = (body = {}) => {
  const out = {}
  if (typeof body.name === 'string') out.name = body.name.trim()
  if (typeof body.description === 'string') out.description = body.description.trim()
  if (body.coverUrl === null || typeof body.coverUrl === 'string') out.coverUrl = body.coverUrl
  if (Array.isArray(body.coverItemIds)) out.coverItemIds = body.coverItemIds
  if (Number.isFinite(body.coverCount)) out.coverCount = Math.min(8, Math.max(1, Math.round(body.coverCount)))
  return out
}

async function decorate(col, profileId) {
  const base = col.toObject ? col.toObject() : col
  const [itemCount, members] = await Promise.all([
    WatchlistItem.countDocuments({ profileId, collectionIds: base._id }),
    WatchlistItem.find({ profileId, collectionIds: base._id, posterUrl: { $ne: null } })
      .select('posterUrl')
      .limit(8)
      .lean(),
  ])
  let coverPosters = []
  if (base.coverItemIds?.length) {
    const items = await WatchlistItem.find({ profileId, _id: { $in: base.coverItemIds } })
      .select('posterUrl')
      .lean()
    const map = new Map(items.map((i) => [String(i._id), i.posterUrl]))
    coverPosters = base.coverItemIds.map((id) => map.get(String(id))).filter(Boolean)
  }
  return { ...base, itemCount, previewPosters: members.map((m) => m.posterUrl).filter(Boolean), coverPosters }
}

router.get('/', async (req, res) => {
  try {
    const profileId = req.profile.profileId
    const cols = await Collection.find({ profileId }).sort({ position: 1, createdAt: 1 }).lean()
    res.json(await Promise.all(cols.map((c) => decorate(c, profileId))))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/', async (req, res) => {
  try {
    const data = pickWritable(req.body)
    if (!data.name) return res.status(400).json({ error: 'Name is required' })
    const col = await Collection.create({ ...data, profileId: req.profile.profileId })
    res.status(201).json(await decorate(col, req.profile.profileId))
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.patch('/:id', async (req, res) => {
  try {
    const data = pickWritable(req.body)
    const col = await Collection.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      data,
      { returnDocument: 'after', runValidators: true }
    )
    if (!col) return res.status(404).json({ error: 'Not found' })
    res.json(await decorate(col, req.profile.profileId))
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.post('/:id/items', async (req, res) => {
  try {
    const ids = Array.isArray(req.body?.itemIds) ? req.body.itemIds : []
    const col = await Collection.findOne({ _id: req.params.id, profileId: req.profile.profileId }).lean()
    if (!col) return res.status(404).json({ error: 'Not found' })
    if (!ids.length) return res.json({ items: [], modified: 0 })
    const { modifiedCount } = await WatchlistItem.updateMany(
      { _id: { $in: ids }, profileId: req.profile.profileId },
      { $addToSet: { collectionIds: col._id } }
    )
    const items = await WatchlistItem.find({ _id: { $in: ids }, profileId: req.profile.profileId })
    res.json({ items, modified: modifiedCount })
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.put('/:id/order', async (req, res) => {
  try {
    const itemIds = Array.isArray(req.body?.itemIds) ? req.body.itemIds : null
    if (!itemIds) return res.status(400).json({ error: 'itemIds must be an array' })
    const col = await Collection.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      { itemOrder: itemIds },
      { returnDocument: 'after', runValidators: true }
    )
    if (!col) return res.status(404).json({ error: 'Not found' })
    res.json(await decorate(col, req.profile.profileId))
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.delete('/:id', async (req, res) => {
  try {
    const col = await Collection.findOneAndDelete({ _id: req.params.id, profileId: req.profile.profileId })
    if (!col) return res.status(404).json({ error: 'Not found' })
    await WatchlistItem.updateMany(
      { profileId: req.profile.profileId, collectionIds: col._id },
      { $pull: { collectionIds: col._id } }
    )
    res.json({ message: 'Deleted' })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
