import { db, commit, newId, now } from '@/storage/localDb.js'

// The device-only implementation of api/watchlist.js. It mirrors the server
// routes (server/routes/*.js) closely enough that the views can't tell which
// one they are talking to.

const MAX_GENRES = 12
const MAX_GENRE_LEN = 40

// Callers pass Vue form state, whose nested arrays are reactive Proxies —
// structuredClone throws on those. Everything here is JSON anyway (it's
// exported and synced as JSON), so a JSON round-trip both strips the proxies
// on the way in and hands back copies the views can't mutate in place.
const clone = (v) => (v === undefined ? v : JSON.parse(JSON.stringify(v)))
const notFound = () => Object.assign(new Error('Not found'), { response: { status: 404 } })

function cleanGenres(value) {
  const out = []
  const seen = new Set()
  for (const raw of Array.isArray(value) ? value : []) {
    if (typeof raw !== 'string') continue
    const name = raw.trim().slice(0, MAX_GENRE_LEN)
    if (!name || seen.has(name.toLowerCase())) continue
    seen.add(name.toLowerCase())
    out.push(name)
    if (out.length === MAX_GENRES) break
  }
  return out
}

const ITEM_DEFAULTS = () => ({
  tmdbId: null,
  status: 'planned',
  posterUrl: null,
  tmdbRating: null,
  watchLink: null,
  streamingProvider: null,
  streamingLogo: null,
  rating: null,
  genres: [],
  favorite: false,
  year: null,
  runtime: null,
  seasons: null,
  episodes: null,
  showRuntime: null,
  openTarget: null,
  collectionIds: [],
  completedAt: null,
  notes: '',
})

const findItem = (id) => db().items.find((i) => i._id === id)
const findCollection = (id) => db().collections.find((c) => c._id === id)
const tombstone = (id) => { db().deleted[id] = now() }

export async function getItems({ status, type, collection } = {}) {
  return clone(
    db()
      .items.filter((i) => (!status || i.status === status) && (!type || i.type === type))
      .filter((i) => !collection || (i.collectionIds || []).includes(collection))
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))
  )
}

export async function createItem(data) {
  data = clone(data)
  const title = typeof data?.title === 'string' ? data.title.trim() : ''
  if (!title) throw new Error('Title is required')
  if (!['movie', 'show'].includes(data.type)) throw new Error('Type must be movie or show')
  const at = now()
  const item = { ...ITEM_DEFAULTS(), ...data, title, _id: newId(), dateAdded: at, createdAt: at, updatedAt: at }
  if ('genres' in data) item.genres = cleanGenres(data.genres)
  if (item.status === 'completed' && !item.completedAt) item.completedAt = at
  db().items.push(item)
  commit()
  return clone(item)
}

export async function updateItem(id, data) {
  const item = findItem(id)
  if (!item) throw notFound()
  const patch = clone(data)
  delete patch._id
  delete patch.completedAt
  if ('genres' in patch) patch.genres = cleanGenres(patch.genres)
  if (typeof patch.title === 'string') patch.title = patch.title.trim()
  if (patch.status && patch.status !== item.status) patch.completedAt = patch.status === 'completed' ? now() : null
  Object.assign(item, patch, { updatedAt: now() })
  commit()
  return clone(item)
}

export async function deleteItem(id) {
  const d = db()
  const i = d.items.findIndex((x) => x._id === id)
  if (i === -1) throw notFound()
  d.items.splice(i, 1)
  tombstone(id)
  commit()
  return { message: 'Deleted' }
}

export async function getSettings() {
  const { openDefaults, searchSources, pluginPlacements, tmdbApiKey } = db().settings
  return clone({ openDefaults, searchSources: searchSources ?? ['tmdb'], pluginPlacements: pluginPlacements ?? {}, tmdbApiKey: tmdbApiKey ?? '' })
}

const pickOpenTarget = (t) => ({ type: t?.type || 'tmdb', customUrl: t?.customUrl || '', titleFormat: t?.titleFormat || 'raw' })

