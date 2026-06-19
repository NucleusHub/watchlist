import { Router } from 'express'
import path from 'path'
import fs from 'node:fs'
import { fileURLToPath } from 'url'
import WatchlistItem from '../models/WatchlistItem.js'
import { requireAuth } from '../middleware/auth.js'

const router = Router()
router.use(requireAuth)

const uploadsDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../uploads')

function requireAdmin(req, res, next) {
  if (req.profile?.role !== 'admin') return res.status(403).json({ error: 'Admin required' })
  next()
}

// Called by the admin panel when a user is deleted: remove their watchlist
// items and any locally-uploaded poster images.
//   POST /api/watchlist/users/:userId/teardown
router.post('/users/:userId/teardown', requireAdmin, async (req, res) => {
  try {
    const items = await WatchlistItem.find({ profileId: req.params.userId }).select('posterUrl')
    for (const it of items) {
      if (it.posterUrl?.startsWith('/uploads/')) {
        fs.unlink(path.join(uploadsDir, path.basename(it.posterUrl)), () => {})
      }
    }
    const { deletedCount } = await WatchlistItem.deleteMany({ profileId: req.params.userId })
    res.json({ ok: true, deleted: deletedCount })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/', async (req, res) => {
  try {
    const { status, type } = req.query
    const filter = { profileId: req.profile.profileId }
    if (status) filter.status = status
    if (type) filter.type = type
    const items = await WatchlistItem.find(filter).sort({ createdAt: -1 })
    res.json(items)
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/', async (req, res) => {
  try {
    const item = await WatchlistItem.create({ ...req.body, profileId: req.profile.profileId })
    res.status(201).json(item)
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.patch('/:id', async (req, res) => {
  try {
    const item = await WatchlistItem.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      req.body,
      { new: true, runValidators: true }
    )
    if (!item) return res.status(404).json({ error: 'Not found' })
    res.json(item)
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.delete('/:id', async (req, res) => {
  try {
    const item = await WatchlistItem.findOneAndDelete(
      { _id: req.params.id, profileId: req.profile.profileId }
    )
    if (!item) return res.status(404).json({ error: 'Not found' })
    res.json({ message: 'Deleted' })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
