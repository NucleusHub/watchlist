import { reactive } from 'vue'
import { updateItem } from '@/api/watchlist.js'
import { searchMulti, fetchMovieDetail, fetchTvDetail, fetchWatchProviders, buildSeasonProgress } from '@/api/tmdb.js'
import { genresFromTmdbDetail } from '@/utils/genres.js'

// "Refresh details from TMDb" (Settings → Data): fills in what's missing, one title at a time.
const state = reactive({ running: false, finished: false, cancelled: false, done: 0, total: 0, failed: 0 })

async function refreshOne(item) {
  const isMovie = item.type === 'movie'
  const mediaType = isMovie ? 'movie' : 'tv'

  let tmdbId = item.tmdbId
  let posterPath = null
  if (!tmdbId) {
    const candidates = (await searchMulti(item.title)).filter((r) => r.media_type === mediaType)
    if (!candidates.length) return null
    const match = (item.year && candidates.find((r) => (r.release_date || r.first_air_date)?.slice(0, 4) === String(item.year))) || candidates[0]
    tmdbId = match.id
    posterPath = match.poster_path
  }

  const [detail, streaming] = await Promise.all([
    isMovie ? fetchMovieDetail(tmdbId) : fetchTvDetail(tmdbId),
    fetchWatchProviders(tmdbId, mediaType),
  ])

  const patch = {}
  if (!item.tmdbId) patch.tmdbId = tmdbId
  if (detail.vote_average) patch.tmdbRating = Math.round(detail.vote_average * 10) / 10
  // Don't overwrite uploaded posters.
  if (!item.posterUrl || item.posterUrl.startsWith('https://image.tmdb.org')) {
    const poster = posterPath ?? detail.poster_path
    if (poster) patch.posterUrl = `https://image.tmdb.org/t/p/w500${poster}`
  }
  // Blank-fill only, so hand-edited genres survive a refresh.
  if (!item.genres?.length) {
    const genres = genresFromTmdbDetail(detail)
    if (genres.length) patch.genres = genres
  }
  if (!item.year && detail.release_date) patch.year = Number(detail.release_date.slice(0, 4))
  if (!item.year && detail.first_air_date) patch.year = Number(detail.first_air_date.slice(0, 4))
  if (isMovie && !item.runtime && detail.runtime) patch.runtime = detail.runtime
  if (!isMovie) {
    if (!item.seasons && detail.number_of_seasons) patch.seasons = detail.number_of_seasons
    if (!item.episodes && detail.number_of_episodes) patch.episodes = detail.number_of_episodes
    if (!item.showRuntime && detail.number_of_episodes && detail.episode_run_time?.length) {
      patch.showRuntime = detail.number_of_episodes * detail.episode_run_time[0]
    }
    const sp = buildSeasonProgress(detail, item.seasonProgress)
    if (sp.length) patch.seasonProgress = sp
  }
  if (streaming) {
    patch.watchLink = streaming.link
    patch.streamingProvider = streaming.name
    patch.streamingLogo = streaming.logo
  }
  return Object.keys(patch).length ? updateItem(item._id, patch) : item
}

async function run(items) {
  Object.assign(state, { running: true, finished: false, cancelled: false, done: 0, total: items.length, failed: 0 })
  for (const item of items) {
    if (state.cancelled) break
    try {
      if (!(await refreshOne(item))) state.failed++
    } catch {
      state.failed++
    }
    state.done++
    await new Promise((r) => setTimeout(r, 300))
  }
  state.running = false
  state.finished = true
}

export function useMetadataRefresh() {
  return {
    state,
    run,
    cancel: () => { state.cancelled = true },
    close: () => { state.finished = false },
  }
}
