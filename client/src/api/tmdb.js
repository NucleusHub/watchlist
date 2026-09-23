const BASE = 'https://api.themoviedb.org/3'
// User-supplied key (Settings → Search sources) takes priority over one baked
// in at build time via VITE_TMDB_API_KEY. Read fresh per request — not cached
// at module load — so saving a key in Settings works without a reload.
export const KEY_STORAGE_KEY = 'watchlist-tmdb-api-key'

function getKey() {
  try {
    const stored = localStorage.getItem(KEY_STORAGE_KEY)
    if (stored) return stored
  } catch {
    // Storage unavailable — fall through to the build-time key.
  }
  return import.meta.env.VITE_TMDB_API_KEY || ''
}

async function get(path, params = {}) {
  const key = getKey()
  if (!key) throw new Error('No TMDb API key set — add one in Settings.')
  const url = new URL(`${BASE}${path}`)
  url.searchParams.set('api_key', key)
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v))
  const res = await fetch(url)
  if (!res.ok) throw new Error(`TMDb ${res.status}`)
  return res.json()
}

export async function searchMulti(query) {
  const data = await get('/search/multi', { query, include_adult: false })
  return (data.results || []).filter((r) => r.media_type === 'movie' || r.media_type === 'tv')
}

export async function fetchMovieDetail(id) {
  return get(`/movie/${id}`)
}

export async function fetchTvDetail(id) {
  return get(`/tv/${id}`)
}

// Priority order: Netflix, Disney+, Max, Peacock, Apple TV+, Hulu, Paramount+
const PROVIDER_PRIORITY = [8, 337, 384, 386, 350, 15, 531]

export async function fetchWatchProviders(id, type) {
  const data = await get(`/${type}/${id}/watch/providers`)
  const region = data.results?.US ?? Object.values(data.results ?? {})[0]
  if (!region) return null

  const flatrate = region.flatrate ?? []
  let provider = null
  for (const pid of PROVIDER_PRIORITY) {
    provider = flatrate.find((p) => p.provider_id === pid)
    if (provider) break
  }
  if (!provider && flatrate.length) provider = flatrate[0]
  if (!provider) return null

  return {
    link: region.link ?? null,
    name: provider.provider_name,
    logo: provider.logo_path,
  }
}

export function logoUrl(path) {
  return path ? `https://image.tmdb.org/t/p/w45${path}` : null
}

// Build a per-season progress list from a TMDb TV detail payload, excluding
// specials (season 0) and empty seasons. Carries over any already-watched
// counts from an existing list, keyed by season number, so refreshing a show
// preserves the user's progress.
export function buildSeasonProgress(detail, existing = []) {
  const prev = new Map((existing || []).map((s) => [s.seasonNumber, s.watched || 0]))
  return (detail.seasons || [])
    .filter((s) => s.season_number > 0 && s.episode_count > 0)
    .sort((a, b) => a.season_number - b.season_number)
    .map((s) => ({
      seasonNumber: s.season_number,
      name: s.name || `Season ${s.season_number}`,
      episodeCount: s.episode_count,
      watched: Math.min(prev.get(s.season_number) ?? 0, s.episode_count),
    }))
}
