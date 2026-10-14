import { ref } from 'vue'
import { getSettings, saveSettings } from '@/api/watchlist.js'
import * as engine from '@/movieDNA/engine.js'

// What the person set lives in `settings.movieDNA`; what it learns is worked out from the library on read.
const settings = ref(engine.normalizeSettings(null))
let loading = null
let loaded = false
let queue = Promise.resolve()
let pending = 0
export function loadMovieDNA() {
  loading ??= getSettings()
    .then((s) => {
      settings.value = engine.normalizeSettings(s.movieDNA)
      loaded = true
    })
    .catch(() => { loading = null })
  return loading
}

async function update(fn) {
  await loadMovieDNA()
  // Saving over a copy we never read would wipe the server's.
  if (!loaded) return
  settings.value = fn(settings.value)
  pending++
  // The server replaces movieDNA whole, so apply the change to a fresh copy to keep edits made on other devices.
  queue = queue
    .then(async () => {
      const next = fn(engine.normalizeSettings((await getSettings()).movieDNA))
      await saveSettings({ movieDNA: next })
      if (pending === 1) settings.value = next
    })
    .catch(() => {
      loading = null
      loadMovieDNA()
    })
    .finally(() => { pending-- })
}

const MUTATIONS = [
  'setEnabled', 'markInterested', 'setStrength', 'addToDNA', 'markNotInterested',
  'clearNotInterested', 'setFollowing', 'removeFromDNA', 'rebuild',
]
const actions = Object.fromEntries(MUTATIONS.map((name) => [name, (...args) => update((s) => engine[name](s, ...args))]))

export function useMovieDNA() {
  loadMovieDNA()
  return { settings, ...actions }
}
