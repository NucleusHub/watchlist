<script setup>
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Spinner } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { getItems, createItem } from '@/api/watchlist.js'
import { BUILTIN_SOURCES } from '@/api/sources.js'
import { fetchMovieDetail, fetchTvDetail, fetchExtras, hasTMDbKey } from '@/api/tmdb.js'
import { metaLine } from '@/utils/progress.js'
import { itemRoute } from '@/utils/routes.js'
import TrailersSection from '@/components/TrailersSection.vue'
import ItemPluginSections from '@/components/ItemPluginSections.vue'
import PageShell from '@/ui/PageShell.vue'
import WlSection from '@/ui/WlSection.vue'
import Glyph from '@/ui/Glyph.vue'
import EmptyState from '@/ui/EmptyState.vue'
import { genreColor } from '@/ui/palette.js'

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

// Adds it and swaps this preview for the title's own page.
async function add() {
  if (adding.value || !draft.value) return
  adding.value = true
  try {
    const created = await createItem({ ...draft.value, year: Number(draft.value.year) || null, status: 'planned' })
    router.replace({ path: '/', ...itemRoute(created._id) })
  } finally {
    adding.value = false
  }
}
</script>

<template>
  <PageShell>
    <div v-if="loading" class="flex justify-center py-24">
      <Spinner class="w-6 h-6 text-[var(--wl-text-2)] animate-spin" />
    </div>

    <EmptyState v-else-if="failed || !draft" icon="film" :title="t('watchlist.preview.failed')" :message="t('watchlist.preview.failedHint')" class="pt-16">
      <button type="button" class="wl-btn wl-btn-secondary mt-2" @click="load">{{ t('watchlist.state.retry') }}</button>
    </EmptyState>

    <template v-else>
      <div class="flex flex-col items-center gap-3.5 pb-6 text-center nuc-in">
        <div class="relative w-[200px] sm:w-[220px] aspect-[2/3] rounded-[22px] shadow-[0_14px_40px_-10px_rgb(0_0_0/0.5)]">
          <div v-squircle class="absolute inset-0 rounded-[22px] overflow-hidden bg-[var(--wl-well)] grid place-items-center">
            <img v-if="draft.posterUrl" :src="draft.posterUrl" :alt="draft.title" class="w-full h-full object-cover" />
            <Glyph v-else :name="type === 'show' ? 'tv' : 'film'" :sw="1" class="w-12 h-12 text-[var(--wl-text-2)]" />
          </div>
        </div>
        <h1 class="mt-1 text-[26px] leading-tight font-bold tracking-[-0.015em]">{{ draft.title }}</h1>
        <p v-if="meta" class="text-[15px] text-[var(--wl-text-2)]">{{ meta }}</p>
        <div class="flex items-center justify-center gap-1.5 flex-wrap">
          <span class="wl-tag">{{ type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}</span>
          <span v-if="draft.tmdbRating" class="wl-tag">TMDb ★ {{ Number(draft.tmdbRating).toFixed(1) }}</span>
        </div>
      </div>

      <RouterLink v-if="existing" :to="itemRoute(existing._id)" class="wl-btn wl-btn-primary w-full !min-h-[52px] !text-base mb-7">
        {{ t('watchlist.preview.openInLibrary') }}
      </RouterLink>
      <button v-else type="button" :disabled="adding" class="wl-btn wl-btn-primary w-full !min-h-[52px] !text-base mb-7" @click="add">
        <Glyph name="plus" :sw="2.75" class="w-4 h-4" />
        {{ t('watchlist.form.addTitle') }}
      </button>

      <WlSection v-if="overview" :title="t('watchlist.detail.overview')" padded>
        <p class="text-[15px] leading-relaxed whitespace-pre-line">{{ overview }}</p>
      </WlSection>

      <TrailersSection v-if="videos.length" :videos="videos" />

      <WlSection v-if="draft.genres?.length" :title="t('watchlist.form.genres')" padded>
        <div class="flex flex-wrap gap-1.5">
          <span v-for="g in draft.genres" :key="g" class="wl-chip !h-7 !text-white" :style="{ background: genreColor(g) }">{{ g }}</span>
        </div>
      </WlSection>

      <ItemPluginSections :item="{ type, tmdbId: Number(tmdbId), title: draft.title }" />
    </template>
  </PageShell>
</template>
