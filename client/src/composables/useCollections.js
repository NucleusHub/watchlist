import { ref } from 'vue'
import {
  getCollections,
  createCollection as apiCreate,
  updateCollection as apiUpdate,
  deleteCollection as apiDelete,
} from '@/api/watchlist.js'

// Per-profile collections, exposed as a module-level reactive singleton so every
// surface — the Collections view, an item's "manage collections" modal, the
// header nav — reads and mutates the same live list (mirrors useOpenSettings).
//
// Item counts are derived server-side from membership; since membership lives on
// the item and is edited via the normal item PATCH, applyMembership() keeps the
// cached counts in step without a round-trip. hydrate() is the source of truth.
const collections = ref([])
const loading = ref(false)
let hydrated = false

async function hydrate(force = false) {
  if (hydrated && !force) return
  hydrated = true
  loading.value = true
  try {
    collections.value = await getCollections()
  } catch {
    // Offline / unauthenticated — keep whatever we have; a later call retries.
    hydrated = false
  } finally {
    loading.value = false
  }
}

function upsert(col) {
  const i = collections.value.findIndex((c) => c._id === col._id)
  if (i === -1) collections.value.push(col)
  else collections.value[i] = { ...collections.value[i], ...col }
}

export function useCollections() {
  hydrate()
  return {
    collections,
    loading,
    reload: () => hydrate(true),
    byId: (id) => collections.value.find((c) => c._id === id) || null,

    async create(data) {
      const col = await apiCreate(data)
      upsert(col)
      return col
    },
    async update(id, data) {
      const col = await apiUpdate(id, data)
      upsert(col)
      return col
    },
    async remove(id) {
      await apiDelete(id)
      collections.value = collections.value.filter((c) => c._id !== id)
    },

    // Store a collection's manual item order in the cache so the browse view
    // reflects it immediately after a reorder.
    applyOrder(id, itemIds) {
      const c = collections.value.find((x) => String(x._id) === String(id))
      if (c) c.itemOrder = [...itemIds]
    },

    // Nudge one collection's cached count (e.g. after a bulk add returns how
    // many items actually changed).
    bumpCount(id, delta) {
      const c = collections.value.find((x) => String(x._id) === String(id))
      if (c) c.itemCount = Math.max(0, (c.itemCount || 0) + delta)
    },

    // Reconcile cached counts after an item's membership changed (arrays of ids).
    applyMembership(prevIds = [], nextIds = []) {
      const prev = new Set(prevIds.map(String))
      const next = new Set(nextIds.map(String))
      for (const c of collections.value) {
        const id = String(c._id)
        if (next.has(id) && !prev.has(id)) c.itemCount = (c.itemCount || 0) + 1
        else if (prev.has(id) && !next.has(id)) c.itemCount = Math.max(0, (c.itemCount || 0) - 1)
      }
    },
  }
}
