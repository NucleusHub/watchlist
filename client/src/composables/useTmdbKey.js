import { ref, watch } from 'vue'
import { KEY_STORAGE_KEY } from '@/api/tmdb.js'

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
  }
})

export function useTmdbKey() {
  return { apiKey }
}
