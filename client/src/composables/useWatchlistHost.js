import { computed, defineComponent, h, ref } from 'vue'
import axios from 'axios'
import { useRouter } from 'vue-router'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { createItem, updateItem } from '@/api/watchlist.js'
import { hasTMDbKey, tmdb } from '@/api/tmdb.js'
import { BUILTIN_SOURCES } from '@/api/sources.js'
import { deriveStatus, showTotals } from '@/utils/progress.js'
import { personSections, pages } from '@/utils/pluginSurfaces.js'
import { itemRoute, titleRoute, pageRoute } from '@/utils/routes.js'
import { playTrailer } from '@/composables/useTrailerPlayer.js'
import { useMovieDNA } from '@/composables/useMovieDNA.js'
import { profile, traitsOf, titleKey, isFollowing } from '@/movieDNA/engine.js'

const TITLE_KEY = /^(movie|show):(\d+)$/
const apiType = (kind) => (kind === 'show' ? 'tv' : 'movie')
const jumpUrl = (i) => i.lastPage || i.playback?.url || i.watchLink || null
const hostOf = (url) => { try { return new URL(url).host.replace(/^www\./, '') } catch { return null } }
const hasProgress = (i) => !!(i.playback || i.lastPage || i.lastWatchedAt || showTotals(i).watchedEp > 0)

function nextEpisode(i) {
  const s = i.type === 'show' ? i.seasonProgress?.find((x) => x.watched < x.episodeCount) : null
  return s ? { season: s.seasonNumber, episode: s.watched + 1 } : null
}

// What a reset leaves on the item: the saved spot always goes, show scopes also unwatch episodes.
function resetPatch(item, scope) {
  const patch = { playback: null, lastPage: null, lastWatchedAt: null }
  if (item.type !== 'show' || scope === 'current') return patch
  const seasons = item.seasonProgress
  if (seasons?.length) {
    const current = seasons.findIndex((s) => s.watched < s.episodeCount)
    const i = current === -1 ? seasons.length - 1 : current
    patch.seasonProgress = seasons.map((s, n) => (scope === 'show' || n === i ? { ...s, watched: 0 } : s))
    const { totalEp, watchedEp } = showTotals({ seasonProgress: patch.seasonProgress })
    patch.status = deriveStatus(watchedEp, totalEp)
  } else if (scope === 'show') patch.status = 'planned'
  return patch
}

const isSelfRole = (role) => /^(self\b|himself|herself|themselves)|\(uncredited\) self/i.test(role)

function creditsOf(data) {
  const credit = (c, role, department) => ({
    titleID: c.id,
    kind: c.media_type === 'tv' ? 'show' : 'movie',
    title: c.title || c.name || '',
    date: c.release_date || c.first_air_date || null,
    posterURL: c.poster_path ? `https://image.tmdb.org/t/p/w342${c.poster_path}` : null,
    role,
    department,
    voteCount: c.vote_count ?? 0,
    isSelf: department === 'Acting' && isSelfRole(role),
  })
  return [
    ...(data.cast ?? []).map((c) => credit(c, c.character || '', 'Acting')),
    ...(data.crew ?? []).map((c) => credit(c, c.job || '', c.department || '')),
  ].filter((c) => c.title && (c.kind === 'movie' || c.kind === 'show'))
}

const photo = (path) => (path ? `https://image.tmdb.org/t/p/w185${path}` : null)
const CREW_RANK = ['Director', 'Creator', 'Screenplay', 'Writer', 'Novel', 'Producer', 'Executive Producer', 'Original Music Composer', 'Director of Photography', 'Editor']
const crewRank = (job) => { const i = CREW_RANK.indexOf(job); return i === -1 ? 99 : i }

