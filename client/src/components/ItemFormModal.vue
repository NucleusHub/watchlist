<script setup>
import { ref, computed, watch, nextTick } from 'vue'
import { logoUrl } from '@/api/tmdb.js'
import { BUILTIN_SOURCES, PLUGIN_SOURCES } from '@/api/sources.js'
import { uploadImage } from '@/api/watchlist.js'
import { OPEN_OPTIONS, TITLE_FORMATS } from '@/utils/openTarget.js'
import { normalizeGenres, genrePillClass, MAX_GENRES } from '@/utils/genres.js'
import TemplateModal from '@core/TemplateModal.vue'
import RatingControl from './RatingControl.vue'
import CollectionSelect from '@/components/CollectionSelect.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { Icon, Spinner } from '@core/icons'
import PhotoIcon from '@/assets/icons/photo.svg?component'
import ChevronDownIcon from '@/assets/icons/chevron-down.svg?component'
import ArrowUpTrayIcon from '@/assets/icons/arrow-up-tray.svg?component'
import LinkIcon from '@/assets/icons/link.svg?component'
import StarIcon from '@/assets/icons/star.svg?component'
import ArrowRightIcon from '@/assets/icons/arrow-right.svg?component'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { searchSources } = useOpenSettings()

const enabledSources = computed(() => {
  const avail = [...BUILTIN_SOURCES, ...PLUGIN_SOURCES.filter((s) => isPluginEnabled(s.pluginId))]
  const on = avail.filter((s) => searchSources.value.includes(s.id))
  return on.length ? on : BUILTIN_SOURCES
})
const multiSource = computed(() => enabledSources.value.length > 1)

const props = defineProps({
  show: { type: Boolean, default: false },
  initial: { type: Object, default: null },
  resetKey: { type: Number, default: 0 },
})
const emit = defineEmits(['close', 'submit'])

const form = ref({})
const results = ref([])
const showDropdown = ref(false)
const searching = ref(false)
const searchError = ref(null)
const fetchingDetail = ref(false)
const uploading = ref(false)
const fileInput = ref(null)
const titleInput = ref(null)
const urlInput = ref(null)
const showPosterMenu = ref(false)
const showUrlInput = ref(false)
const posterUrlDraft = ref('')
const genreDraft = ref('')
const openType = ref('')
const openCustomUrl = ref('')
const openTitleFormat = ref('raw')
let searchTimer = null

const EMPTY_FORM = () => ({
  title: '', type: 'movie', status: 'planned',
  posterUrl: null,
  tmdbRating: null,
  watchLink: '',
  streamingProvider: null,
  streamingLogo: null,
  rating: null, year: '', runtime: '',
  genres: [],
  seasons: '', episodes: '', showRuntime: '',
  seasonProgress: null,
  favorite: false,
  collectionIds: [],
  notes: '',
})

function resetForm() {
  form.value = props.initial ? { ...props.initial } : EMPTY_FORM()
  openType.value = form.value.openTarget?.type || ''
  openCustomUrl.value = form.value.openTarget?.customUrl || ''
  openTitleFormat.value = form.value.openTarget?.titleFormat || 'raw'
  results.value = []
  showDropdown.value = false
  showPosterMenu.value = false
  showUrlInput.value = false
  posterUrlDraft.value = ''
  genreDraft.value = ''
  form.value.genres = normalizeGenres(form.value.genres)
  nextTick(() => titleInput.value?.focus())
}

function addGenre() {
  const name = genreDraft.value.trim()
  if (!name) return
  form.value.genres = normalizeGenres([...(form.value.genres ?? []), name])
  genreDraft.value = ''
}

function onGenreKey(e) {
  if (e.key !== 'Enter' && e.key !== ',') return
  e.preventDefault()
  addGenre()
}

function removeGenre(name) {
  const key = name.toLowerCase()
  form.value.genres = (form.value.genres ?? []).filter((g) => g.toLowerCase() !== key)
}

