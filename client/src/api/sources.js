import { shallowReactive } from 'vue'
import {
  searchMulti, fetchMovieDetail, fetchTvDetail, fetchWatchProviders, buildSeasonProgress,
} from './tmdb.js'
import { genresFromTmdbDetail } from '@/utils/genres.js'

const tmdbSource = {
  id: 'tmdb',
  label: 'TMDb',

  async search(q) {
    const results = (await searchMulti(q)).slice(0, 7)
    return results.map((r) => {
      const isMovie = r.media_type === 'movie'
      const year = (isMovie ? r.release_date : r.first_air_date)?.slice(0, 4) || ''
      return {
        key: `tmdb:${r.id}`,
        title: isMovie ? r.title : r.name,
        subtitle: year,
        poster: r.poster_path ? `https://image.tmdb.org/t/p/w92${r.poster_path}` : null,
        type: isMovie ? 'movie' : 'show',
        _raw: r,
      }
    })
  },

  async toForm(result, ctx = {}) {
    const r = result._raw
    const isMovie = r.media_type === 'movie'
    const form = {
      title: isMovie ? r.title : r.name,
      type: isMovie ? 'movie' : 'show',
      year: (isMovie ? r.release_date : r.first_air_date)?.slice(0, 4) ?? '',
      posterUrl: r.poster_path ? `https://image.tmdb.org/t/p/w500${r.poster_path}` : null,
      tmdbId: r.id ?? null,
    }
    const mediaType = isMovie ? 'movie' : 'tv'
    const [d, streaming] = await Promise.all([
      isMovie ? fetchMovieDetail(r.id) : fetchTvDetail(r.id),
      fetchWatchProviders(r.id, mediaType),
    ])
    if (d.vote_average) form.tmdbRating = Math.round(d.vote_average * 10) / 10
    const genres = genresFromTmdbDetail(d)
    if (genres.length) form.genres = genres
    if (isMovie) {
      if (d.runtime) form.runtime = d.runtime
    } else {
      if (d.number_of_seasons) form.seasons = d.number_of_seasons
      if (d.number_of_episodes) form.episodes = d.number_of_episodes
      if (d.number_of_episodes && d.episode_run_time?.length) {
        form.showRuntime = d.number_of_episodes * d.episode_run_time[0]
      }
      form.seasonProgress = buildSeasonProgress(d, ctx.existing?.seasonProgress)
    }
    if (streaming) {
      form.watchLink = streaming.link ?? ''
      form.streamingProvider = streaming.name
      form.streamingLogo = streaming.logo
    }
    return form
  },
}

export const BUILTIN_SOURCES = [tmdbSource]

const manifests = import.meta.glob('../../plugins/*/nucleus.plugin.json', { eager: true, import: 'default' })
const modules = import.meta.glob('../../plugins/*/client/watchlistSources.js', { eager: true })

const dirOf = (file) => file.match(/\/plugins\/([^/]+)\//)?.[1]

function collectPluginSources() {
  const manifestByDir = {}
  for (const [file, m] of Object.entries(manifests)) manifestByDir[dirOf(file)] = m

  const sources = []
  for (const [file, mod] of Object.entries(modules)) {
    const dir = dirOf(file)
    const manifest = manifestByDir[dir]
    const targets = Array.isArray(manifest?.target) ? manifest.target : [manifest?.target]
    if (!targets.includes('watchlist')) continue
    const exported = mod?.default
    sources.push(...validSources(exported, manifest?.id || dir))
  }
  return sources
}

function validSources(exported, pluginId) {
  const list = Array.isArray(exported) ? exported : exported ? [exported] : []
  return list
    .filter((s) => s?.id && typeof s.search === 'function' && typeof s.toForm === 'function')
    .map((s) => ({ ...s, pluginId }))
}

// Reactive so that plugins installed at runtime in the iOS app (see
// plugins/runtime.js) show up in search and Settings without a reload.
export const PLUGIN_SOURCES = shallowReactive(collectPluginSources())

/** Register a runtime plugin's sources; returns the source ids it added. */
export function addRuntimeSources(pluginId, exported) {
  removeRuntimeSources(pluginId)
  const added = validSources(exported, pluginId)
  PLUGIN_SOURCES.push(...added)
  return added.map((s) => s.id)
}

export function removeRuntimeSources(pluginId) {
  for (let i = PLUGIN_SOURCES.length - 1; i >= 0; i--) {
    if (PLUGIN_SOURCES[i].pluginId === pluginId) PLUGIN_SOURCES.splice(i, 1)
  }
}
