import { reactive, ref, watch } from 'vue'
import { getSettings, saveSettings } from '@/api/watchlist.js'
import { PLACEMENTS } from '@/utils/pluginSurfaces.js'

const KEY = 'watchlist-settings'
const DEFAULT = () => ({ type: 'tmdb', customUrl: '', titleFormat: 'raw' })
const BUILTIN_SOURCE = 'tmdb'

const normalize = (t) => ({
  type: t?.type || 'tmdb',
  customUrl: t?.customUrl || '',
  titleFormat: t?.titleFormat || 'raw',
})

const normalizeSources = (arr) => {
  const ids = Array.isArray(arr) ? arr.filter((s) => typeof s === 'string' && s) : []
  return [...new Set([BUILTIN_SOURCE, ...ids])]
}

const normalizePlacements = (obj) => {
  const out = {}
  for (const [id, where] of Object.entries(obj ?? {})) {
    if (PLACEMENTS.includes(where)) out[id] = where
  }
  return out
}

const defaults = reactive({ movie: DEFAULT(), show: DEFAULT() })
const searchSources = ref([BUILTIN_SOURCE])
const pluginPlacements = ref({})

const snapshot = () => ({
  movie: normalize(defaults.movie),
  show: normalize(defaults.show),
  searchSources: [...searchSources.value],
  pluginPlacements: { ...pluginPlacements.value },
})

function loadLocal() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY))
    if (raw?.movie?.type && raw?.show?.type) {
      defaults.movie = normalize(raw.movie)
      defaults.show = normalize(raw.show)
      if (raw.searchSources) searchSources.value = normalizeSources(raw.searchSources)
      if (raw.pluginPlacements) pluginPlacements.value = normalizePlacements(raw.pluginPlacements)
    }
  } catch {
  }
}
loadLocal()

let lastSaved = null
let saveTimer = null
let touched = false

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

let hydrated = false
async function hydrate() {
  if (hydrated) return
  hydrated = true
  try {
    const { openDefaults, searchSources: sources, pluginPlacements: placements } = await getSettings()
    if (touched) return
    if (sources) searchSources.value = normalizeSources(sources)
    if (placements) pluginPlacements.value = normalizePlacements(placements)
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
  }
}

export function reloadOpenSettings() {
  hydrated = false
  touched = false
  return hydrate()
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
    setSearchSources(ids) {
      touched = true
      searchSources.value = normalizeSources(ids)
    },
    pluginPlacements,
    placementOf(surface) {
      const chosen = pluginPlacements.value[surface.pluginId]
      if (chosen === 'hidden') return 'hidden'
      if (chosen && surface.placements.includes(chosen)) return chosen
      return surface.defaultPlacement
    },
    setPlacement(pluginId, where) {
      if (!PLACEMENTS.includes(where)) return
      touched = true
      pluginPlacements.value = { ...pluginPlacements.value, [pluginId]: where }
    },
  }
}