const genresFull = computed(() => (form.value.genres?.length ?? 0) >= MAX_GENRES)

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
    searchError.value = null
    showDropdown.value = false
    return
  }
  searchTimer = setTimeout(async () => {
    searching.value = true
    searchError.value = null
    try {
      const sources = enabledSources.value
      const settled = await Promise.allSettled(sources.map((s) => s.search(q)))
      const merged = []
      settled.forEach((res, i) => {
        if (res.status === 'fulfilled' && Array.isArray(res.value)) {
          for (const r of res.value) merged.push({ ...r, _source: sources[i], sourceLabel: sources[i].label })
        } else if (res.status === 'rejected') {
          console.warn(`[watchlist] search source "${sources[i].label}" failed:`, res.reason)
        }
      })
      results.value = merged.slice(0, 10)
      if (!results.value.length && settled.every((r) => r.status === 'rejected')) {
        searchError.value = settled[0]?.reason?.message || 'Search failed'
      }
      showDropdown.value = results.value.length > 0 || !!searchError.value
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
  form.value.title = r.title
  form.value.type = r.type
  if (r.poster) form.value.posterUrl = r.poster

  fetchingDetail.value = true
  try {
    const patch = await r._source.toForm(r, { existing: form.value })
    Object.assign(form.value, patch)
  } catch {
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
    delete payload.seasonProgress
  } else {
    delete payload.runtime
  }
  for (const f of ['rating', 'year', 'runtime', 'seasons', 'episodes', 'showRuntime']) {
    if (!(f in payload)) continue
    if (payload[f] === '' || payload[f] == null) payload[f] = null
    else payload[f] = Number(payload[f])
  }
  payload.genres = normalizeGenres(payload.genres)
  payload.openTarget = openType.value
    ? {
        type: openType.value,
        customUrl: openType.value === 'custom' ? openCustomUrl.value.trim() : '',
        titleFormat: openType.value === 'custom' ? openTitleFormat.value : 'raw',
      }
    : null
  emit('submit', payload, addAnother)
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    :title="initial ? t('watchlist.form.editTitle') : t('watchlist.form.addTitle')"
    size="xl"
    body-class="px-4 sm:px-6 pb-5 pt-2"
    @cancel="$emit('close')"
  >
    <form @submit.prevent="handleSubmit()" class="flex flex-col gap-5 sm:flex-row sm:gap-6 items-start">

              <div class="w-36 sm:w-44 shrink-0 mx-auto sm:mx-0 flex flex-col gap-3 sm:sticky sm:top-0">
                <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.poster') }}</label>
                <div class="relative">
                  <div
                    class="aspect-[2/3] rounded-lg overflow-hidden bg-slate-100 dark:bg-slate-700 border-2 border-dashed border-slate-300 dark:border-slate-600 flex items-center justify-center cursor-pointer hover:border-indigo-500 transition-colors"
                    @click="!form.posterUrl && triggerUpload()"
                  >
                    <img v-if="form.posterUrl" :src="form.posterUrl" class="w-full h-full object-cover" />
                    <div v-else class="flex flex-col items-center gap-2 text-slate-400 dark:text-slate-500 p-3">
                      <PhotoIcon class="w-7 h-7" />
                      <span class="text-xs text-center leading-tight">{{ t('watchlist.form.clickToUpload') }}</span>
                    </div>
                  </div>
                  <div v-if="uploading" class="absolute inset-0 bg-black/60 rounded-lg flex items-center justify-center">
                    <Spinner class="w-5 h-5 text-white animate-spin" />
                  </div>
                  <div v-if="form.posterUrl && !uploading" class="absolute top-1 right-1 flex flex-col gap-1">
                    <button type="button" @click="triggerUpload" class="cursor-pointer bg-black/70 hover:bg-black/90 text-white rounded p-1 transition-colors" :title="t('watchlist.form.replace')">
                      <Icon name="refresh" class="w-3 h-3" :sw="2.5" />
                    </button>
                    <button type="button" @click="form.posterUrl = null" class="cursor-pointer bg-black/70 hover:bg-red-600/90 text-white rounded p-1 transition-colors" :title="t('watchlist.form.remove')">
                      <Icon name="close" class="w-3 h-3" :sw="2.5" />
                    </button>
                  </div>
                </div>
                <div class="relative">
                  <button
                    type="button"
                    @click="openPosterMenu"
                    class="cursor-pointer w-full flex items-center justify-between gap-1.5 px-2.5 py-1.5 text-xs text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg transition-colors"
                  >
                    <span>{{ t('watchlist.form.setPoster') }}</span>
                    <ChevronDownIcon class="w-3 h-3" />
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
                      <ArrowUpTrayIcon class="w-3.5 h-3.5 shrink-0" />
                      {{ t('watchlist.form.uploadFile') }}
                    </button>
                    <button
                      type="button"
                      @click="pickUrl"
                      class="cursor-pointer w-full flex items-center gap-2 px-3 py-2 text-xs text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-600 transition-colors"
                    >
                      <LinkIcon class="w-3.5 h-3.5 shrink-0" />
                      {{ t('watchlist.form.pasteUrl') }}
                    </button>
                  </div>
                </div>

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
                    <button type="button" @click="applyPosterUrl" class="cursor-pointer flex-1 text-xs bg-indigo-600 hover:bg-indigo-500 text-white rounded-md py-1 transition-colors">{{ t('watchlist.form.apply') }}</button>
                    <button type="button" @click="showUrlInput = false" class="cursor-pointer text-xs bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 text-slate-600 dark:text-slate-300 rounded-md px-2 py-1 transition-colors">{{ t('watchlist.form.cancel') }}</button>
                  </div>
                </div>
                <input ref="fileInput" type="file" accept="image/*" class="hidden" @change="handleFileUpload" />
              </div>

              <div class="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-x-5 gap-y-4 min-w-0 self-stretch content-start">

                <div class="flex flex-col gap-1.5 sm:col-span-2">
                  <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.title') }}</label>
                  <div class="relative">
                    <input
                      ref="titleInput"
                      v-model="form.title"
                      @input="onTitleInput"
                      @blur="closeDropdown"
                      required
                      autocomplete="off"
                      :placeholder="t('watchlist.form.titlePlaceholder')"
                      class="w-full bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 pr-8 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                    <Spinner v-if="searching" class="absolute right-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 animate-spin" />
                    <div v-if="showDropdown" class="absolute z-10 top-full left-0 right-0 mt-1 bg-white dark:bg-slate-700 rounded-xl overflow-hidden shadow-2xl border border-slate-200 dark:border-slate-600 max-h-72 overflow-y-auto">
                      <p v-if="searchError" class="px-3 py-2.5 text-xs text-amber-600 dark:text-amber-400">
                        {{ searchError }}
                      </p>
                      <button
                        v-for="r in results" :key="r.key"
                        type="button"
                        @mousedown.prevent="selectResult(r)"
                        class="cursor-pointer w-full flex items-center gap-3 px-3 py-2 hover:bg-slate-100 dark:hover:bg-slate-600 transition-colors text-left"
                      >
                        <img v-if="r.poster" :src="r.poster" class="w-8 h-11 object-cover rounded shrink-0" />
                        <div v-else class="w-8 h-11 bg-slate-200 dark:bg-slate-600 rounded shrink-0 flex items-center justify-center text-slate-400 dark:text-slate-500 text-xs">?</div>
                        <div class="flex-1 min-w-0">
                          <p class="text-sm text-slate-900 dark:text-white font-medium truncate">{{ r.title }}</p>
                          <p class="text-xs text-slate-500 dark:text-slate-400">{{ r.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}<span v-if="r.subtitle"> · {{ r.subtitle }}</span></p>
                        </div>
                        <span v-if="multiSource" class="shrink-0 text-[10px] font-medium uppercase tracking-wide text-slate-400 dark:text-slate-500 bg-slate-100 dark:bg-slate-600/50 rounded px-1.5 py-0.5">{{ r.sourceLabel }}</span>
                      </button>
                    </div>
                  </div>
                </div>

                <div class="grid grid-cols-3 gap-3 sm:col-span-2">
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.type') }}</label>
                    <select v-model="form.type" class="cursor-pointer bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500">
                      <option value="movie">{{ t('watchlist.type.movie') }}</option>
                      <option value="show">{{ t('watchlist.type.show') }}</option>
                    </select>
                  </div>
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.status') }}</label>
                    <select v-model="form.status" class="cursor-pointer bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500">
                      <option value="planned">{{ t('watchlist.status.planned') }}</option>
                      <option value="watching">{{ t('watchlist.status.watching') }}</option>
                      <option value="completed">{{ t('watchlist.status.completed') }}</option>
                    </select>
                  </div>
                  <div class="flex flex-col gap-1.5">
                    <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.year') }}</label>
                    <input v-model="form.year" type="number" min="1888" max="2100" :placeholder="t('watchlist.form.yearPlaceholder')" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                  </div>
                </div>

                <div class="flex flex-col gap-3 relative sm:col-span-2">
                  <div v-if="fetchingDetail" class="absolute inset-0 bg-slate-800/60 rounded-lg flex items-center justify-center z-10">
                    <Spinner class="w-5 h-5 text-indigo-400 animate-spin" />
                  </div>
                  <template v-if="form.type === 'movie'">
                    <div class="flex flex-col gap-1.5">
                      <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.runtime') }}</label>
                      <input v-model="form.runtime" type="number" min="1" :placeholder="t('watchlist.form.runtimePlaceholder')" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                    </div>
                  </template>
                  <template v-else>
                    <div class="grid grid-cols-3 gap-3">
                      <div class="flex flex-col gap-1.5">
                        <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.seasons') }}</label>
                        <input v-model="form.seasons" type="number" min="1" :placeholder="t('watchlist.form.seasonsPlaceholder')" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                      </div>
                      <div class="flex flex-col gap-1.5">
                        <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.episodes') }}</label>
                        <input v-model="form.episodes" type="number" min="1" :placeholder="t('watchlist.form.episodesPlaceholder')" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                      </div>
                      <div class="flex flex-col gap-1.5">
                        <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.totalRuntime') }}</label>
                        <input v-model="form.showRuntime" type="number" min="1" :placeholder="t('watchlist.form.totalRuntimePlaceholder')" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                      </div>
                    </div>
                  </template>
                </div>

                <div class="flex flex-col gap-1.5">
                  <div class="flex items-center gap-2">
                    <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.whereToWatch') }}</label>
                    <img v-if="form.streamingLogo" :src="logoUrl(form.streamingLogo)" :alt="form.streamingProvider" class="w-5 h-5 rounded object-cover" />
                    <span v-else-if="form.streamingProvider" class="text-xs text-slate-400 dark:text-slate-500">{{ form.streamingProvider }}</span>
                  </div>
                  <input v-model="form.watchLink" type="url" placeholder="https://…" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                </div>

                <div class="flex flex-col gap-1.5">
                  <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.openOnClick') }}</label>
                  <select v-model="openType" class="cursor-pointer bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500">
                    <option value="">{{ t('watchlist.form.openUseGlobal') }}</option>
                    <option v-for="opt in OPEN_OPTIONS" :key="opt.type" :value="opt.type">{{ t(opt.i18n) }}</option>
                  </select>
                  <template v-if="openType === 'custom'">
                    <input
                      v-model="openCustomUrl"
                      type="url"
                      :placeholder="t('watchlist.open.customPlaceholder')"
                      class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                    <div class="flex items-center gap-2">
                      <label class="text-xs text-slate-500 dark:text-slate-400 shrink-0">{{ t('watchlist.open.titleFormat') }}</label>
                      <select v-model="openTitleFormat" class="cursor-pointer flex-1 bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500">
                        <option v-for="fmt in TITLE_FORMATS" :key="fmt.value" :value="fmt.value">{{ t(fmt.i18n) }} — {{ fmt.example }}</option>
                      </select>
                    </div>
                    <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.open.customHint') }}</p>
                  </template>
                </div>

                <div class="flex flex-col gap-1.5">
                  <div class="flex items-center justify-between">
                    <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.yourRating') }}</label>
                    <button
                      type="button"
                      @click="form.favorite = !form.favorite"
                      :title="form.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
                      class="nuc-fav nuc-press cursor-pointer inline-flex items-center gap-1.5 text-sm transition-colors"
                      :class="form.favorite ? 'text-rose-500' : 'text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200'"
                    >
                      <FavoriteHeart :active="form.favorite" class="w-5 h-5" />
                      <span>{{ t('watchlist.form.favorite') }}</span>
                    </button>
                  </div>
                  <RatingControl v-model="form.rating" :max="10" size="md" />
                </div>

                <div class="flex flex-col gap-1.5">
                  <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.tmdbRating') }}</label>
                  <div class="bg-slate-100 dark:bg-slate-700/50 rounded-lg px-3 py-2 text-sm text-slate-500 dark:text-slate-400 flex items-center gap-1.5 h-[38px]">
                    <template v-if="form.tmdbRating">
                      <StarIcon class="w-3.5 h-3.5 text-amber-400 fill-current shrink-0" />
                      <span class="text-slate-900 dark:text-white">{{ form.tmdbRating }}</span>
                      <span class="text-slate-400 dark:text-slate-500">/10</span>
                    </template>
                    <span v-else class="text-slate-400 dark:text-slate-600 text-xs">{{ t('watchlist.form.tmdbAutofill') }}</span>
                  </div>
                </div>

                <div class="flex flex-col gap-1.5 sm:col-span-2">
                  <div class="flex items-center justify-between">
                    <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.genres') }}</label>
                    <span v-if="genresFull" class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.form.genresFull', { max: MAX_GENRES }) }}</span>
                  </div>
                  <div class="flex flex-wrap items-center gap-1.5">
                    <span
                      v-for="g in form.genres"
                      :key="g"
                      :class="['inline-flex items-center gap-1 text-xs font-medium pl-2 pr-1 py-0.5 rounded-full', genrePillClass(g)]"
                    >
                      {{ g }}
                      <button
                        type="button"
                        @click="removeGenre(g)"
                        :title="t('watchlist.form.removeGenre', { genre: g })"
                        class="cursor-pointer rounded-full p-0.5 hover:bg-black/10 dark:hover:bg-white/15 transition-colors"
                      >
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
                      </button>
                    </span>
                    <input
                      v-model="genreDraft"
                      :disabled="genresFull"
                      @keydown="onGenreKey"
                      @blur="addGenre"
                      :placeholder="t('watchlist.form.genrePlaceholder')"
                      class="min-w-28 flex-1 bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-1.5 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50"
                    />
                  </div>
                </div>

                <div class="sm:col-span-2 h-px bg-black/[0.06] dark:bg-white/8" />

                <div class="flex flex-col gap-1.5 sm:col-span-2">
                  <div class="flex items-center justify-between">
                    <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.collections.label') }}</label>
                    <span v-if="form.collectionIds?.length" class="text-xs text-indigo-600 dark:text-indigo-400">{{ t('watchlist.collections.selectedCount', { count: form.collectionIds.length }) }}</span>
                  </div>
                  <CollectionSelect v-model="form.collectionIds" list-class="max-h-40 overflow-y-auto" />
                </div>

                <div class="flex flex-col gap-1.5 sm:col-span-2">
                  <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.form.notes') }}</label>
                  <textarea v-model="form.notes" rows="2" :placeholder="t('watchlist.form.notesPlaceholder')" class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 resize-none" />
                </div>

                <div class="flex gap-2 sm:col-span-2">
                  <button
                    type="submit"
                    class="cursor-pointer flex-1 bg-indigo-600 hover:bg-indigo-500 text-white font-medium rounded-lg py-2 text-sm transition-colors"
                  >
                    {{ initial ? t('watchlist.form.saveChanges') : t('watchlist.form.addTitle') }}
                  </button>
                  <button
                    v-if="!initial"
                    type="button"
                    @click="handleSubmit(true)"
                    :title="t('watchlist.form.addAnother')"
                    class="cursor-pointer shrink-0 flex items-center gap-1 px-3 py-2 bg-green-700 hover:bg-green-600 text-green-100 rounded-lg transition-colors"
                  >
                    <Icon name="plus" class="w-4 h-4" />
                    <ArrowRightIcon class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
    </form>
  </TemplateModal>
</template>
