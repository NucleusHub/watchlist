import { ref, watch } from 'vue'
import { KEY_STORAGE_KEY } from '@/api/tmdb.js'
import { getSettings, saveSettings } from '@/api/watchlist.js'

function readStored() {
  try {
    return localStorage.getItem(KEY_STORAGE_KEY) || ''
  } catch {
    return ''
  }
}

const apiKey = ref(readStored())
let fromServer = false

watch(apiKey, (v) => {
  try {
    v ? localStorage.setItem(KEY_STORAGE_KEY, v) : localStorage.removeItem(KEY_STORAGE_KEY)
  } catch {
  }
  if (fromServer) {
    fromServer = false
    return
  }
  saveSettings({ tmdbApiKey: v }).catch(() => {})
})

let hydrated = false
async function hydrate() {
  if (hydrated) return
  hydrated = true
  try {
    const { tmdbApiKey } = await getSettings()
    if (tmdbApiKey && tmdbApiKey !== apiKey.value) {
      fromServer = true
      apiKey.value = tmdbApiKey
    } else if (!tmdbApiKey && apiKey.value) {
      saveSettings({ tmdbApiKey: apiKey.value }).catch(() => {})
    }
  } catch {
    hydrated = false
  }
}

export function useTmdbKey() {
  hydrate()
  return { apiKey }
}
