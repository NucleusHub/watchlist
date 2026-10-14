import { shallowRef } from 'vue'
import { parseExtras } from '@/utils/trailers.js'

const BASE = 'https://api.themoviedb.org/3'
const BUILD_KEY = import.meta.env.VITE_TMDB_API_KEY
const STORE = 'watchlist-tmdb-key'

// The key from Settings wins over the build-time one; cached so the first screen already has it.
let userKey = ''
try { userKey = localStorage.getItem(STORE) || '' } catch {}

async function get(path, params = {}, key = userKey || BUILD_KEY) {
  if (!key) throw new Error('TMDb API key not set')
  const url = new URL(`${BASE}${path}`)
  url.searchParams.set('api_key', key)
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v))
  const res = await fetch(url)
  if (!res.ok) throw new Error(`TMDb ${res.status}`)
  return res.json()
}

// Reactive: flips when a key is saved in Settings.
export const hasTMDbKey = shallowRef(!!(userKey || BUILD_KEY))
export const tmdb = (path, params) => get(path, params)

export function setTMDbKey(key) {
  userKey = (key || '').trim()
  hasTMDbKey.value = !!(userKey || BUILD_KEY)
  try {
    if (userKey) localStorage.setItem(STORE, userKey)
    else localStorage.removeItem(STORE)
  } catch {}
}

// false when TMDb rejects the key; other failures (offline) throw so the caller can keep it anyway.
export async function verifyTMDbKey(key) {
  try {
    await get('/configuration', {}, key)
    return true
  } catch (e) {
    if (e.message === 'TMDb 401') return false
    throw e
  }
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

const extrasCache = new Map()

// Overview and trailers for a title; cached per session so going back to a title doesn't ask again.
export function fetchExtras(id, type) {
  const key = `${type}:${id}`
  if (!extrasCache.has(key)) {
    const request = get(`/${type === 'movie' ? 'movie' : 'tv'}/${id}`, { append_to_response: 'videos', include_video_language: 'en,null' })
      .then(parseExtras)
      .catch((err) => { extrasCache.delete(key); throw err })
    extrasCache.set(key, request)
  }
  return extrasCache.get(key)
}

// People matching a name, for the custom credits editor.
export async function searchPeople(query) {
  const data = await get('/search/person', { query, include_adult: false })
  return (data.results || []).slice(0, 8).map((p) => ({
    id: p.id,
    name: p.name,
    knownFor: p.known_for_department || '',
    photo: p.profile_path ? `https://image.tmdb.org/t/p/w185${p.profile_path}` : null,
  }))
}
