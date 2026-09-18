<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { getItems, createItem, updateItem } from '@/api/watchlist.js'
import { searchMulti, fetchMovieDetail, fetchTvDetail, fetchWatchProviders, buildSeasonProgress } from '@/api/tmdb.js'
import { genreFacets, genresFromTmdbDetail, hasGenre, genrePillClass } from '@/utils/genres.js'
import { watchlistSurfaces } from '@/utils/pluginSurfaces.js'
import ItemCard from '@/components/ItemCard.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ManageCollectionsModal from '@/components/ManageCollectionsModal.vue'
import WatchlistNav from '@/components/WatchlistNav.vue'
import TemplateModal from '@core/TemplateModal.vue'
import AppHeader from '@core/AppHeader.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import WatchlistStats from '@/components/WatchlistStats.vue'
import SettingsButton from '@/components/SettingsButton.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { Icon } from '@core/icons'
import VideoCameraIcon from '@/assets/icons/video-camera.svg?component'
import ClockAltIcon from '@/assets/icons/clock-alt.svg?component'
import CalendarIcon from '@/assets/icons/calendar.svg?component'
import StarOutlineIcon from '@/assets/icons/star-outline.svg?component'
import SortIcon from '@/assets/icons/sort.svg?component'
import ListIcon from '@/assets/icons/list.svg?component'
import ViewColumns2Icon from '@/assets/icons/view-columns-2.svg?component'
import ViewColumns3Icon from '@/assets/icons/view-columns-3.svg?component'

const { t } = useI18n()
const { applyMembership } = useCollections()
const { isPluginEnabled } = useRegistry()
const { placementOf } = useOpenSettings()

// Plugin surfaces the user has placed as a section on this page rather than as
// their own tab (see utils/pluginSurfaces.js). They render above the filter bar,
// get the already-loaded items, and can ask for a reload when they change one.
const panelSurfaces = computed(() =>
  watchlistSurfaces.filter((s) => isPluginEnabled(s.pluginId) && placementOf(s) === 'panel')
)

const WARN_THRESHOLD = 10
const showStats = ref(false)
const gridStyle = ref(localStorage.getItem('watchlist-grid') || 'small')
watch(gridStyle, val => localStorage.setItem('watchlist-grid', val))

const gridClass = computed(() => ({
  list:  'grid-cols-1',
  // Keep the three view modes distinct on phones too: big starts at 2-up, small
  // at 3-up (below sm both used to collapse to 2 columns, so "small" did nothing).
  big:   'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4',
  small: 'grid-cols-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5',
}[gridStyle.value]))

const items = ref([])
const loading = ref(true)
const error = ref(null)
const showModal = ref(false)
const editingItem = ref(null)
const modalResetKey = ref(0)
const showManage = ref(false)
const managingItem = ref(null)
const activeStatus = ref('planned')
const activeType = ref('all')
const onlyFavorite = ref(false)
const sortBy = ref('alphabetical')
const sortDir = ref('asc')
const searchQuery = ref('')
// Genre filter — the selected genre names, matched as "any of" rather than
// "all of": picking Action and Comedy widens the list instead of narrowing it
// to the rare item tagged both, which is what browsing a library wants.
const activeGenres = ref([])

// Refresh state
const showRefreshWarning = ref(false)
const refreshing = ref(false)
const refreshCurrent = ref(0)
const refreshTotal = ref(0)
const refreshDone = ref(false)
const refreshFailed = ref(0)
const refreshCancelled = ref(false)

const STATUS_TABS = computed(() => [
  { key: 'all', label: t('watchlist.status.all') },
  { key: 'planned', label: t('watchlist.status.planned') },
  { key: 'watching', label: t('watchlist.status.watching') },
  { key: 'completed', label: t('watchlist.status.completed') },
])

const TYPE_TABS = computed(() => [
  { key: 'all', label: t('watchlist.type.all') },
  { key: 'movie', label: t('watchlist.type.movies') },
  { key: 'show', label: t('watchlist.type.shows') },
])



