import { ref } from 'vue'
import {
  getCollections,
  createCollection as apiCreate,
  updateCollection as apiUpdate,
  deleteCollection as apiDelete,
} from '@/api/watchlist.js'

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
    hydrated = false
  } finally {
    loading.value = false
  }
}

export const reloadCollections = () => hydrate(true)

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

    applyOrder(id, itemIds) {
      const c = collections.value.find((x) => String(x._id) === String(id))
      if (c) c.itemOrder = [...itemIds]
    },

    bumpCount(id, delta) {
      const c = collections.value.find((x) => String(x._id) === String(id))
      if (c) c.itemCount = Math.max(0, (c.itemCount || 0) + delta)
    },

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
