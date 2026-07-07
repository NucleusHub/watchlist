import { reactive, watch } from 'vue'

// Per-type global default for where a poster click opens a title. Persisted in
// localStorage (same convention as the grid-style preference) and exposed as a
// module-level reactive singleton so any component — the settings modal, every
// ItemCard — reads/writes the same live state without prop threading.
const KEY = 'watchlist-open-defaults'
const DEFAULT = () => ({ type: 'tmdb', customUrl: '', titleFormat: 'raw' })

const normalize = (t) => ({
  type: t.type,
  customUrl: t.customUrl || '',
  titleFormat: t.titleFormat || 'raw',
})

function load() {
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

const defaults = reactive(load())

watch(defaults, (v) => localStorage.setItem(KEY, JSON.stringify(v)), { deep: true })

export function useOpenSettings() {
  return {
    defaults,
    setDefault(kind, target) {
      defaults[kind] = normalize(target)
    },
  }
}
