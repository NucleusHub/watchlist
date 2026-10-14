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

router.post('/users/:userId/teardown', requireAdmin, async (req, res) => {
  try {
    const items = await WatchlistItem.find({ profileId: req.params.userId }).select('posterUrl')
    for (const it of items) {
      if (it.posterUrl?.startsWith('/uploads/')) {
        fs.unlink(path.join(uploadsDir, path.basename(it.posterUrl)), () => {})
      }
    }
    const { deletedCount } = await WatchlistItem.deleteMany({ profileId: req.params.userId })
    await Collection.deleteMany({ profileId: req.params.userId })
    res.json({ ok: true, deleted: deletedCount })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

const pickOpenTarget = (t) => ({
  type: t?.type || 'tmdb',
  customUrl: t?.customUrl || '',
  titleFormat: t?.titleFormat || 'raw',
})

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v)

// Keeps the iOS shape (ios/Watchlist/Model/MovieDNA.swift) so device and server copies hash equal.
function pickMovieDNA(v) {
  return {
    enabled: typeof v.enabled === 'boolean' ? v.enabled : true,
    entries: isPlainObject(v.entries) ? Object.fromEntries(Object.entries(v.entries).filter(([, e]) => isPlainObject(e) && typeof e.kind === 'string')) : {},
    notInterested: isPlainObject(v.notInterested) ? Object.fromEntries(Object.entries(v.notInterested).filter(([, n]) => isPlainObject(n))) : {},
  }
}

const placementsOut = (m) => (m instanceof Map ? Object.fromEntries(m) : m ?? {})

router.get('/settings', async (req, res) => {
  try {
    const doc = await WatchlistSettings.findOne({ profileId: req.profile.profileId }).lean()
    res.json({
      openDefaults: doc?.openDefaults ?? null,
      searchSources: doc?.searchSources ?? ['tmdb'],
      pluginPlacements: placementsOut(doc?.pluginPlacements),
      tmdbApiKey: doc?.tmdbApiKey ?? '',
      accent: doc?.accent ?? null,
      movieDNA: doc?.movieDNA ?? null,
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.put('/settings', async (req, res) => {
  try {
    const $set = {}
    if (req.body?.movie !== undefined || req.body?.show !== undefined) {
      $set.openDefaults = {
        movie: pickOpenTarget(req.body?.movie),
        show: pickOpenTarget(req.body?.show),
      }
    }
    if (Array.isArray(req.body?.searchSources)) {
      const ids = req.body.searchSources.filter((s) => typeof s === 'string' && s)
      $set.searchSources = [...new Set(['tmdb', ...ids])]
    }
    if (req.body?.pluginPlacements && typeof req.body.pluginPlacements === 'object') {
      const placements = {}
      for (const [id, where] of Object.entries(req.body.pluginPlacements)) {
        if (['tab', 'panel', 'hidden'].includes(where)) placements[id] = where
      }
      $set.pluginPlacements = placements
    }
    if (typeof req.body?.tmdbApiKey === 'string') $set.tmdbApiKey = req.body.tmdbApiKey.trim()
    if (req.body?.accent === null) $set.accent = null
    else if (typeof req.body?.accent?.id === 'string' && req.body.accent.id) {
      const { id, custom, updatedAt } = req.body.accent
      $set.accent = { id, custom: typeof custom === 'string' ? custom : null, updatedAt: updatedAt ? new Date(updatedAt) : new Date() }
    }
    if (req.body?.movieDNA === null) $set.movieDNA = null
    else if (isPlainObject(req.body?.movieDNA)) $set.movieDNA = pickMovieDNA(req.body.movieDNA)
    const doc = await WatchlistSettings.findOneAndUpdate(
      { profileId: req.profile.profileId },
      { $set },
      { new: true, upsert: true, runValidators: true, setDefaultsOnInsert: true }
    ).lean()
    res.json({
      openDefaults: doc.openDefaults,
      searchSources: doc.searchSources ?? ['tmdb'],
      pluginPlacements: placementsOut(doc.pluginPlacements),
      tmdbApiKey: doc.tmdbApiKey ?? '',
      accent: doc.accent ?? null,
      movieDNA: doc.movieDNA ?? null,
    })
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
    if (collection) filter.collectionIds = collection
    const items = await WatchlistItem.find(filter).sort({ createdAt: -1 })
    res.json(items)
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

const MAX_GENRES = 12
const MAX_GENRE_LEN = 40

function cleanGenres(value) {
  const out = []
  const seen = new Set()
  for (const raw of Array.isArray(value) ? value : []) {
    if (typeof raw !== 'string') continue
    const name = raw.trim().slice(0, MAX_GENRE_LEN)
    if (!name) continue
    const key = name.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    out.push(name)
    if (out.length === MAX_GENRES) break
  }
  return out
}

function cleanCredits(value) {
  if (!Array.isArray(value)) return undefined
  return value
    .filter((c) => c && typeof c.name === 'string' && c.name.trim())
    .map((c) => ({
      name: c.name.trim(),
      role: typeof c.role === 'string' ? c.role : '',
      cast: c.cast !== false,
      personId: Number.isFinite(c.personId) ? c.personId : null,
      photo: typeof c.photo === 'string' ? c.photo : null,
    }))
}

// Applies shared iOS-field normalisation; an invalid playback is dropped rather than rejected.
function cleanIosFields(body) {
  if ('customCredits' in body) body.customCredits = cleanCredits(body.customCredits)
  if ('playback' in body) {
    const p = body.playback
    body.playback = p && typeof p.url === 'string' && p.url && p.duration > 0
      ? { url: p.url, position: Math.max(0, Number(p.position) || 0), duration: p.duration }
      : null
  }
}

router.post('/', async (req, res) => {
  try {
    const body = { ...req.body }
    if ('genres' in body) body.genres = cleanGenres(body.genres)
    cleanIosFields(body)
    if (body.status === 'completed' && !body.completedAt) body.completedAt = new Date()
    const item = await WatchlistItem.create({ ...body, profileId: req.profile.profileId })
    res.status(201).json(item)
  } catch (err) {
    res.status(400).json({ error: err.message })
  }
})

router.patch('/:id', async (req, res) => {
  try {
    const current = await WatchlistItem.findOne(
      { _id: req.params.id, profileId: req.profile.profileId }
    ).select('status completedAt').lean()
    if (!current) return res.status(404).json({ error: 'Not found' })

    const patch = { ...req.body }
    if ('genres' in patch) patch.genres = cleanGenres(patch.genres)
    cleanIosFields(patch)
    // completedAt is server-derived; re-saving an already completed item keeps the original date.
    delete patch.completedAt
    if (patch.status && patch.status !== current.status) {
      if (patch.status === 'completed') patch.completedAt = new Date()
      else patch.completedAt = null
    }

    const item = await WatchlistItem.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      patch,
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
