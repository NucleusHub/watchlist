import {
  getItems, createItem, updateItem, deleteItem,
  getCollections, createCollection, updateCollection, deleteCollection, saveCollectionOrder,
  getSettings, saveSettings,
} from '@/api/watchlist.js'
import { storeAccent } from '@/utils/accent.js'
import { buildBackup, backupFileName, planImport, itemPayload, collectionPayload, remapIds, newerAccent } from '@/utils/backup.js'

export async function exportBackup() {
  const [items, collections, settings] = await Promise.all([getItems(), getCollections(), getSettings()])
  const text = JSON.stringify(buildBackup({ items, collections, settings }), null, 2)
  const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }))
  const a = Object.assign(document.createElement('a'), { href: url, download: backupFileName() })
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  return { items: items.length, collections: collections.length }
}

// Settings the file carries: replace takes them all, merge only the newer accent and a key this account lacks.
const settingsPatch = (file, current, replace) => {
  const patch = {}
  const accent = replace && file.accent?.id ? file.accent : newerAccent(current.accent, file.accent)
  if (accent?.id && accent !== current.accent) patch.accent = replace ? { ...accent, updatedAt: new Date().toISOString() } : accent
  if (typeof file.tmdbApiKey === 'string' && file.tmdbApiKey && (replace || !current.tmdbApiKey)) patch.tmdbApiKey = file.tmdbApiKey
  if (replace) {
    const { openDefaults, searchSources, pluginPlacements, movieDNA } = file
    if (openDefaults?.movie && openDefaults?.show) Object.assign(patch, { movie: openDefaults.movie, show: openDefaults.show })
    Object.assign(patch, { ...(searchSources && { searchSources }), ...(pluginPlacements && { pluginPlacements }), ...(movieDNA !== undefined && { movieDNA }) })
  }
  return patch
}

// Applies a parsed backup through the REST API. Collections may get new ids on the server, so item
// memberships, covers and order are translated once everything exists. Replace is upsert-then-prune:
// leftovers are deleted last, and only when every record in the file was valid and went through.
export async function importBackup(file, replace) {
  if (replace) await exportBackup()
  const [items, collections, settings] = await Promise.all([getItems(), getCollections(), getSettings()])
  const plan = planImport({ items, collections }, file, replace)
  let failed = 0
  const attempt = async (fn) => { try { return await fn() } catch { failed++ } }

  // File ids -> live ids. Everything that already matched maps to itself.
  const colIds = new Map((replace ? [] : collections).map((c) => [String(c._id), String(c._id)]))
  const itemIds = new Map((replace ? [] : items).map((i) => [String(i._id), String(i._id)]))
  for (const { record, id } of plan.collections) {
    const data = collectionPayload(record)
    // An id taken by another account is refused; retry with a fresh one.
    const live = await attempt(() => (id ? updateCollection(id, data) : createCollection(data).catch(() => createCollection({ ...data, _id: undefined }))))
    if (live) colIds.set(String(record._id), String(live._id))
  }
  for (const { record, id } of plan.items) {
    const data = { ...itemPayload(record), collectionIds: remapIds(record.collectionIds, colIds) }
    const live = await attempt(() => (id ? updateItem(id, data) : createItem(data).catch(() => createItem({ ...data, _id: undefined }))))
    if (live) itemIds.set(String(record._id), String(live._id))
  }
  for (const { record } of plan.collections) {
    const live = colIds.get(String(record._id))
    if (!live) continue
    const cover = remapIds(record.coverItemIds, itemIds)
    const order = remapIds(record.itemOrder, itemIds)
    if (cover.length) await attempt(() => updateCollection(live, { coverItemIds: cover }))
    if (order.length) await attempt(() => saveCollectionOrder(live, order))
  }
  // A record the file couldn't hold may be one we'd prune, so keep everything then.
  if (replace && !failed && !file.skipped) await Promise.all([...plan.deleteItems.map(deleteItem), ...plan.deleteCollections.map(deleteCollection)])

  const patch = settingsPatch(file.settings, settings, replace)
  if (Object.keys(patch).length) await saveSettings(patch)
  // Without this the newer local accent would win over the stamped one after reload.
  if (replace && patch.accent) storeAccent(patch.accent)
  return { items: plan.items.length, collections: plan.collections.length, skipped: (file.skipped || 0) + failed, patch }
}