// A title's cast in billing order and crew by the jobs people look for first; shows aggregate every season.
function titleCredits(data, key) {
  const credits = data[key] ?? {}
  const cast = (credits.cast ?? []).map((c) => ({
    personID: c.id,
    name: c.name,
    role: c.character ?? [...(c.roles ?? [])].sort((a, b) => (b.episode_count ?? 0) - (a.episode_count ?? 0))[0]?.character ?? '',
    department: 'Acting',
    photoURL: photo(c.profile_path),
    order: c.order ?? 999,
  }))
  const seen = new Set()
  const crew = (credits.crew ?? [])
    .map((c) => ({
      personID: c.id,
      name: c.name,
      role: c.job ?? c.jobs?.[0]?.job ?? '',
      department: c.department ?? '',
      photoURL: photo(c.profile_path),
    }))
    .filter((c) => !seen.has(`${c.personID}|${c.role}`) && seen.add(`${c.personID}|${c.role}`))
    .sort((a, b) => crewRank(a.role) - crewRank(b.role) || a.name.localeCompare(b.name))
  return { cast: cast.sort((a, b) => a.order - b.order).map(({ order, ...c }) => c), crew }
}

const creditsCache = new Map()
const personCache = new Map()

// What the app does for plugin surfaces; the contract is described in utils/pluginSurfaces.js.
export function useWatchlistHost({ items, changed = () => {} }) {
  const movieDNA = useMovieDNA()
  const router = useRouter()
  const { t } = useI18n()
  const { isPluginEnabled } = useRegistry()
  const added = ref(new Set())

  const dna = computed(() => profile(items(), movieDNA.settings.value))
  const pluginDNA = computed(() => {
    const { enabled, notInterested } = movieDNA.settings.value
    return {
      enabled,
      genres: traitsOf(dna.value, 'genre').map((t) => ({ name: t.name, strength: t.strength })),
      titles: traitsOf(dna.value, 'title').flatMap((t) => {
        const m = TITLE_KEY.exec(t.key)
        return m ? [{ kind: m[1], tmdbID: Number(m[2]), name: t.name, strength: t.strength }] : []
      }),
      people: traitsOf(dna.value, 'person').map((t) => ({
        personID: Number(t.key.slice('person:'.length)), name: t.name, strength: t.strength, followed: t.followed,
      })),
      notInterested: new Set(Object.keys(notInterested)),
    }
  })
  const library = computed(() =>
    items().map((i) => ({
      kind: i.type,
      tmdbID: i.tmdbId ?? null,
      title: i.title,
      genres: i.genres ?? [],
      rating: i.rating ?? null,
      favorite: !!i.favorite,
      isCompleted: i.status === 'completed',
      finishedAt: i.completedAt || i.updatedAt ? new Date(i.completedAt || i.updatedAt) : null,
    }))
  )
  const titles = computed(() =>
    items().map((i) => {
      const url = jumpUrl(i)
      const p = i.playback
      const watched = i.lastWatchedAt || (p ? i.updatedAt : null)
      return {
        id: i._id,
        title: i.title,
        kind: i.type,
        posterURL: i.posterUrl || null,
        isCompleted: i.status === 'completed',
        lastWatchedAt: watched ? new Date(watched) : null,
        resume: p ? { position: p.position, duration: p.duration, fraction: p.duration > 0 ? Math.min(1, Math.max(0, p.position / p.duration)) : 0 } : null,
        nextEpisode: nextEpisode(i),
        resumeHost: url ? hostOf(url) : null,
      }
    })
  )
  const byId = (id) => items().find((i) => i._id === id)
  const personPage = () => pages.find((p) => p.id === 'person' && isPluginEnabled(p.pluginId))
  const owned = computed(() => new Set(items().filter((i) => i.tmdbId).map((i) => titleKey(i.type, i.tmdbId))))

  const host = {
    get movieDNA() { return pluginDNA.value },
    get library() { return library.value },
    get titles() { return titles.value },
    get hasTMDbKey() { return hasTMDbKey.value },
    // Parsed TMDb JSON, e.g. tmdb('/trending/all/week').
    tmdb,
    inLibrary: (kind, tmdbID) => owned.value.has(titleKey(kind, tmdbID)) || added.value.has(titleKey(kind, tmdbID)),

    async addToWatchlist(kind, tmdbID) {
      const type = apiType(kind)
      const d = await tmdb(`/${type}/${tmdbID}`)
      const raw = { ...d, media_type: type }
      const form = await BUILTIN_SOURCES[0].toForm({ _raw: raw })
      await createItem({ ...form, status: 'planned' })
      added.value = new Set(added.value).add(titleKey(kind, tmdbID))
      changed()
    },

    // Opens the title's saved page (or watch link) in a new tab.
    resume(id) {
      const url = byId(id) && jumpUrl(byId(id))
      if (url && /^https?:\/\//i.test(url)) window.open(url, '_blank', 'noopener')
    },

    openItem: (id) => router.push(`/item/${id}`),

    // The ways to reset a title's progress, named for the person: [{ id, title, isDestructive }].
    resetActions(id) {
      const item = byId(id)
      if (!item || !hasProgress(item)) return []
      if (item.type !== 'show') return [{ id: 'current', title: t('watchlist.host.reset'), isDestructive: false }]
      return [
        { id: 'current', title: t('watchlist.host.resetEpisode'), isDestructive: false },
        ...(item.seasonProgress?.length ? [{ id: 'season', title: t('watchlist.host.resetSeason'), isDestructive: true }] : []),
        { id: 'show', title: t('watchlist.host.resetShow'), isDestructive: true },
      ]
    },

    // Runs one of resetActions on a title.
    async perform(id, actionId) {
      const item = byId(id)
      if (!item) return
      await updateItem(id, resetPatch(item, actionId))
      changed()
    },

    markNotInterested: (kind, tmdbID, title, genres) => movieDNA.markNotInterested(titleKey(kind, tmdbID), title, genres),

    isFollowing: (personID) => isFollowing(movieDNA.settings.value, personID),
    setFollowing: (following, personID, name, photoURL) => movieDNA.setFollowing(personID, name, photoURL, following),

    // A title's people as { cast, crew: [{ personID, name, role, department, photoURL }] }.
    credits(kind, tmdbID) {
      const key = `${kind}:${tmdbID}`
      if (!creditsCache.has(key)) {
        const credits = kind === 'show' ? 'aggregate_credits' : 'credits'
        creditsCache.set(key, tmdb(`/${apiType(kind)}/${tmdbID}`, { append_to_response: credits }).then((d) => titleCredits(d, credits)))
        creditsCache.get(key).catch(() => creditsCache.delete(key))
      }
      return creditsCache.get(key)
    },

    // A person with everything they worked on; credits: [{ titleID, kind, title, date, posterURL, role, department, voteCount, isSelf }].
    person(id) {
      if (!personCache.has(id)) {
        personCache.set(id, tmdb(`/person/${id}`, { append_to_response: 'combined_credits,external_ids' }).then((p) => ({
          id,
          name: p.name || '',
          biography: p.biography || '',
          knownFor: p.known_for_department || null,
          birthday: p.birthday || null,
          deathday: p.deathday || null,
          birthplace: p.place_of_birth || null,
          photoURL: p.profile_path ? `https://image.tmdb.org/t/p/h632${p.profile_path}` : null,
          wikidataID: p.external_ids?.wikidata_id || null,
          imdbID: p.external_ids?.imdb_id || null,
          credits: creditsOf(p.combined_credits ?? {}),
        })))
        personCache.get(id).catch(() => personCache.delete(id))
      }
      return personCache.get(id)
    },

    // Titles open in-app (the library item when it's there), people and pages through the plugin that owns them.
    open(dest) {
      if (dest.type === 'web') { if (/^https?:\/\//i.test(dest.url ?? '')) window.open(dest.url, '_blank', 'noopener') }
      else if (dest.type === 'title') {
        const item = items().find((i) => i.type === dest.kind && i.tmdbId === dest.tmdbID)
        router.push(item ? itemRoute(item._id) : titleRoute(dest.kind, dest.tmdbID))
      } else if (dest.type === 'person') {
        const page = personPage()
        if (page) router.push(pageRoute(page.pluginId, 'person', dest.id))
      } else if (dest.type === 'page') router.push(pageRoute(dest.plugin, dest.page, dest.arg ?? ''))
    },

    playTrailer: (youTubeKey) => playTrailer(youTubeKey),

    // Film and TV news from the app's server (cached there): { articles: [{ title, link, published, source, image, summary }], failed: [source names] }.
    news: (refresh = false) => axios.get('/api/watchlist/news', { params: refresh ? { refresh: 1 } : {} }).then((r) => r.data),

    personSections: defineComponent({
      props: { personId: Number, name: String },
      setup: (props) => () =>
        personSections.filter((s) => isPluginEnabled(s.pluginId)).map((s) => h(s.component, { key: s.pluginId, personID: props.personId, name: props.name, host })),
    }),
  }
  return host
}
