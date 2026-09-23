import { ref, watch } from 'vue'
import { KEY_STORAGE_KEY } from '@/api/tmdb.js'

// A user-supplied TMDb API key, stored per-device (not synced to the server —
// it's a device/API-access concern, not a user preference). Lets someone run
// the app without VITE_TMDB_API_KEY baked in at build time: paste a key in
// Settings and search works immediately, no rebuild.

function readStored() {
  try {
    return localStorage.getItem(KEY_STORAGE_KEY) || ''
  } catch {
    return ''
  }
}

const apiKey = ref(readStored())

watch(apiKey, (v) => {
  try {
    v ? localStorage.setItem(KEY_STORAGE_KEY, v) : localStorage.removeItem(KEY_STORAGE_KEY)
  } catch {
    // Storage unavailable (private mode, quota) — key just won't persist.
  }
})

export function useTmdbKey() {
  return { apiKey }
}