const SORT_DEFAULTS = { dateAdded: 'desc', dateReleased: 'desc', rating: 'desc', alphabetical: 'asc', runtime: 'desc' }

function toggleSort(key) {
  if (sortBy.value === key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
  } else {
    sortBy.value = key
    sortDir.value = SORT_DEFAULTS[key]
  }
}

// Everything the filter bar does EXCEPT the genre picker. Split out so the
// genre chips can be faceted against it: each chip's count reflects the list
// you're currently looking at, and picking one genre doesn't make the others
// look empty.
const preGenre = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  return items.value.filter((i) => {
    const statusOk = activeStatus.value === 'all' || i.status === activeStatus.value
    const typeOk = activeType.value === 'all' || i.type === activeType.value
    const favOk = !onlyFavorite.value || i.favorite
    const searchOk = !q || i.title.toLowerCase().includes(q) || (i.notes && i.notes.toLowerCase().includes(q))
    return statusOk && typeOk && favOk && searchOk
  })
})

const genreOptions = computed(() => genreFacets(preGenre.value))

function toggleGenre(name) {
  const key = name.toLowerCase()
  const next = activeGenres.value.filter((g) => g.toLowerCase() !== key)
  if (next.length === activeGenres.value.length) next.push(name)
  activeGenres.value = next
}

const isGenreOn = (name) => activeGenres.value.some((g) => g.toLowerCase() === name.toLowerCase())

// Drop selections that no longer exist in the current facet set — otherwise
// switching to Movies while "Talk" (a show-only genre) is picked leaves an
// invisible filter showing zero results with no chip to un-click.
watch(genreOptions, (opts) => {
  if (!activeGenres.value.length) return
  const available = new Set(opts.map((o) => o.name.toLowerCase()))
  const kept = activeGenres.value.filter((g) => available.has(g.toLowerCase()))
  if (kept.length !== activeGenres.value.length) activeGenres.value = kept
})

const filtered = computed(() => {
  const base = activeGenres.value.length
    ? preGenre.value.filter((i) => activeGenres.value.some((g) => hasGenre(i, g)))
    : preGenre.value
  const dir = sortDir.value === 'asc' ? 1 : -1
  return [...base].sort((a, b) => {
    switch (sortBy.value) {
      case 'dateAdded':
        return (new Date(a.dateAdded) - new Date(b.dateAdded)) * dir
      case 'dateReleased':
        return ((a.year ?? 0) - (b.year ?? 0)) * dir
      case 'rating':
        return ((a.rating ?? a.tmdbRating ?? 0) - (b.rating ?? b.tmdbRating ?? 0)) * dir
      case 'alphabetical':
        return a.title.localeCompare(b.title) * dir
      case 'runtime': {
        const aRt = a.type === 'movie' ? (a.runtime ?? 0) : (a.showRuntime ?? 0)
        const bRt = b.type === 'movie' ? (b.runtime ?? 0) : (b.showRuntime ?? 0)
        return (aRt - bRt) * dir
      }
      default:
        return 0
    }
  })
})

const stats = computed(() => ({
  total: items.value.length,
  completed: items.value.filter((i) => i.status === 'completed').length,
  watching: items.value.filter((i) => i.status === 'watching').length,
}))

const refreshWarningMessage = computed(() => {
  const n = items.value.length
  const secs = Math.round(n * 0.8)
  const time = secs >= 60 ? `~${Math.round(secs / 60)} min` : `~${secs}s`
  return t('watchlist.refresh.warningMessage', { count: n, time })
})

async function load() {
  loading.value = true
  error.value = null
  try {
    items.value = await getItems()
  } catch {
    error.value = t('watchlist.state.loadError')
  } finally {
    loading.value = false
  }
}

