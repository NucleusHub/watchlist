// Backup files share the iOS format (ios/Watchlist/Store/Backup.swift): one JSON document.
export const FORMAT = 'nucleus-watchlist'

const OBJECT_ID = /^[0-9a-f]{24}$/i
const SERVER_ONLY = ['profileId', '__v', 'itemCount', 'previewPosters', 'coverPosters']

export const backupFileName = (date = new Date()) => `watchlist-${date.toISOString().slice(0, 10)}.json`

const strip = (record) => Object.fromEntries(Object.entries(record).filter(([k]) => !SERVER_ONLY.includes(k)))

export function buildBackup({ items, collections, settings }, now = new Date()) {
  return {
    format: FORMAT,
    version: 1,
    exportedAt: now.toISOString(),
    items: items.map(strip),
    collections: collections.map(strip),
    settings: { ...settings, updatedAt: now.toISOString() },
    deleted: {},
  }
}

const isRecord = (v, key) => v && typeof v === 'object' && v._id && v[key]
const TYPES = ['movie', 'show']
const STATUSES = ['planned', 'watching', 'completed']
// What the server's WatchlistItem schema would reject.
const validItem = (i) => isRecord(i, 'title') && TYPES.includes(i.type)
  && (i.status === undefined || STATUSES.includes(i.status))
  && (i.seasonProgress == null || (Array.isArray(i.seasonProgress) && i.seasonProgress.every((s) => Number.isFinite(s?.seasonNumber))))

// Throws when the text isn't a Watchlist backup; drops invalid records and counts them in `skipped`.
export function parseBackup(text) {
  let doc
  try { doc = JSON.parse(text) } catch { throw new Error('notABackup') }
  if (doc?.format !== FORMAT || !Array.isArray(doc.items)) throw new Error('notABackup')
  const rawCollections = Array.isArray(doc.collections) ? doc.collections : []
  const items = doc.items.filter(validItem)
  const collections = rawCollections.filter((c) => isRecord(c, 'name'))
  return {
    items,
    collections,
    skipped: doc.items.length - items.length + rawCollections.length - collections.length,
    settings: doc.settings && typeof doc.settings === 'object' ? doc.settings : {},
    exportedAt: typeof doc.exportedAt === 'string' ? doc.exportedAt : null,
  }
}

// When a record last changed, in ms; 0 if unknown.
export const stamp = (r) => Date.parse(r?.updatedAt || r?.createdAt) || 0

// The REST API takes an item's own id when it is an ObjectId; collections only take what pickWritable keeps.
export const itemPayload = (item) => {
  const data = strip(item)
  if (!OBJECT_ID.test(data._id)) delete data._id
  return data
}
// Covers are set in a second pass, once item ids are remapped.
const COLLECTION_FIELDS = ['name', 'description', 'coverUrl', 'coverCount']
export const collectionPayload = (c) => ({
  ...(OBJECT_ID.test(c._id) && { _id: c._id }),
  ...Object.fromEntries(Object.entries(c).filter(([k]) => COLLECTION_FIELDS.includes(k))),
})

// What to do with a file's records. Merge adds new ones and takes a file record only when it's newer;
// replace takes every file record (matched by id) and lists what's left over to delete afterwards.
export function planImport(current, file, replace) {
  const plan = { deleteItems: [], deleteCollections: [], items: [], collections: [] }
  const have = (list) => new Map(list.map((r) => [String(r._id), r]))
  const sort = (records, existing, out) => {
    for (const r of records) {
      const cur = existing.get(String(r._id))
      if (!cur) out.push({ record: r })
      else if (replace || stamp(r) > stamp(cur)) out.push({ record: r, id: String(cur._id) })
    }
  }
  sort(file.items, have(current.items), plan.items)
  sort(file.collections, have(current.collections), plan.collections)
  if (replace) {
    const left = (list, kept) => list.map((r) => String(r._id)).filter((id) => !kept.has(id))
    plan.deleteItems = left(current.items, new Set(file.items.map((r) => String(r._id))))
    plan.deleteCollections = left(current.collections, new Set(file.collections.map((r) => String(r._id))))
  }
  return plan
}

// File ids to the ids they ended up with; ids with no entry (a collection that wasn't imported) drop out.
export const remapIds = (ids, map) => (Array.isArray(ids) ? ids.map((id) => map.get(String(id))).filter(Boolean) : [])

// The accent that was picked last, `{ id, custom, updatedAt }` or null.
export const newerAccent = (a, b) => (!a?.id ? b || null : !b?.id ? a : Date.parse(b.updatedAt) > Date.parse(a.updatedAt) ? b : a)
