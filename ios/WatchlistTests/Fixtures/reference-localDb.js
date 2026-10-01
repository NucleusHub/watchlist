import { ref } from 'vue'
import { readJson, writeJson } from './persist.js'

// The on-device database: one JSON document holding everything, the same
// shape that is exported to a file and synced to Nucleus ID. Every record
// carries `updatedAt`, and deletions leave a tombstone in `deleted`, so two
// copies can be merged without resurrecting what one side removed.
const STORAGE_KEY = 'watchlist-db'
const TOMBSTONE_TTL_MS = 180 * 24 * 3600 * 1000
export const FORMAT = 'nucleus-watchlist'
export const FORMAT_VERSION = 1

const emptySettings = () => ({
  openDefaults: null,
  searchSources: ['tmdb'],
  pluginPlacements: {},
  tmdbApiKey: '',
  updatedAt: null,
})

export const emptyDoc = () => ({ items: [], collections: [], settings: emptySettings(), deleted: {} })

let doc = emptyDoc()
// Bumped when data changes underneath the views (a sync pulled something in,
// a backup was imported), so they reload.
export const revision = ref(0)
let saveTimer = null
const listeners = new Set()

export const now = () => new Date().toISOString()

export function newId() {
  const bytes = crypto.getRandomValues(new Uint8Array(12))
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}

export function normalizeDoc(raw) {
  const out = emptyDoc()
  if (!raw || typeof raw !== 'object') return out
  if (Array.isArray(raw.items)) out.items = raw.items.filter((i) => i && i._id && i.title)
  if (Array.isArray(raw.collections)) out.collections = raw.collections.filter((c) => c && c._id && c.name)
  if (raw.settings && typeof raw.settings === 'object') out.settings = { ...emptySettings(), ...raw.settings }
  if (raw.deleted && typeof raw.deleted === 'object') out.deleted = { ...raw.deleted }
  return out
}

export async function loadDb() {
  doc = normalizeDoc(await readJson(STORAGE_KEY))
}

export const db = () => doc

export function isEmpty(d = doc) {
  return !d.items.length && !d.collections.length
}

/** Persist soon and tell the sync layer something changed locally. */
export function commit({ silent = false } = {}) {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(flush, 150)
  if (!silent) for (const fn of listeners) fn()
}

export async function flush() {
  clearTimeout(saveTimer)
  await writeJson(STORAGE_KEY, doc).catch((err) => console.error('[watchlist] could not save', err))
}

export function onLocalChange(fn) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

export function replaceDoc(next, opts) {
  doc = normalizeDoc(next)
  revision.value++
  commit(opts)
}

/** Empty the watchlist on this device. Settings (the TMDb key…) are device setup, not data, and stay. */
export function clearData() {
  doc = { ...emptyDoc(), settings: doc.settings }
  revision.value++
  commit({ silent: true })
}

export function exportDoc() {
  return { format: FORMAT, version: FORMAT_VERSION, exportedAt: now(), ...JSON.parse(JSON.stringify(doc)) }
}

const stamp = (r) => Date.parse(r?.updatedAt || r?.createdAt || 0) || 0

function mergeRecords(a, b, deleted) {
  const map = new Map()
  for (const r of [...a, ...b]) {
    const prev = map.get(r._id)
    if (!prev || stamp(r) > stamp(prev)) map.set(r._id, r)
  }
  // An edit made after the delete wins; anything older stays deleted.
  return [...map.values()].filter((r) => !deleted[r._id] || Date.parse(deleted[r._id]) < stamp(r))
}

/** Union of two documents, newest record wins. Pure: returns a new document. */
export function mergeDocs(a, b) {
  a = normalizeDoc(a)
  b = normalizeDoc(b)
  const cutoff = Date.now() - TOMBSTONE_TTL_MS
  const deleted = {}
  for (const [id, at] of [...Object.entries(a.deleted), ...Object.entries(b.deleted)]) {
    if (Date.parse(at) < cutoff) continue
    if (!deleted[id] || Date.parse(at) > Date.parse(deleted[id])) deleted[id] = at
  }
  return {
    items: mergeRecords(a.items, b.items, deleted),
    collections: mergeRecords(a.collections, b.collections, deleted),
    settings: stamp(b.settings) > stamp(a.settings) ? b.settings : a.settings,
    deleted,
  }
}

/** Order-insensitive fingerprint, to tell whether a merge changed anything. */
export function fingerprint(d) {
  const ids = (list) => list.map((r) => `${r._id}@${r.updatedAt}`).sort().join(',')
  return `${ids(d.items)}|${ids(d.collections)}|${d.settings?.updatedAt}|${Object.keys(d.deleted).length}`
}
