<script setup>
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import AppHeader from '@core/AppHeader.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import { Icon, Spinner } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { getItems, createItem } from '@/api/watchlist.js'
import { BUILTIN_SOURCES } from '@/api/sources.js'
import { fetchMovieDetail, fetchTvDetail, fetchExtras, hasTMDbKey } from '@/api/tmdb.js'
import { metaLine } from '@/utils/progress.js'
import { genrePillClass } from '@/utils/genres.js'
import { itemRoute } from '@/utils/routes.js'
import DetailSection from '@/components/DetailSection.vue'
import TrailersSection from '@/components/TrailersSection.vue'
import ItemPluginSections from '@/components/ItemPluginSections.vue'
import SettingsButton from '@/components/SettingsButton.vue'
import ArchiveBoxIcon from '@/assets/icons/archive-box.svg?component'

// A TMDb title that isn't in the library (yet); `kind` is 'movie' or 'show'.
const props = defineProps({
  kind: { type: String, required: true },
  tmdbId: { type: String, required: true },
})

const { t } = useI18n()
const router = useRouter()
const tmdbSource = BUILTIN_SOURCES.find((s) => s.id === 'tmdb')

const draft = ref(null)
const overview = ref('')
const videos = ref([])
const existing = ref(null)
const failed = ref(false)
const loading = ref(true)
const adding = ref(false)

const type = computed(() => (props.kind === 'movie' ? 'movie' : 'show'))
const meta = computed(() => (draft.value ? metaLine(draft.value, t) : ''))

async function load() {
  loading.value = true
  failed.value = false
  draft.value = null
  videos.value = []
  existing.value = null
  try {
    if (!hasTMDbKey.value) throw new Error('no key')
    const id = Number(props.tmdbId)
    const isMovie = type.value === 'movie'
    const detail = await (isMovie ? fetchMovieDetail(id) : fetchTvDetail(id))
    overview.value = (detail.overview || '').trim()
    const raw = { ...detail, id, media_type: isMovie ? 'movie' : 'tv' }
    draft.value = await tmdbSource.toForm({ _raw: raw })
    getItems()
      .then((all) => { existing.value = all.find((i) => i.tmdbId === id && i.type === type.value) || null })
      .catch(() => {})
    fetchExtras(id, type.value).then((e) => { videos.value = e.videos }).catch(() => {})
  } catch {
    failed.value = true
  } finally {
    loading.value = false
  }
}
watch(() => [props.kind, props.tmdbId], load, { immediate: true })

function goBack() {
  if (window.history.state?.back) router.back()
  else router.push('/')
}

// Adds it and swaps this preview for the title's own page.
async function add() {
  if (adding.value || !draft.value) return
  adding.value = true
  try {
    const created = await createItem({ ...draft.value, year: Number(draft.value.year) || null, status: 'planned' })
    router.replace(itemRoute(created._id))
  } finally {
    adding.value = false
  }
}
</script>

<template>
  <div class="relative min-h-screen bg-slate-100 dark:bg-[#0d0d1a] text-slate-900 dark:text-white overflow-x-hidden">
    <BackgroundBlobs />
    <div class="relative z-10">
      <AppHeader>
        <template #left>
          <button
            @click="goBack"
            :title="t('watchlist.header.backToList')"
            class="cursor-pointer p-2 rounded-lg text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
          >
            <Icon name="arrowLeft" class="w-5 h-5" />
          </button>
        </template>
        <template #right>
          <SettingsButton />
        </template>
      </AppHeader>

      <main class="max-w-2xl mx-auto px-4 py-6 flex flex-col gap-5">
        <div v-if="loading" class="flex justify-center py-24">
          <Spinner class="w-6 h-6 text-slate-400 animate-spin" />
        </div>

        <div v-else-if="failed || !draft" class="text-center py-24 flex flex-col items-center gap-3">
          <p class="text-base font-semibold">{{ t('watchlist.preview.failed') }}</p>
          <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.preview.failedHint') }}</p>
          <button @click="load" class="cursor-pointer text-sm text-indigo-600 dark:text-indigo-400 hover:underline">{{ t('watchlist.state.retry') }}</button>
        </div>

        <template v-else>
          <div class="flex flex-col items-center gap-3 pb-2 text-center">
            <div class="w-44 sm:w-52 aspect-[2/3] overflow-hidden rounded-2xl bg-slate-100 dark:bg-slate-700/60 shadow-2xl shadow-black/30">
              <img v-if="draft.posterUrl" :src="draft.posterUrl" :alt="draft.title" class="w-full h-full object-cover" />
              <div v-else class="w-full h-full flex items-center justify-center">
                <ArchiveBoxIcon class="w-10 h-10 text-slate-300 dark:text-slate-600" />
              </div>
            </div>
            <h1 class="mt-2 text-2xl font-bold tracking-tight">{{ draft.title }}</h1>
            <p v-if="meta" class="text-sm text-slate-500 dark:text-slate-400">{{ meta }}</p>
            <div class="flex items-center justify-center gap-1.5 flex-wrap">
              <span :class="['text-xs font-medium px-2 py-0.5 rounded-full', type === 'movie' ? 'bg-purple-900 text-purple-300' : 'bg-amber-900 text-amber-300']">
                {{ type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}
              </span>
              <span v-if="draft.tmdbRating" class="text-xs font-medium px-2 py-0.5 rounded-full bg-amber-100 dark:bg-amber-900/40 text-amber-700 dark:text-amber-300">
                TMDb ★ {{ Number(draft.tmdbRating).toFixed(1) }}
              </span>
            </div>
          </div>

          <RouterLink
            v-if="existing"
            :to="itemRoute(existing._id)"
            class="nuc-press h-11 inline-flex items-center justify-center gap-2 rounded-full bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold no-underline transition-colors"
          >
            {{ t('watchlist.preview.openInLibrary') }}
          </RouterLink>
          <button
            v-else
            @click="add"
            :disabled="adding"
            class="nuc-press cursor-pointer h-11 inline-flex items-center justify-center gap-2 rounded-full bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold transition-colors disabled:cursor-wait disabled:opacity-60"
          >
            <Icon name="plus" class="w-4 h-4" :sw="2.5" />
            {{ t('watchlist.form.addTitle') }}
          </button>

          <DetailSection v-if="overview" :title="t('watchlist.detail.overview')">
            <p class="text-sm text-slate-700 dark:text-slate-200 leading-relaxed whitespace-pre-line">{{ overview }}</p>
          </DetailSection>

          <TrailersSection v-if="videos.length" :videos="videos" />

          <DetailSection v-if="draft.genres?.length" :title="t('watchlist.form.genres')">
            <div class="flex flex-wrap gap-1.5">
              <span v-for="g in draft.genres" :key="g" :class="['text-xs font-medium px-2.5 py-1 rounded-full', genrePillClass(g)]">{{ g }}</span>
            </div>
          </DetailSection>

          <ItemPluginSections :item="{ type, tmdbId: Number(tmdbId), title: draft.title }" />
        </template>
      </main>
    </div>
  </div>
</template>
