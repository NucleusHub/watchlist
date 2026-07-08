import { reactive, watch } from 'vue'
import { getSettings, saveSettings } from '@/api/watchlist.js'

// Per-type global default for where a poster click opens a title. The server is
// the source of truth (persisted per profile, so it follows the user across
// sessions/devices); localStorage is kept purely as a no-flash cache so the
// last-known value renders instantly before the server hydrate lands. Exposed
// as a module-level reactive singleton so any component — the settings modal,
// every ItemCard — reads/writes the same live state without prop threading.
const KEY = 'watchlist-open-defaults'
const DEFAULT = () => ({ type: 'tmdb', customUrl: '', titleFormat: 'raw' })

const normalize = (t) => ({
  type: t?.type || 'tmdb',
  customUrl: t?.customUrl || '',
  titleFormat: t?.titleFormat || 'raw',
})

const snapshot = (v) => ({ movie: normalize(v.movie), show: normalize(v.show) })

function loadLocal() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY))
    if (raw?.movie?.type && raw?.show?.type) {
      return { movie: normalize(raw.movie), show: normalize(raw.show) }
    }
  } catch {
    // fall through to defaults
  }
  return { movie: DEFAULT(), show: DEFAULT() }
}

const defaults = reactive(loadLocal())

// JSON of what the server already has (or a pending save) — lets the persist
// watcher skip a redundant PUT, including the no-op change hydration triggers.
let lastSaved = null
let saveTimer = null
// Set once the user edits a default, so a slow server hydrate can't clobber a
// choice they just made.
let touched = false

watch(
  defaults,
  (v) => {
    const snap = snapshot(v)
    const json = JSON.stringify(snap)
    localStorage.setItem(KEY, json)
    if (json === lastSaved) return
    lastSaved = json
    clearTimeout(saveTimer)
    saveTimer = setTimeout(() => saveSettings(snap).catch(() => {}), 400)
  },
  { deep: true }
)

// Pull the persisted defaults once, behind AuthGuard so the session cookie is
// present. If the user has nothing stored yet, migrate their current (local or
// default) prefs up so an existing user's choices aren't lost.
let hydrated = false
async function hydrate() {
  if (hydrated) return
  hydrated = true
  try {
    const { openDefaults } = await getSettings()
    if (touched) return
    if (openDefaults?.movie?.type && openDefaults?.show?.type) {
      const server = { movie: normalize(openDefaults.movie), show: normalize(openDefaults.show) }
      lastSaved = JSON.stringify(server)
      defaults.movie = server.movie
      defaults.show = server.show
    } else {
      const snap = snapshot(defaults)
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
    setDefault(kind, target) {
      touched = true
      defaults[kind] = normalize(target)
    },
  }
}
