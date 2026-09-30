import { isNative } from '@/native.js'
import { readJson, writeJson, remove } from '@/storage/persist.js'
import { db, flush } from '@/storage/localDb.js'
import { updateItem } from '@/api/localApi.js'
import { emitItemChange } from '@/composables/useItemEvents.js'

// Edits made on the Apple Watch. The native side (ios/App/App/WatchBridge.swift)
// queues them here, and the database is only ever written from JS.
const INBOX_KEY = 'watch-inbox'

let draining = null

function patchFor(item, op) {
  if (op.field === 'favorite') return { favorite: !!op.value }
  if (op.field !== 'completed') return null
  if (!op.value) return { status: 'planned' }
  const patch = { status: 'completed' }
  if (item.type === 'show' && item.seasonProgress?.length) {
    patch.seasonProgress = item.seasonProgress.map((s) => ({ ...s, watched: s.episodeCount }))
  }
  return patch
}

async function drain() {
  const ops = await readJson(INBOX_KEY, [])
  if (!Array.isArray(ops) || !ops.length) return
  for (const op of ops.sort((a, b) => Date.parse(a.at) - Date.parse(b.at))) {
    const item = db().items.find((i) => i._id === op.itemId)
    // Something edited on the phone after the tap on the watch wins.
    if (!item || Date.parse(op.at) <= Date.parse(item.updatedAt || 0)) continue
    const patch = patchFor(item, op)
    if (!patch) continue
    emitItemChange({ type: 'updated', item: await updateItem(item._id, patch) })
  }
  await flush()
  // Keep anything the watch sent while this ran.
  const done = new Set(ops.map((o) => o.id))
  const left = (await readJson(INBOX_KEY, [])).filter((o) => !done.has(o.id))
  if (left.length) await writeJson(INBOX_KEY, left)
  else await remove(INBOX_KEY)
}

export function drainWatchInbox() {
  if (!isNative) return Promise.resolve()
  draining = (draining || Promise.resolve()).then(drain).catch((err) => console.error('[watchlist] watch inbox', err))
  return draining
}

export async function initWatchInbox() {
  if (!isNative) return
  window.addEventListener('watchinbox', () => drainWatchInbox())
  const { App } = await import('@capacitor/app')
  App.addListener('resume', () => drainWatchInbox())
  await drainWatchInbox()
}