export async function saveSettings(body = {}) {
  body = clone(body)
  const s = db().settings
  const before = JSON.stringify(s)
  if (body.movie !== undefined || body.show !== undefined) {
    s.openDefaults = { movie: pickOpenTarget(body.movie), show: pickOpenTarget(body.show) }
  }
  if (Array.isArray(body.searchSources)) {
    s.searchSources = [...new Set(['tmdb', ...body.searchSources.filter((x) => typeof x === 'string' && x)])]
  }
  if (body.pluginPlacements && typeof body.pluginPlacements === 'object') {
    s.pluginPlacements = Object.fromEntries(
      Object.entries(body.pluginPlacements).filter(([, w]) => ['tab', 'panel', 'hidden'].includes(w))
    )
  }
  if (typeof body.tmdbApiKey === 'string') s.tmdbApiKey = body.tmdbApiKey.trim().slice(0, 256)
  // Settings are re-saved on every hydrate; only a real change should sync.
  if (JSON.stringify(s) !== before) {
    s.updatedAt = now()
    commit()
  }
  return getSettings()
}

function decorate(col) {
  const members = db().items.filter((i) => (i.collectionIds || []).includes(col._id))
  const byId = new Map(db().items.map((i) => [i._id, i.posterUrl]))
  return clone({
    ...col,
    itemCount: members.length,
    previewPosters: members.map((m) => m.posterUrl).filter(Boolean).slice(0, 8),
    coverPosters: (col.coverItemIds || []).map((id) => byId.get(id)).filter(Boolean),
  })
}

function pickWritable(body = {}) {
  const out = {}
  if (typeof body.name === 'string') out.name = body.name.trim()
  if (typeof body.description === 'string') out.description = body.description.trim()
  if (body.coverUrl === null || typeof body.coverUrl === 'string') out.coverUrl = body.coverUrl
  if (Array.isArray(body.coverItemIds)) out.coverItemIds = body.coverItemIds
  if (Number.isFinite(body.coverCount)) out.coverCount = Math.min(8, Math.max(1, Math.round(body.coverCount)))
  return out
}

export async function getCollections() {
  return [...db().collections]
    .sort((a, b) => (a.position || 0) - (b.position || 0) || Date.parse(a.createdAt) - Date.parse(b.createdAt))
    .map(decorate)
}

export async function createCollection(data) {
  const fields = pickWritable(clone(data))
  if (!fields.name) throw new Error('Name is required')
  const at = now()
  const col = {
    description: '',
    coverUrl: null,
    coverItemIds: [],
    coverCount: 4,
    kind: 'manual',
    position: 0,
    ...fields,
    _id: newId(),
    createdAt: at,
    updatedAt: at,
  }
  db().collections.push(col)
  commit()
  return decorate(col)
}

export async function updateCollection(id, data) {
  const col = findCollection(id)
  if (!col) throw notFound()
  Object.assign(col, pickWritable(clone(data)), { updatedAt: now() })
  commit()
  return decorate(col)
}

export async function deleteCollection(id) {
  const d = db()
  const i = d.collections.findIndex((c) => c._id === id)
  if (i === -1) throw notFound()
  d.collections.splice(i, 1)
  tombstone(id)
  const at = now()
  for (const item of d.items) {
    if (!item.collectionIds?.includes(id)) continue
    item.collectionIds = item.collectionIds.filter((c) => c !== id)
    item.updatedAt = at
  }
  commit()
  return { message: 'Deleted' }
}

export async function addItemsToCollection(id, itemIds = []) {
  if (!findCollection(id)) throw notFound()
  const wanted = new Set(itemIds.map(String))
  const at = now()
  let modified = 0
  const items = db().items.filter((i) => wanted.has(i._id))
  for (const item of items) {
    if (item.collectionIds?.includes(id)) continue
    item.collectionIds = [...(item.collectionIds || []), id]
    item.updatedAt = at
    modified++
  }
  if (modified) commit()
  return { items: clone(items), modified }
}

export async function saveCollectionOrder(id, itemIds) {
  const col = findCollection(id)
  if (!col) throw notFound()
  col.itemOrder = itemIds.map(String)
  col.updatedAt = now()
  commit()
  return decorate(col)
}

// No server to upload to: keep the image in the document, scaled down so a
// handful of custom posters doesn't blow the Nucleus ID storage quota.
const MAX_IMAGE_EDGE = 480

export function uploadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      const scale = Math.min(1, MAX_IMAGE_EDGE / Math.max(img.width, img.height))
      const canvas = document.createElement('canvas')
      canvas.width = Math.round(img.width * scale)
      canvas.height = Math.round(img.height * scale)
      canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height)
      URL.revokeObjectURL(url)
      resolve(canvas.toDataURL('image/jpeg', 0.72))
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('Could not read that image'))
    }
    img.src = url
  })
}
