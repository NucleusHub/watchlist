import { Router } from 'express'
import path from 'path'
import fs from 'node:fs'
import { fileURLToPath } from 'url'
import WatchlistItem from '../models/WatchlistItem.js'
import WatchlistSettings from '../models/WatchlistSettings.js'
import Collection from '../models/Collection.js'
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
    // Their collections are just groupings of those items — remove them too so a
    // deleted user leaves nothing behind.
    await Collection.deleteMany({ profileId: req.params.userId })
    res.json({ ok: true, deleted: deletedCount })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// ── Per-user app preferences ────────────────────────────────────────────────
// The per-type "open in" defaults. These used to live only in the browser, so
// they vanished each session; now persisted per profile. Defined before the
// `/:id` item routes for readability (no method collision — those are PATCH/DELETE).

// Coerce a client-supplied open target into the stored shape, dropping junk.
const pickOpenTarget = (t) => ({
  type: t?.type || 'tmdb',
  customUrl: t?.customUrl || '',
  titleFormat: t?.titleFormat || 'raw',
})

router.get('/settings', async (req, res) => {
  try {
    const doc = await WatchlistSettings.findOne({ profileId: req.profile.profileId }).lean()
    res.json({ openDefaults: doc?.openDefaults ?? null, searchSources: doc?.searchSources ?? ['tmdb'] })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.put('/settings', async (req, res) => {
  try {
    // Partial-safe: only touch the fields present in the body so a search-source
    // save can't wipe the open defaults (and vice-versa).
    const $set = {}
    if (req.body?.movie !== undefined || req.body?.show !== undefined) {
      $set.openDefaults = {
        movie: pickOpenTarget(req.body?.movie),
        show: pickOpenTarget(req.body?.show),
      }
    }
    if (Array.isArray(req.body?.searchSources)) {
      // Normalize: strings only, unique, and always keep TMDb (the built-in).
      const ids = req.body.searchSources.filter((s) => typeof s === 'string' && s)
      $set.searchSources = [...new Set(['tmdb', ...ids])]
    }
    const doc = await WatchlistSettings.findOneAndUpdate(
      { profileId: req.profile.profileId },
      { $set },
      { new: true, upsert: true, runValidators: true, setDefaultsOnInsert: true }
    ).lean()
    res.json({ openDefaults: doc.openDefaults, searchSources: doc.searchSources ?? ['tmdb'] })
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.get('/', async (req, res) => {
  try {
    const { status, type, collection } = req.query
    const filter = { profileId: req.profile.profileId }
    if (status) filter.status = status
    if (type) filter.type = type
    // Browse a single collection: only its members (see models/Collection.js).
    if (collection) filter.collectionIds = collection
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
