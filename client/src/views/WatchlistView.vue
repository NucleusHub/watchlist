<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue'
import { getItems, createItem, updateItem } from '@/api/watchlist.js'
import { searchMulti, fetchMovieDetail, fetchTvDetail, fetchWatchProviders } from '@/api/tmdb.js'
import ItemCard from '@/components/ItemCard.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ConfirmModal from '@/components/ConfirmModal.vue'
import AppSidebar from '@/components/AppSidebar.vue'
import WatchlistStats from '@/components/WatchlistStats.vue'

const WARN_THRESHOLD = 10
const sidebarOpen = ref(false)
const showStats = ref(false)
const gridStyle = ref(localStorage.getItem('watchlist-grid') || 'small')
watch(gridStyle, val => localStorage.setItem('watchlist-grid', val))

const gridClass = computed(() => ({
  list:  'grid-cols-1',
  big:   'grid-cols-1 sm:grid-cols-2',
  small: 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-3',
}[gridStyle.value]))

const items = ref([])
const loading = ref(true)
const error = ref(null)
const showModal = ref(false)
const editingItem = ref(null)
const modalResetKey = ref(0)
const activeStatus = ref('planned')
const activeType = ref('all')
const sortBy = ref('alphabetical')
const sortDir = ref('asc')
const searchQuery = ref('')
const showSearch = ref(false)
const searchInput = ref(null)

// Refresh state
const showRefreshWarning = ref(false)
const refreshing = ref(false)
const refreshCurrent = ref(0)
const refreshTotal = ref(0)
const refreshDone = ref(false)
const refreshFailed = ref(0)
const refreshCancelled = ref(false)

const STATUS_TABS = [
  { key: 'all', label: 'All' },
  { key: 'planned', label: 'Planned' },
  { key: 'watching', label: 'Watching' },
  { key: 'completed', label: 'Completed' },
]

const TYPE_TABS = [
  { key: 'all', label: 'All' },
  { key: 'movie', label: 'Movies' },
  { key: 'show', label: 'Shows' },
]


function toggleSearch() {
  if (showSearch.value) {
    closeSearch()
  } else {
    showSearch.value = true
    nextTick(() => searchInput.value?.focus())
  }
}

function closeSearch() {
  searchQuery.value = ''
  showSearch.value = false
}

const SORT_DEFAULTS = { dateAdded: 'desc', dateReleased: 'desc', rating: 'desc', alphabetical: 'asc', runtime: 'desc' }

function toggleSort(key) {
  if (sortBy.value === key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
  } else {
    sortBy.value = key
    sortDir.value = SORT_DEFAULTS[key]
  }
}

const filtered = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  const base = items.value.filter((i) => {
    const statusOk = activeStatus.value === 'all' || i.status === activeStatus.value
    const typeOk = activeType.value === 'all' || i.type === activeType.value
    const searchOk = !q || i.title.toLowerCase().includes(q) || (i.notes && i.notes.toLowerCase().includes(q))
    return statusOk && typeOk && searchOk
  })
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
  return `This will fetch updated ratings and streaming info for all ${n} items from TMDb. It may take ${time}.`
})

async function load() {
  loading.value = true
  error.value = null
  try {
    items.value = await getItems()
  } catch {
    error.value = 'Failed to load watchlist. Is the server running?'
  } finally {
    loading.value = false
  }
}

