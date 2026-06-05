<script setup>
import { ref, watch, onUnmounted, nextTick } from 'vue'
import { searchMulti, fetchMovieDetail, fetchTvDetail, fetchWatchProviders, logoUrl } from '@/api/tmdb.js'
import { uploadImage } from '@/api/watchlist.js'

const props = defineProps({
  show: { type: Boolean, default: false },
  initial: { type: Object, default: null },
  resetKey: { type: Number, default: 0 },
})
const emit = defineEmits(['close', 'submit'])

function onKeydown(e) { if (e.key === 'Escape') emit('close') }
watch(() => props.show, (val) => {
  val ? window.addEventListener('keydown', onKeydown) : window.removeEventListener('keydown', onKeydown)
})
onUnmounted(() => window.removeEventListener('keydown', onKeydown))

const form = ref({})
const results = ref([])
const showDropdown = ref(false)
const searching = ref(false)
const fetchingDetail = ref(false)
const uploading = ref(false)
const fileInput = ref(null)
const titleInput = ref(null)
const urlInput = ref(null)
const showPosterMenu = ref(false)
const showUrlInput = ref(false)
const posterUrlDraft = ref('')
let searchTimer = null

const EMPTY_FORM = () => ({
  title: '', type: 'movie', status: 'planned',
  posterUrl: null,
  tmdbRating: null,
  watchLink: '',
  streamingProvider: null,
  streamingLogo: null,
  rating: '', year: '', runtime: '',
  seasons: '', episodes: '', showRuntime: '',
  notes: '',
})

function resetForm() {
  form.value = props.initial ? { ...props.initial } : EMPTY_FORM()
  results.value = []
  showDropdown.value = false
  showPosterMenu.value = false
  showUrlInput.value = false
  posterUrlDraft.value = ''
  nextTick(() => titleInput.value?.focus())
}

function openPosterMenu() {
  showPosterMenu.value = !showPosterMenu.value
}

function pickFile() {
  showPosterMenu.value = false
  showUrlInput.value = false
  triggerUpload()
}

function pickUrl() {
  showPosterMenu.value = false
  showUrlInput.value = true
  posterUrlDraft.value = form.value.posterUrl?.startsWith('http') ? form.value.posterUrl : ''
  nextTick(() => urlInput.value?.focus())
}

function applyPosterUrl() {
  const url = posterUrlDraft.value.trim()
  if (url) form.value.posterUrl = url
  showUrlInput.value = false
}

watch(() => props.show, (val) => { if (val) resetForm() }, { immediate: true })
watch(() => props.resetKey, () => { if (props.show) resetForm() })

function onTitleInput() {
  clearTimeout(searchTimer)
  const q = form.value.title?.trim()
  if (!q || q.length < 2) {
    results.value = []
    showDropdown.value = false
    return
  }
  searchTimer = setTimeout(async () => {
    searching.value = true
    try {
      results.value = (await searchMulti(q)).slice(0, 7)
      showDropdown.value = results.value.length > 0
    } catch {
      results.value = []
      showDropdown.value = false
    } finally {
      searching.value = false
    }
  }, 300)
}

function closeDropdown() {
  setTimeout(() => { showDropdown.value = false }, 150)
}

async function selectResult(r) {
  showDropdown.value = false
  const isMovie = r.media_type === 'movie'
  form.value.title = isMovie ? r.title : r.name
  form.value.type = isMovie ? 'movie' : 'show'
  form.value.year = (isMovie ? r.release_date : r.first_air_date)?.slice(0, 4) ?? ''
  if (r.poster_path) form.value.posterUrl = `https://image.tmdb.org/t/p/w500${r.poster_path}`

  fetchingDetail.value = true
  try {
    const mediaType = isMovie ? 'movie' : 'tv'
    const [d, streaming] = await Promise.all([
      isMovie ? fetchMovieDetail(r.id) : fetchTvDetail(r.id),
      fetchWatchProviders(r.id, mediaType),
    ])

    if (d.vote_average) form.value.tmdbRating = Math.round(d.vote_average * 10) / 10

    if (isMovie) {
      if (d.runtime) form.value.runtime = d.runtime
    } else {
      if (d.number_of_seasons) form.value.seasons = d.number_of_seasons
      if (d.number_of_episodes) form.value.episodes = d.number_of_episodes
      if (d.number_of_episodes && d.episode_run_time?.length) {
        form.value.showRuntime = d.number_of_episodes * d.episode_run_time[0]
      }
    }

    if (streaming) {
      form.value.watchLink = streaming.link ?? ''
      form.value.streamingProvider = streaming.name
      form.value.streamingLogo = streaming.logo
    }
  } catch {
    // user can fill manually
  } finally {
    fetchingDetail.value = false
  }
}

