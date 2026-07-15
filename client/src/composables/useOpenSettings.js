import { reactive, ref, watch } from 'vue'
import { getSettings, saveSettings } from '@/api/watchlist.js'

// Per-profile Watchlist preferences: the per-type "open on click" defaults and
// the set of enabled metadata search sources. The server is the source of truth
// (so they follow the user across sessions/devices); localStorage is a no-flash
// cache so the last-known values render instantly before the server hydrate
// lands. Exposed as a module-level reactive singleton so any component — the
// settings modal, every ItemCard, the add/edit form — reads/writes the same
// live state.
const KEY = 'watchlist-settings'
const DEFAULT = () => ({ type: 'tmdb', customUrl: '', titleFormat: 'raw' })
const BUILTIN_SOURCE = 'tmdb'

const normalize = (t) => ({
  type: t?.type || 'tmdb',
  customUrl: t?.customUrl || '',
  titleFormat: t?.titleFormat || 'raw',
})

// The built-in TMDb source is always searched; plugin sources are opt-in.
const normalizeSources = (arr) => {
  const ids = Array.isArray(arr) ? arr.filter((s) => typeof s === 'string' && s) : []
  return [...new Set([BUILTIN_SOURCE, ...ids])]
}

const defaults = reactive({ movie: DEFAULT(), show: DEFAULT() })
const searchSources = ref([BUILTIN_SOURCE])

// The full persisted snapshot — what both the cache and the server PUT carry.
const snapshot = () => ({
  movie: normalize(defaults.movie),
  show: normalize(defaults.show),
  searchSources: [...searchSources.value],
})

function loadLocal() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY))
    if (raw?.movie?.type && raw?.show?.type) {
      defaults.movie = normalize(raw.movie)
      defaults.show = normalize(raw.show)
      if (raw.searchSources) searchSources.value = normalizeSources(raw.searchSources)
    }
  } catch {
    // keep defaults
  }
}
loadLocal()

// JSON of what the server already has (or a pending save) — lets the persist
// watcher skip a redundant PUT, including the no-op change hydration triggers.
let lastSaved = null
let saveTimer = null
// Set once the user edits a setting, so a slow server hydrate can't clobber a
// choice they just made.
let touched = false

// One watch covers both openDefaults and the search sources (snapshot() reads
// both), so any change schedules a single combined save.
watch(
  () => JSON.stringify(snapshot()),
  (json) => {
    localStorage.setItem(KEY, json)
    if (json === lastSaved) return
    lastSaved = json
    clearTimeout(saveTimer)
    saveTimer = setTimeout(() => saveSettings(JSON.parse(json)).catch(() => {}), 400)
  }
)

// Pull the persisted settings once, behind AuthGuard so the session cookie is
// present. If the user has nothing stored yet, migrate their current (local or
// default) prefs up so an existing user's choices aren't lost.
let hydrated = false
async function hydrate() {
  if (hydrated) return
  hydrated = true
  try {
    const { openDefaults, searchSources: sources } = await getSettings()
    if (touched) return
    if (sources) searchSources.value = normalizeSources(sources)
    if (openDefaults?.movie?.type && openDefaults?.show?.type) {
      defaults.movie = normalize(openDefaults.movie)
      defaults.show = normalize(openDefaults.show)
      lastSaved = JSON.stringify(snapshot())
    } else {
      const snap = snapshot()
      lastSaved = JSON.stringify(snap)
      saveSettings(snap).catch(() => {})
    }
  } catch {
    // Offline / unauthenticated — keep the localStorage-backed values.
  }
}

export function useOpenSettings() {
  hydrate()
  return {
    defaults,
    searchSources,
    setDefault(kind, target) {
      touched = true
      defaults[kind] = normalize(target)
    },
    // Replace the enabled-source set. TMDb (the built-in) is always kept on.
    setSearchSources(ids) {
      touched = true
      searchSources.value = normalizeSources(ids)
    },
  }
}