async function handleSubmit(data, addAnother = false) {
  if (editingItem.value) {
    const updated = await updateItem(editingItem.value._id, data)
    items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
    closeModal()
  } else {
    const created = await createItem(data)
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
      const results = await searchMulti(item.title)
      const mediaType = item.type === 'movie' ? 'movie' : 'tv'
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

      const isMovie = match.media_type === 'movie'
      const [detail, streaming] = await Promise.all([
        isMovie ? fetchMovieDetail(match.id) : fetchTvDetail(match.id),
        fetchWatchProviders(match.id, isMovie ? 'movie' : 'tv'),
      ])

      const patch = {}

      if (detail.vote_average) patch.tmdbRating = Math.round(detail.vote_average * 10) / 10

      // Only set poster if unset or already from TMDb (don't overwrite uploads)
      if (!item.posterUrl || item.posterUrl.startsWith('https://image.tmdb.org')) {
        if (match.poster_path) patch.posterUrl = `https://image.tmdb.org/t/p/w500${match.poster_path}`
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
  <div class="min-h-screen bg-slate-100 dark:bg-slate-900 text-slate-900 dark:text-white overflow-x-hidden">
    <!-- Hamburger — fixed to viewport left -->
    <button
      @click="sidebarOpen = !sidebarOpen"
      class="cursor-pointer fixed left-4 top-[18px] z-40 flex flex-col justify-center gap-[5px] p-2 rounded-lg text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
      title="Menu"
    >
      <span class="block w-5 h-0.5 rounded-full bg-current transition-all duration-200"
            :class="sidebarOpen ? 'rotate-45 translate-y-[7px]' : ''" />
      <span class="block w-5 h-0.5 rounded-full bg-current transition-all duration-200"
            :class="sidebarOpen ? 'opacity-0 scale-x-0' : ''" />
      <span class="block w-5 h-0.5 rounded-full bg-current transition-all duration-200"
            :class="sidebarOpen ? '-rotate-45 -translate-y-[7px]' : ''" />
    </button>

    <header class="border-b border-slate-200 dark:border-slate-800 bg-white dark:bg-transparent px-4 py-4">
      <div class="max-w-4xl mx-auto flex items-center justify-between pl-10 sm:pl-0">
        <div>
          <h1 class="text-xl font-bold text-slate-900 dark:text-white">Watchlist</h1>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
            {{ stats.total }} items · {{ stats.watching }} watching · {{ stats.completed }} completed
          </p>
        </div>
        <div class="flex items-center gap-2">
          <!-- Search -->
          <div class="flex items-center">
            <input
              ref="searchInput"
              v-model="searchQuery"
              @keydown.escape="closeSearch"
              placeholder="Search…"
              autocomplete="off"
              :class="showSearch ? 'w-44 opacity-100' : 'w-0 opacity-0 pointer-events-none'"
              class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white text-sm rounded-lg pl-3 pr-2 py-1.5 placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 transition-all duration-200 ease-out"
            />
            <button
              @click="toggleSearch"
              :title="showSearch ? 'Close search' : 'Search'"
              :class="['cursor-pointer p-2 rounded-lg transition-colors', showSearch ? 'text-indigo-500 dark:text-indigo-400 hover:text-slate-900 dark:hover:text-white' : 'text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700']"
            >
              <svg v-if="!showSearch || !searchQuery" class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 15.803a7.5 7.5 0 0010.607 0z" />
              </svg>
              <svg v-else class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <button
            v-if="stats.total > 0"
            @click="showStats = !showStats"
            :title="showStats ? 'Back to list' : 'Statistics'"
            :class="['cursor-pointer p-2 rounded-lg transition-colors', showStats ? 'text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-slate-700' : 'text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700']"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z" />
            </svg>
          </button>
          <button
            v-if="stats.total > 0 && !showStats"
            @click="requestRefresh"
            :disabled="refreshing"
            title="Refresh TMDb data for all items"
            class="hidden sm:block cursor-pointer p-2 text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors disabled:opacity-40 disabled:cursor-default"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99" />
            </svg>
          </button>
          <button
            @click="openAdd"
            class="cursor-pointer flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-3 sm:px-4 py-2 rounded-lg transition-colors"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
            </svg>
            <span class="hidden sm:inline">Add</span>
          </button>
        </div>
      </div>
    </header>

    <main class="max-w-4xl mx-auto px-4 py-6 flex flex-col gap-6">
      <WatchlistStats v-if="showStats" :items="items" />
      <template v-else>
      <div class="flex flex-col gap-3">
        <div class="flex gap-1.5 flex-wrap">
          <button
            v-for="tab in STATUS_TABS"
            :key="tab.key"
            @click="activeStatus = tab.key"
            :class="[
              'cursor-pointer px-3 py-1.5 rounded-lg text-sm font-medium transition-colors',
              activeStatus === tab.key
                ? 'bg-indigo-600 text-white'
                : 'bg-slate-200 dark:bg-slate-800 text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-300 dark:hover:bg-slate-700',
            ]"
          >
            {{ tab.label }}
          </button>
        </div>

        <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div class="flex items-center gap-2">
            <div class="flex gap-1.5">
            <button
              v-for="tab in TYPE_TABS"
              :key="tab.key"
              @click="activeType = tab.key"
              :class="[
                'cursor-pointer px-3 py-1.5 rounded-lg text-sm font-medium transition-colors',
                activeType === tab.key
                  ? 'bg-slate-600 text-white'
                  : 'bg-slate-200 dark:bg-slate-800 text-slate-500 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-slate-300 dark:hover:bg-slate-700',
              ]"
            >
              {{ tab.label }}
            </button>
          </div>
            <span class="text-xs text-slate-500">
              showing {{ filtered.length }} of {{ stats.total }}
            </span>
          </div>

          <!-- Sort icons + grid/size toggle -->
          <div class="flex items-center gap-1.5">
            <!-- Desktop: column layout -->
            <div class="hidden sm:flex items-center bg-slate-200 dark:bg-slate-800 rounded-lg overflow-hidden">
              <button @click="gridStyle = 'list'" :class="['cursor-pointer p-2 transition-colors', gridStyle === 'list' ? 'text-slate-900 dark:text-white bg-white dark:bg-slate-600 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']" title="List">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M3 12h18M3 18h18" /></svg>
              </button>
              <button @click="gridStyle = 'big'" :class="['cursor-pointer p-2 transition-colors', gridStyle === 'big' ? 'text-slate-900 dark:text-white bg-white dark:bg-slate-600 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']" title="2-column grid">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 4.5h7.5v15H3v-15zm10.5 0H21v15h-7.5v-15z" /></svg>
              </button>
              <button @click="gridStyle = 'small'" :class="['cursor-pointer p-2 transition-colors', gridStyle === 'small' ? 'text-slate-900 dark:text-white bg-white dark:bg-slate-600 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']" title="3-column grid">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 4.5h4.5v15H3v-15zm6.75 0h4.5v15h-4.5v-15zm6.75 0H21v15h-4.5v-15z" /></svg>
              </button>
            </div>
            <!-- Mobile: card size -->
            <div class="flex sm:hidden items-center bg-slate-200 dark:bg-slate-800 rounded-lg overflow-hidden">
              <button @click="gridStyle = 'list'"  :class="['cursor-pointer px-2.5 py-2 text-xs font-medium transition-colors', gridStyle === 'list'  ? 'text-slate-900 dark:text-white bg-white dark:bg-slate-600 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">S</button>
              <button @click="gridStyle = 'small'" :class="['cursor-pointer px-2.5 py-2 text-xs font-medium transition-colors', gridStyle === 'small' ? 'text-slate-900 dark:text-white bg-white dark:bg-slate-600 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">M</button>
              <button @click="gridStyle = 'big'"   :class="['cursor-pointer px-2.5 py-2 text-xs font-medium transition-colors', gridStyle === 'big'   ? 'text-slate-900 dark:text-white bg-white dark:bg-slate-600 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">L</button>
            </div>
          <div class="flex items-center gap-0.5">
            <!-- Runtime: film -->
            <button
              @click="toggleSort('runtime')"
              :title="'Runtime ' + (sortBy === 'runtime' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
              :class="['cursor-pointer relative p-2 rounded-lg transition-colors flex flex-col items-center gap-px', sortBy === 'runtime' ? 'text-indigo-600 dark:text-indigo-400 bg-slate-200 dark:bg-slate-800' : 'text-slate-400 dark:text-slate-600 hover:text-slate-700 dark:hover:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800']"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9a2.25 2.25 0 00-2.25-2.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z" />
              </svg>
              <svg v-if="sortBy === 'runtime'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" />
              </svg>
              <div v-else class="w-2.5 h-2.5" />
            </button>

            <!-- Date added: clock -->
            <button
              @click="toggleSort('dateAdded')"
              :title="'Date added ' + (sortBy === 'dateAdded' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
              :class="['cursor-pointer relative p-2 rounded-lg transition-colors flex flex-col items-center gap-px', sortBy === 'dateAdded' ? 'text-indigo-600 dark:text-indigo-400 bg-slate-200 dark:bg-slate-800' : 'text-slate-400 dark:text-slate-600 hover:text-slate-700 dark:hover:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800']"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <svg v-if="sortBy === 'dateAdded'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" />
              </svg>
              <div v-else class="w-2.5 h-2.5" />
            </button>

            <!-- Date released: calendar -->
            <button
              @click="toggleSort('dateReleased')"
              :title="'Release year ' + (sortBy === 'dateReleased' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
              :class="['cursor-pointer relative p-2 rounded-lg transition-colors flex flex-col items-center gap-px', sortBy === 'dateReleased' ? 'text-indigo-600 dark:text-indigo-400 bg-slate-200 dark:bg-slate-800' : 'text-slate-400 dark:text-slate-600 hover:text-slate-700 dark:hover:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800']"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 9v7.5" />
              </svg>
              <svg v-if="sortBy === 'dateReleased'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" />
              </svg>
              <div v-else class="w-2.5 h-2.5" />
            </button>

            <!-- Rating: star -->
            <button
              @click="toggleSort('rating')"
              :title="'Rating ' + (sortBy === 'rating' ? (sortDir === 'asc' ? '↑' : '↓') : '')"
              :class="['cursor-pointer relative p-2 rounded-lg transition-colors flex flex-col items-center gap-px', sortBy === 'rating' ? 'text-indigo-600 dark:text-indigo-400 bg-slate-200 dark:bg-slate-800' : 'text-slate-400 dark:text-slate-600 hover:text-slate-700 dark:hover:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800']"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.563.563 0 00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.562.562 0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z" />
              </svg>
              <svg v-if="sortBy === 'rating'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" />
              </svg>
              <div v-else class="w-2.5 h-2.5" />
            </button>

            <!-- Alphabetical: A↕Z bars -->
            <button
              @click="toggleSort('alphabetical')"
              :title="'Alphabetical ' + (sortBy === 'alphabetical' ? (sortDir === 'asc' ? 'A→Z' : 'Z→A') : '')"
              :class="['cursor-pointer relative p-2 rounded-lg transition-colors flex flex-col items-center gap-px', sortBy === 'alphabetical' ? 'text-indigo-600 dark:text-indigo-400 bg-slate-200 dark:bg-slate-800' : 'text-slate-400 dark:text-slate-600 hover:text-slate-700 dark:hover:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800']"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h10.5m-10.5 5.25h6" />
              </svg>
              <svg v-if="sortBy === 'alphabetical'" class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="sortDir === 'asc' ? 'M4.5 15.75l7.5-7.5 7.5 7.5' : 'M19.5 8.25l-7.5 7.5-7.5-7.5'" />
              </svg>
              <div v-else class="w-2.5 h-2.5" />
            </button>

          </div>
          </div>
        </div>
      </div>

      <div v-if="loading" class="text-center py-16 text-slate-400 dark:text-slate-500">Loading...</div>

      <div v-else-if="error" class="text-center py-16">
        <p class="text-red-400 text-sm">{{ error }}</p>
        <button @click="load" class="cursor-pointer mt-3 text-sm text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white underline">Retry</button>
      </div>

      <div v-else-if="filtered.length === 0" class="grid gap-3" :class="gridClass">
        <button
          @click="openAdd"
          class="cursor-pointer min-h-36 rounded-xl border-2 border-dashed border-slate-300 dark:border-slate-700 hover:border-indigo-500 hover:bg-slate-100/50 dark:hover:bg-slate-800/50 text-slate-400 dark:text-slate-600 hover:text-indigo-500 dark:hover:text-indigo-400 transition-all flex items-center justify-center"
        >
          <svg class="w-8 h-8" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>

      <div v-else class="grid gap-3" :class="gridClass">
        <ItemCard
          v-for="item in filtered"
          :key="item._id"
          :item="item"
          :grid-style="gridStyle"
          @updated="handleUpdated"
          @deleted="handleDeleted"
          @edit="openEdit"
        />
        <button
          @click="openAdd"
          class="cursor-pointer min-h-36 rounded-xl border-2 border-dashed border-slate-300 dark:border-slate-700 hover:border-indigo-500 hover:bg-slate-100/50 dark:hover:bg-slate-800/50 text-slate-400 dark:text-slate-600 hover:text-indigo-500 dark:hover:text-indigo-400 transition-all flex items-center justify-center"
        >
          <svg class="w-8 h-8" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>
      </template>
    </main>

    <AppSidebar :open="sidebarOpen" @close="sidebarOpen = false" />

    <ItemFormModal
      :show="showModal"
      :initial="editingItem"
      :reset-key="modalResetKey"
      @close="closeModal"
      @submit="handleSubmit"
    />

    <!-- Refresh warning -->
    <ConfirmModal
      :show="showRefreshWarning"
      title="Refresh all items from TMDb?"
      :message="refreshWarningMessage"
      confirm-label="Refresh"
      @confirm="runRefresh"
      @cancel="showRefreshWarning = false"
    />

    <!-- Refresh progress modal -->
    <Teleport to="body">
      <Transition name="fade">
        <div v-if="refreshing" class="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" />
          <div class="relative bg-white dark:bg-slate-800 rounded-2xl shadow-2xl w-full max-w-sm p-6 flex flex-col gap-5">
            <div>
              <h2 class="text-base font-semibold text-slate-900 dark:text-white">
                {{ refreshDone ? (refreshCancelled ? 'Cancelled' : 'Done!') : 'Refreshing from TMDb…' }}
              </h2>
              <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">
                <template v-if="refreshDone">
                  Updated {{ refreshCurrent - refreshFailed }} of {{ refreshTotal }} items.
                  <span v-if="refreshFailed > 0" class="text-slate-500"> ({{ refreshFailed }} not found on TMDb)</span>
                </template>
                <template v-else>
                  {{ refreshCurrent }} / {{ refreshTotal }} items
                </template>
              </p>
            </div>

            <!-- Progress bar -->
            <div class="h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
              <div
                class="h-full bg-indigo-500 rounded-full transition-all duration-300"
                :style="{ width: `${refreshProgress}%` }"
              />
            </div>

            <div class="flex justify-end">
              <button
                v-if="refreshDone"
                @click="closeRefreshModal"
                class="cursor-pointer px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-lg transition-colors"
              >
                Close
              </button>
              <button
                v-else
                @click="refreshCancelled = true"
                class="cursor-pointer px-4 py-2 text-sm font-medium text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.15s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