async function handleSubmit(data, addAnother = false) {
  if (editingItem.value) {
    const prev = editingItem.value.collectionIds || []
    const updated = await updateItem(editingItem.value._id, data)
    applyMembership(prev, updated.collectionIds || [])
    items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
    closeModal()
  } else {
    const created = await createItem(data)
    applyMembership([], created.collectionIds || [])
    items.value.unshift(created)
    if (addAnother) {
      modalResetKey.value++
    } else {
      closeModal()
    }
  }
}

function openAdd() {
  editingItem.value = null
  showModal.value = true
}

function openEdit(item) {
  editingItem.value = item
  showModal.value = true
}

function closeModal() {
  showModal.value = false
  editingItem.value = null
}

function handleUpdated(updated) {
  items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
}

function openManage(item) {
  managingItem.value = item
  showManage.value = true
}

function handleDeleted(id) {
  items.value = items.value.filter((i) => i._id !== id)
}

function requestRefresh() {
  if (items.value.length === 0) return
  if (items.value.length > WARN_THRESHOLD) {
    showRefreshWarning.value = true
  } else {
    runRefresh()
  }
}

async function runRefresh() {
  showRefreshWarning.value = false
  refreshing.value = true
  refreshDone.value = false
  refreshFailed.value = 0
  refreshCancelled.value = false
  refreshCurrent.value = 0
  refreshTotal.value = items.value.length

  for (const item of items.value) {
    if (refreshCancelled.value) break

    try {
      const isMovie = item.type === 'movie'
      const mediaType = isMovie ? 'movie' : 'tv'

      // Prefer the stored TMDb id: an exact handle on the same title, where a
      // title search can hand back a remake or a same-named show. Items added
      // before ids were stored (or from a non-TMDb source) still search by
      // name, and we write the resolved id back so the next pass is exact.
      let tmdbId = item.tmdbId
      let posterPath = null
      if (!tmdbId) {
        const results = await searchMulti(item.title)
        const candidates = results.filter((r) => r.media_type === mediaType)

        if (candidates.length === 0) {
          refreshFailed.value++
          refreshCurrent.value++
          continue
        }

        // Prefer year match if available
        let match = candidates[0]
        if (item.year) {
          const exact = candidates.find(
            (r) => (r.release_date || r.first_air_date)?.slice(0, 4) === String(item.year)
          )
          if (exact) match = exact
        }
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

      // Only set poster if unset or already from TMDb (don't overwrite uploads)
      if (!item.posterUrl || item.posterUrl.startsWith('https://image.tmdb.org')) {
        const poster = posterPath ?? detail.poster_path
        if (poster) patch.posterUrl = `https://image.tmdb.org/t/p/w500${poster}`
      }

      // Genres — the backfill path for every item added before genre tags
      // existed. Treated as blank-fill, not an overwrite, so a genre you added
      // or removed by hand in the edit form survives a refresh.
      if (!item.genres?.length) {
        const genres = genresFromTmdbDetail(detail)
        if (genres.length) patch.genres = genres
      }

      // Only fill blank metadata fields
      if (!item.year && detail.release_date) patch.year = Number(detail.release_date.slice(0, 4))
      if (!item.year && detail.first_air_date) patch.year = Number(detail.first_air_date.slice(0, 4))
      if (isMovie && !item.runtime && detail.runtime) patch.runtime = detail.runtime
      if (!isMovie) {
        if (!item.seasons && detail.number_of_seasons) patch.seasons = detail.number_of_seasons
        if (!item.episodes && detail.number_of_episodes) patch.episodes = detail.number_of_episodes
        if (!item.showRuntime && detail.number_of_episodes && detail.episode_run_time?.length) {
          patch.showRuntime = detail.number_of_episodes * detail.episode_run_time[0]
        }
        // Refresh the per-season structure (new seasons air over time) while
        // preserving watched counts by season number.
        const sp = buildSeasonProgress(detail, item.seasonProgress)
        if (sp.length) patch.seasonProgress = sp
      }

      // Always refresh streaming (it changes)
      if (streaming) {
        patch.watchLink = streaming.link
        patch.streamingProvider = streaming.name
        patch.streamingLogo = streaming.logo
      }

      if (Object.keys(patch).length > 0) {
        const updated = await updateItem(item._id, patch)
        items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
      }
    } catch {
      refreshFailed.value++
    }

    refreshCurrent.value++
    await new Promise((r) => setTimeout(r, 300))
  }

  refreshDone.value = true
}

function closeRefreshModal() {
  refreshing.value = false
  refreshDone.value = false
}

const refreshProgress = computed(() =>
  refreshTotal.value > 0 ? (refreshCurrent.value / refreshTotal.value) * 100 : 0
)

onMounted(load)
</script>

<template>
  <div class="relative min-h-screen bg-slate-100 dark:bg-[#0d0d1a] text-slate-900 dark:text-white overflow-x-hidden">
    <BackgroundBlobs />
    <div class="relative z-10">
    <AppHeader>
      <template #left>
        <!-- Search -->
        <div class="relative">
          <Icon name="search" class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 dark:text-slate-500 pointer-events-none" />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="t('watchlist.header.search')"
            autocomplete="off"
            class="w-32 sm:w-48 pl-9 pr-3 py-1.5 text-sm bg-black/5 dark:bg-white/8 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-slate-500 rounded-lg border border-transparent focus:border-indigo-500/50 focus:outline-none focus:bg-white dark:focus:bg-white/12 transition-all duration-200"
          />
          <button
            v-if="searchQuery"
            @click="searchQuery = ''"
            class="cursor-pointer absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
          >
            <Icon name="close" class="w-3.5 h-3.5" :sw="2.5" />
          </button>
        </div>
      </template>

      <template #right>
        <button
          v-if="stats.total > 0"
          @click="showStats = !showStats"
          :title="showStats ? t('watchlist.header.backToList') : t('watchlist.header.statistics')"
          :class="['cursor-pointer p-2 rounded-lg transition-colors', showStats ? 'text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-slate-700' : 'text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700']"
        >
          <Icon name="stats" class="w-4 h-4" />
        </button>
        <SettingsButton />
        <button
          v-if="stats.total > 0 && !showStats"
          @click="requestRefresh"
          :disabled="refreshing"
          :title="t('watchlist.header.refresh')"
          class="hidden sm:block cursor-pointer p-2 text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors disabled:opacity-40 disabled:cursor-default"
        >
          <Icon name="refresh" class="w-4 h-4" />
        </button>
        <button
          @click="openAdd"
          class="group nuc-press cursor-pointer flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-3 sm:px-4 py-2 rounded-lg transition-colors"
        >
          <Icon name="plus" class="w-4 h-4 nuc-pop" :sw="2.5" />
          <span class="hidden sm:inline">{{ t('watchlist.header.add') }}</span>
        </button>
      </template>
    </AppHeader>

    <main class="max-w-4xl mx-auto px-4 py-6 flex flex-col gap-6">
      <p class="text-xs text-slate-500 dark:text-slate-400">
        {{ t('watchlist.header.stats', { total: stats.total, watching: stats.watching, completed: stats.completed }) }}
      </p>

      <div class="flex justify-center">
        <WatchlistNav />
      </div>

      <WatchlistStats v-if="showStats" :items="items" />
      <template v-else>
      <component
        v-for="s in panelSurfaces"
        :key="s.pluginId"
        :is="s.component"
        :items="items"
        placement="panel"
        @changed="load"
      />

      <div class="glass rounded-2xl p-2 flex flex-col gap-2.5">
        <!-- Status segmented control + result count -->
        <div class="flex items-center gap-3">
          <div class="min-w-0 flex-1 overflow-x-auto no-scrollbar">
            <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1">
              <button
                v-for="tab in STATUS_TABS"
                :key="tab.key"
                @click="activeStatus = tab.key"
                :class="[
                  'cursor-pointer whitespace-nowrap px-3.5 py-1.5 rounded-lg text-sm font-medium transition-all',
                  activeStatus === tab.key
                    ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm'
                    : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                ]"
              >
                {{ tab.label }}
              </button>
            </div>
          </div>
          <span class="hidden sm:block shrink-0 text-xs text-slate-400 dark:text-slate-500 tabular-nums pr-1">
            {{ t('watchlist.list.showing', { shown: filtered.length, total: stats.total }) }}
          </span>
        </div>

        <div class="h-px bg-black/[0.06] dark:bg-white/8 -mx-2" />

        <!-- Type segmented (left) · sort + grid size (right) -->
        <div class="flex flex-col gap-2.5 lg:flex-row lg:items-center lg:justify-between">
          <div class="flex items-center gap-2 self-start">
            <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1">
              <button
                v-for="tab in TYPE_TABS"
                :key="tab.key"
                @click="activeType = tab.key"
                :class="[
                  'cursor-pointer whitespace-nowrap px-3.5 py-1.5 rounded-lg text-sm font-medium transition-all',
                  activeType === tab.key
                    ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm'
                    : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                ]"
              >
                {{ tab.label }}
              </button>
            </div>
            <button
              @click="onlyFavorite = !onlyFavorite"
              :title="t('watchlist.filter.favorites')"
              :class="[
                'nuc-fav nuc-press cursor-pointer inline-flex items-center gap-1.5 h-9 px-3 rounded-xl text-sm font-medium transition-colors',
                onlyFavorite
                  ? 'bg-rose-500/15 text-rose-600 dark:text-rose-400'
                  : 'bg-black/[0.04] dark:bg-white/5 text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
              ]"
            >
              <FavoriteHeart :active="onlyFavorite" class="w-4 h-4" />
              <span class="hidden sm:inline">{{ t('watchlist.filter.favorites') }}</span>
            </button>
          </div>

          <div class="flex items-center gap-1.5 shrink-0">
            <!-- Sort icons; active shows the direction caret inline -->
            <div class="flex items-center gap-0.5">
              <button
                @click="toggleSort('runtime')"
                :title="t('watchlist.sort.runtime') + ' ' + (sortBy === 'runtime' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
                :class="['cursor-pointer h-9 px-2 rounded-lg transition-colors inline-flex items-center gap-0.5', sortBy === 'runtime' ? 'text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-500/15' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8']"
              >
                <VideoCameraIcon class="w-4 h-4" />
                <svg v-if="sortBy === 'runtime'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" /></svg>
              </button>
              <button
                @click="toggleSort('dateAdded')"
                :title="t('watchlist.sort.dateAdded') + ' ' + (sortBy === 'dateAdded' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
                :class="['cursor-pointer h-9 px-2 rounded-lg transition-colors inline-flex items-center gap-0.5', sortBy === 'dateAdded' ? 'text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-500/15' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8']"
              >
                <ClockAltIcon class="w-4 h-4" />
                <svg v-if="sortBy === 'dateAdded'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" /></svg>
              </button>
              <button
                @click="toggleSort('dateReleased')"
                :title="t('watchlist.sort.dateReleased') + ' ' + (sortBy === 'dateReleased' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
                :class="['cursor-pointer h-9 px-2 rounded-lg transition-colors inline-flex items-center gap-0.5', sortBy === 'dateReleased' ? 'text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-500/15' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8']"
              >
                <CalendarIcon class="w-4 h-4" />
                <svg v-if="sortBy === 'dateReleased'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" /></svg>
              </button>
              <button
                @click="toggleSort('rating')"
                :title="t('watchlist.sort.rating') + ' ' + (sortBy === 'rating' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
                :class="['cursor-pointer h-9 px-2 rounded-lg transition-colors inline-flex items-center gap-0.5', sortBy === 'rating' ? 'text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-500/15' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8']"
              >
                <StarOutlineIcon class="w-4 h-4" />
                <svg v-if="sortBy === 'rating'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" /></svg>
              </button>
              <button
                @click="toggleSort('alphabetical')"
                :title="t('watchlist.sort.alphabetical') + ' ' + (sortBy === 'alphabetical' ? (sortDir === 'asc' ? 'A→Z' : 'Z→A') : '')"
                :class="['cursor-pointer h-9 px-2 rounded-lg transition-colors inline-flex items-center gap-0.5', sortBy === 'alphabetical' ? 'text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-500/15' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8']"
              >
                <SortIcon class="w-4 h-4" />
                <svg v-if="sortBy === 'alphabetical'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" /></svg>
              </button>
            </div>

            <!-- Grid size (segmented) -->
            <div class="flex items-center h-9 bg-black/[0.05] dark:bg-white/5 rounded-lg p-1 gap-0.5">
              <button @click="gridStyle = 'list'" :title="t('watchlist.list.viewList')" :class="['cursor-pointer h-full px-2.5 rounded-md inline-flex items-center transition-colors', gridStyle === 'list' ? 'text-indigo-600 dark:text-white bg-white dark:bg-white/15 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">
                <ListIcon class="w-4 h-4" />
              </button>
              <button @click="gridStyle = 'big'" :title="t('watchlist.list.viewGrid2')" :class="['cursor-pointer h-full px-2.5 rounded-md inline-flex items-center transition-colors', gridStyle === 'big' ? 'text-indigo-600 dark:text-white bg-white dark:bg-white/15 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">
                <ViewColumns2Icon class="w-4 h-4" />
              </button>
              <button @click="gridStyle = 'small'" :title="t('watchlist.list.viewGrid3')" :class="['cursor-pointer h-full px-2.5 rounded-md inline-flex items-center transition-colors', gridStyle === 'small' ? 'text-indigo-600 dark:text-white bg-white dark:bg-white/15 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">
                <ViewColumns3Icon class="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>

        <!-- Genre filter — a scrollable chip strip rather than a dropdown, so
             the genres you own are visible at a glance. Only rendered once
             something in view actually carries genres (a library that predates
             genre tags, or one refreshed to nothing, shows no empty control). -->
        <template v-if="genreOptions.length">
          <div class="h-px bg-black/[0.06] dark:bg-white/8 -mx-2" />
          <div class="flex items-center gap-2">
            <div class="min-w-0 flex-1 overflow-x-auto no-scrollbar">
              <div class="inline-flex items-center gap-1.5 py-0.5">
                <button
                  v-for="g in genreOptions"
                  :key="g.name"
                  @click="toggleGenre(g.name)"
                  :class="[
                    'cursor-pointer whitespace-nowrap inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium transition-all',
                    isGenreOn(g.name)
                      ? 'ring-1 ring-inset ring-current ' + genrePillClass(g.name)
                      : 'bg-black/[0.04] dark:bg-white/5 text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                  ]"
                >
                  {{ g.name }}
                  <span class="tabular-nums opacity-60">{{ g.count }}</span>
                </button>
              </div>
            </div>
            <button
              v-if="activeGenres.length"
              @click="activeGenres = []"
              class="cursor-pointer shrink-0 text-xs text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white transition-colors pr-1"
            >
              {{ t('watchlist.filter.clearGenres') }}
            </button>
          </div>
        </template>
      </div>

      <div v-if="loading" class="text-center py-16 text-slate-400 dark:text-slate-500">{{ t('watchlist.state.loading') }}</div>

      <div v-else-if="error" class="text-center py-16">
        <p class="text-red-400 text-sm">{{ error }}</p>
        <button @click="load" class="cursor-pointer mt-3 text-sm text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white underline">{{ t('watchlist.state.retry') }}</button>
      </div>

      <div v-else-if="filtered.length === 0" class="grid gap-3" :class="gridClass">
        <button
          @click="openAdd"
          class="cursor-pointer min-h-36 rounded-xl border-2 border-dashed border-slate-300 dark:border-slate-700 hover:border-indigo-500 hover:bg-slate-100/50 dark:hover:bg-slate-800/50 text-slate-400 dark:text-slate-600 hover:text-indigo-500 dark:hover:text-indigo-400 transition-all flex items-center justify-center"
        >
          <Icon name="plus" class="w-8 h-8" :sw="1.5" />
        </button>
      </div>

      <div v-else class="grid gap-3 nuc-stagger" :class="gridClass" style="--nuc-step: 32ms">
        <ItemCard
          v-for="item in filtered"
          :key="item._id"
          :item="item"
          :grid-style="gridStyle"
          @updated="handleUpdated"
          @deleted="handleDeleted"
          @edit="openEdit"
          @manage-collections="openManage"
        />
        <button
          @click="openAdd"
          class="cursor-pointer min-h-36 rounded-xl border-2 border-dashed border-slate-300 dark:border-slate-700 hover:border-indigo-500 hover:bg-slate-100/50 dark:hover:bg-slate-800/50 text-slate-400 dark:text-slate-600 hover:text-indigo-500 dark:hover:text-indigo-400 transition-all flex items-center justify-center"
        >
          <Icon name="plus" class="w-8 h-8" :sw="1.5" />
        </button>
      </div>
      </template>
    </main>

    <ItemFormModal
      :show="showModal"
      :initial="editingItem"
      :reset-key="modalResetKey"
      @close="closeModal"
      @submit="handleSubmit"
    />


    <ManageCollectionsModal
      :show="showManage"
      :item="managingItem"
      @close="showManage = false"
      @updated="handleUpdated"
    />

    <!-- Refresh warning -->
    <TemplateModal
      :show="showRefreshWarning"
      :title="t('watchlist.refresh.warningTitle')"
      :message="refreshWarningMessage"
      :confirm-label="t('watchlist.refresh.confirm')"
      @confirm="runRefresh"
      @cancel="showRefreshWarning = false"
    />

    <!-- Refresh progress modal -->
    <TemplateModal
      :show="refreshing"
      header
      :closeable="false"
      size="sm"
      :title="refreshDone ? (refreshCancelled ? t('watchlist.refresh.cancelled') : t('watchlist.refresh.done')) : t('watchlist.refresh.running')"
      body-class="px-6 pt-4 pb-2"
    >
      <div class="flex flex-col gap-4">
        <p class="text-sm text-slate-500 dark:text-slate-400">
          <template v-if="refreshDone">
            {{ t('watchlist.refresh.updated', { done: refreshCurrent - refreshFailed, total: refreshTotal }) }}
            <span v-if="refreshFailed > 0" class="text-slate-500">{{ t('watchlist.refresh.notFound', { count: refreshFailed }) }}</span>
          </template>
          <template v-else>
            {{ t('watchlist.refresh.progress', { current: refreshCurrent, total: refreshTotal }) }}
          </template>
        </p>
        <div class="h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
          <div
            class="h-full bg-indigo-500 rounded-full transition-all duration-300"
            :style="{ width: `${refreshProgress}%` }"
          />
        </div>
      </div>
      <template #footer>
        <div class="flex justify-end w-full">
          <button
            v-if="refreshDone"
            @click="closeRefreshModal"
            class="cursor-pointer px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-lg transition-colors"
          >
            {{ t('watchlist.refresh.close') }}
          </button>
          <button
            v-else
            @click="refreshCancelled = true"
            class="cursor-pointer px-4 py-2 text-sm font-medium text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15 rounded-lg transition-colors"
          >
            {{ t('watchlist.refresh.cancel') }}
          </button>
        </div>
      </template>
    </TemplateModal>
  </div>
  </div>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.15s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