function triggerUpload() {
  fileInput.value?.click()
}

async function handleFileUpload(e) {
  const file = e.target.files?.[0]
  if (!file) return
  uploading.value = true
  try {
    form.value.posterUrl = await uploadImage(file)
  } catch {
    // silent — user still has the field empty
  } finally {
    uploading.value = false
    e.target.value = ''
  }
}

function handleSubmit(addAnother = false) {
  const payload = { ...form.value }
  if (payload.type === 'movie') {
    delete payload.seasons
    delete payload.episodes
    delete payload.showRuntime
  } else {
    delete payload.runtime
  }
  for (const f of ['rating', 'year', 'runtime', 'seasons', 'episodes', 'showRuntime']) {
    if (!(f in payload)) continue
    if (payload[f] === '' || payload[f] == null) payload[f] = null
    else payload[f] = Number(payload[f])
  }
  emit('submit', payload, addAnother)
}

function resultYear(r) {
  return (r.media_type === 'movie' ? r.release_date : r.first_air_date)?.slice(0, 4)
}
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/20 backdrop-blur-xl" @click="$emit('close')" />
        <div class="relative bg-white/25 dark:bg-white/8 border border-white/50 dark:border-white/10 rounded-2xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
          <div class="p-4 sm:p-6 flex flex-col gap-5">

            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-slate-900 dark:text-white">
                {{ initial ? 'Edit item' : 'Add to watchlist' }}
              </h2>
              <button @click="$emit('close')" class="cursor-pointer text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <form @submit.prevent="handleSubmit()" class="flex flex-col gap-4 sm:flex-row sm:gap-6 items-start">

              <!-- Left: Poster -->
              <div class="w-36 sm:w-40 shrink-0 mx-auto sm:mx-0 flex flex-col gap-3">
                <label class="text-sm text-slate-500 dark:text-slate-400">Poster</label>
                <div class="relative">
                  <div
                    class="aspect-[2/3] rounded-lg overflow-hidden bg-slate-100 dark:bg-slate-700 border-2 border-dashed border-slate-300 dark:border-slate-600 flex items-center justify-center cursor-pointer hover:border-indigo-500 transition-colors"
                    @click="!form.posterUrl && triggerUpload()"
                  >
                    <img v-if="form.posterUrl" :src="form.posterUrl" class="w-full h-full object-cover" />
                    <div v-else class="flex flex-col items-center gap-2 text-slate-400 dark:text-slate-500 p-3">
                      <svg class="w-7 h-7" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3 3h18M3 21h18" />
                      </svg>
                      <span class="text-xs text-center leading-tight">Click to upload</span>
                    </div>
                  </div>
                  <div v-if="uploading" class="absolute inset-0 bg-black/60 rounded-lg flex items-center justify-center">
                    <svg class="w-5 h-5 text-white animate-spin" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                    </svg>
                  </div>
                  <div v-if="form.posterUrl && !uploading" class="absolute top-1 right-1 flex flex-col gap-1">
                    <button type="button" @click="triggerUpload" class="cursor-pointer bg-black/70 hover:bg-black/90 text-white rounded p-1 transition-colors" title="Replace">
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99" />
                      </svg>
                    </button>
                    <button type="button" @click="form.posterUrl = null" class="cursor-pointer bg-black/70 hover:bg-red-600/90 text-white rounded p-1 transition-colors" title="Remove">
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                </div>
                <!-- Poster source menu -->
                <div class="relative">
                  <button
                    type="button"
                    @click="openPosterMenu"
                    class="cursor-pointer w-full flex items-center justify-between gap-1.5 px-2.5 py-1.5 text-xs text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg transition-colors"
                  >
                    <span>Set poster</span>
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
                    </svg>
                  </button>

                  <div v-if="showPosterMenu" class="fixed inset-0 z-20" @click="showPosterMenu = false" />
                  <div
                    v-if="showPosterMenu"
                    class="absolute top-full left-0 right-0 mt-1 bg-white dark:bg-slate-700 border border-slate-200 dark:border-slate-600 rounded-lg overflow-hidden shadow-xl z-30"
                  >
                    <button
                      type="button"
                      @click="pickFile"
                      class="cursor-pointer w-full flex items-center gap-2 px-3 py-2 text-xs text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-600 transition-colors"
                    >
                      <svg class="w-3.5 h-3.5 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
                      </svg>
                      Upload file
                    </button>
                    <button
                      type="button"
                      @click="pickUrl"
                      class="cursor-pointer w-full flex items-center gap-2 px-3 py-2 text-xs text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-600 transition-colors"
                    >
                      <svg class="w-3.5 h-3.5 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244" />
                      </svg>
                      Paste URL
                    </button>
                  </div>
                </div>

                <!-- URL input -->
                <div v-if="showUrlInput" class="flex flex-col gap-1.5">
                  <input
                    ref="urlInput"
                    v-model="posterUrlDraft"
                    type="url"
                    placeholder="https://…"
                    @keydown.enter.prevent="applyPosterUrl"
                    @keydown.escape="showUrlInput = false"
                    class="w-full bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-2.5 py-1.5 text-xs placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                  <div class="flex gap-1.5">
                    <button type="button" @click="applyPosterUrl" class="cursor-pointer flex-1 text-xs bg-indigo-600 hover:bg-indigo-500 text-white rounded-md py-1 transition-colors">Apply</button>
                    <button type="button" @click="showUrlInput = false" class="cursor-pointer text-xs bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 text-slate-600 dark:text-slate-300 rounded-md px-2 py-1 transition-colors">Cancel</button>
                  </div>
                </div>
                <input ref="fileInput" type="file" accept="image/*" class="hidden" @change="handleFileUpload" />
              </div>

              <!-- Right: Fields -->
              <div class="flex-1 flex flex-col gap-4 min-w-0">

                <!-- Title with typeahead -->
                <div class="flex flex-col gap-1.5">
                  <label class="text-sm text-slate-500 dark:text-slate-400">Title</label>
                  <div class="relative">
                    <input
                      ref="titleInput"
                      v-model="form.title"
                      @input="onTitleInput"
                      @blur="closeDropdown"
                      required
                      autocomplete="off"
                      placeholder="Search or type a title…"
                      class="w-full bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 pr-8 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                    <svg v-if="searching" class="absolute right-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 animate-spin" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                    </svg>
                    <div v-if="showDropdown" class="absolute z-10 top-full left-0 right-0 mt-1 bg-white dark:bg-slate-700 rounded-xl overflow-hidden shadow-2xl border border-slate-200 dark:border-slate-600 max-h-72 overflow-y-auto">
                      <button
                        v-for="r in results" :key="r.id"
                        type="button"
                        @mousedown.prevent="selectResult(r)"
                        class="cursor-pointer w-full flex items-center gap-3 px-3 py-2 hover:bg-slate-100 dark:hover:bg-slate-600 transition-colors text-left"
                      >
                        <img v-if="r.poster_path" :src="`https://image.tmdb.org/t/p/w92${r.poster_path}`" class="w-8 h-11 object-cover rounded shrink-0" />
                        <div v-else class="w-8 h-11 bg-slate-200 dark:bg-slate-600 rounded shrink-0 flex items-center justify-center text-slate-400 dark:text-slate-500 text-xs">?</div>
                        <div class="flex-1 min-w-0">
                          <p class="text-sm text-slate-900 dark:text-white font-medium truncate">{{ r.media_type === 'movie' ? r.title : r.name }}</p>
                          <p class="text-xs text-slate-500 dark:text-slate-400">{{ r.media_type === 'movie' ? 'Movie' : 'Show' }}<span v-if="resultYear(r)"> · {{ resultYear(r) }}</span></p>
                        </div>
                      </button>
                    </div>
                  </div>
                </div>

                <!-- Type + Status + Year in one row -->
                <div class="grid grid-cols-3 gap-3">
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">Type</label>
                    <select v-model="form.type" class="cursor-pointer bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500">
                      <option value="movie">Movie</option>
                      <option value="show">Show</option>
                    </select>
                  </div>
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">Status</label>
                    <select v-model="form.status" class="cursor-pointer bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500">
                      <option value="planned">Planned</option>
                      <option value="watching">Watching</option>
                      <option value="completed">Completed</option>
                    </select>
                  </div>
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">Year</label>
                    <input v-model="form.year" type="number" min="1888" max="2100" placeholder="e.g. 2010" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                  </div>
                </div>

                <!-- Type-specific fields -->
                <div class="flex flex-col gap-3 relative">
                  <div v-if="fetchingDetail" class="absolute inset-0 bg-slate-800/60 rounded-lg flex items-center justify-center z-10">
                    <svg class="w-5 h-5 text-indigo-400 animate-spin" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                    </svg>
                  </div>
                  <template v-if="form.type === 'movie'">
                    <div class="flex flex-col gap-1.5">
                      <label class="text-sm text-slate-500 dark:text-slate-400">Runtime (min)</label>
                      <input v-model="form.runtime" type="number" min="1" placeholder="e.g. 148" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                    </div>
                  </template>
                  <template v-else>
                    <div class="grid grid-cols-3 gap-3">
                      <div class="flex flex-col gap-1.5">
                        <label class="text-sm text-slate-500 dark:text-slate-400">Seasons</label>
                        <input v-model="form.seasons" type="number" min="1" placeholder="e.g. 4" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                      </div>
                      <div class="flex flex-col gap-1.5">
                        <label class="text-sm text-slate-500 dark:text-slate-400">Episodes</label>
                        <input v-model="form.episodes" type="number" min="1" placeholder="e.g. 32" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                      </div>
                      <div class="flex flex-col gap-1.5">
                        <label class="text-sm text-slate-500 dark:text-slate-400">Total runtime (min)</label>
                        <input v-model="form.showRuntime" type="number" min="1" placeholder="e.g. 2790" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                      </div>
                    </div>
                  </template>
                </div>

                <!-- Watch link -->
                <div class="flex flex-col gap-1.5">
                  <div class="flex items-center gap-2">
                    <label class="text-sm text-slate-500 dark:text-slate-400">Where to watch</label>
                    <img v-if="form.streamingLogo" :src="logoUrl(form.streamingLogo)" :alt="form.streamingProvider" class="w-5 h-5 rounded object-cover" />
                    <span v-else-if="form.streamingProvider" class="text-xs text-slate-400 dark:text-slate-500">{{ form.streamingProvider }}</span>
                  </div>
                  <input v-model="form.watchLink" type="url" placeholder="https://…" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                </div>

                <!-- Rating + TMDb -->
                <div class="grid grid-cols-2 gap-3">
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">Your rating (1–10)</label>
                    <input v-model="form.rating" type="number" min="1" max="10" placeholder="—" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                  </div>
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">TMDb rating</label>
                    <div class="bg-slate-100 dark:bg-slate-700/50 rounded-lg px-3 py-2 text-sm text-slate-500 dark:text-slate-400 flex items-center gap-1.5 h-[38px]">
                      <template v-if="form.tmdbRating">
                        <svg class="w-3.5 h-3.5 text-amber-400 fill-current shrink-0" viewBox="0 0 24 24">
                          <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
                        </svg>
                        <span class="text-slate-900 dark:text-white">{{ form.tmdbRating }}</span>
                        <span class="text-slate-400 dark:text-slate-500">/10</span>
                      </template>
                      <span v-else class="text-slate-400 dark:text-slate-600 text-xs">Auto-filled from TMDb</span>
                    </div>
                  </div>
                </div>

                <!-- Notes -->
                <div class="flex flex-col gap-1.5">
                  <label class="text-sm text-slate-500 dark:text-slate-400">Notes</label>
                  <textarea v-model="form.notes" rows="2" placeholder="Any thoughts..." class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 resize-none" />
                </div>

                <div class="flex gap-2">
                  <button
                    type="submit"
                    class="cursor-pointer flex-1 bg-indigo-600 hover:bg-indigo-500 text-white font-medium rounded-lg py-2 text-sm transition-colors"
                  >
                    {{ initial ? 'Save changes' : 'Add to watchlist' }}
                  </button>
                  <button
                    v-if="!initial"
                    type="button"
                    @click="handleSubmit(true)"
                    title="Add and add another"
                    class="cursor-pointer shrink-0 flex items-center gap-1 px-3 py-2 bg-green-700 hover:bg-green-600 text-green-100 rounded-lg transition-colors"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                    </svg>
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
                    </svg>
                  </button>
                </div>
              </div>
            </form>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.15s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
