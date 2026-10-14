<script setup>
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import AppHeader from '@core/AppHeader.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import TemplateModal from '@core/TemplateModal.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { Icon, Spinner } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useCollections } from '@/composables/useCollections.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { useMovieDNA } from '@/composables/useMovieDNA.js'
import { getItems, updateItem, deleteItem } from '@/api/watchlist.js'
import { fetchExtras, hasTMDbKey, logoUrl } from '@/api/tmdb.js'
import { interestCount } from '@/movieDNA/engine.js'
import { movieDNAUses } from '@/utils/pluginSurfaces.js'
import { resolveTarget, buildOpenUrl } from '@/utils/openTarget.js'
import { trailerVideos } from '@/utils/trailers.js'
import { genrePillClass } from '@/utils/genres.js'
import {
  showTotals, watchedFraction, remainingMinutes, formatRuntime, metaLine, markWatchedPatch,
  resetActions, resetPatch, clock,
} from '@/utils/progress.js'
import DetailSection from '@/components/DetailSection.vue'
import TrailersSection from '@/components/TrailersSection.vue'
import ItemPluginSections from '@/components/ItemPluginSections.vue'
import RatingControl from '@/components/RatingControl.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ManageCollectionsModal from '@/components/ManageCollectionsModal.vue'
import SeasonProgressModal from '@/components/SeasonProgressModal.vue'
import MovieDNAModal from '@/components/MovieDNAModal.vue'
import SettingsButton from '@/components/SettingsButton.vue'
import ArchiveBoxIcon from '@/assets/icons/archive-box.svg?component'
import ListBulletIcon from '@/assets/icons/list-bullet.svg?component'

const props = defineProps({ id: { type: String, required: true } })

const { t } = useI18n()
const router = useRouter()
const { isPluginEnabled } = useRegistry()
const { defaults } = useOpenSettings()
const { collections, applyMembership } = useCollections()
const dna = useMovieDNA()

const STATUSES = ['planned', 'watching', 'completed']
const STATUS_COLORS = {
  planned: 'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300',
  watching: 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300',
  completed: 'bg-green-100 dark:bg-green-900 text-green-700 dark:text-green-300',
}
const TYPE_COLORS = {
  movie: 'bg-purple-900 text-purple-300',
  show: 'bg-amber-900 text-amber-300',
}
const FLAME = [
  'M15.362 5.214A8.252 8.252 0 0 1 12 21 8.25 8.25 0 0 1 6.038 7.047 8.287 8.287 0 0 0 9 9.601a8.983 8.983 0 0 1 3.361-6.867 8.21 8.21 0 0 0 3 2.48Z',
  'M12 18a3.75 3.75 0 0 0 .495-7.468 5.99 5.99 0 0 0-1.925 3.547 5.975 5.975 0 0 1-2.133-1.001A3.75 3.75 0 0 0 12 18Z',
]
const rowClass = 'w-full flex items-center gap-3 px-4 py-3 text-left text-sm text-slate-900 dark:text-white hover:bg-black/[0.03] dark:hover:bg-white/5 transition-colors'

const item = ref(null)
const loading = ref(true)
const extras = ref(null)
const marking = ref(false)
const showEdit = ref(false)
const showManage = ref(false)
const showProgress = ref(false)
const showDna = ref(false)
const showDelete = ref(false)
const showReset = ref(false)
const deleting = ref(false)

async function load() {
  loading.value = true
  try {
    const all = await getItems()
    item.value = all.find((i) => i._id === props.id) || null
  } catch {
    item.value = null
  } finally {
    loading.value = false
  }
}
watch(() => props.id, load, { immediate: true })

// Trailers and TMDb's description come from TMDb; nothing without a TMDb id or key.
watch(
  () => (item.value?.tmdbId && hasTMDbKey.value ? `${item.value.type}:${item.value.tmdbId}` : null),
  async (key) => {
    extras.value = null
    if (!key) return
    const [type, id] = key.split(':')
    const loaded = await fetchExtras(id, type).catch(() => null)
    if (key === `${item.value?.type}:${item.value?.tmdbId}`) extras.value = loaded
  },
  { immediate: true }
)

async function patch(data) {
  const prev = item.value.collectionIds || []
  const updated = await updateItem(item.value._id, data)
  if ('collectionIds' in data) applyMembership(prev, updated.collectionIds || [])
  item.value = updated
  return updated
}

function setItem(updated) {
  item.value = updated
}

function goBack() {
  if (window.history.state?.back) router.back()
  else router.push('/')
}

const isShow = computed(() => item.value?.type === 'show')
const meta = computed(() => (item.value ? metaLine(item.value, t) : ''))
const totals = computed(() => showTotals(item.value))
const fraction = computed(() => watchedFraction(item.value))
const timeLeft = computed(() => (fraction.value > 0 && remainingMinutes(item.value) > 0 ? remainingMinutes(item.value) : 0))
const overview = computed(() => extras.value?.overview || item.value?.overview?.trim() || '')
const videos = computed(() => trailerVideos(item.value, extras.value?.videos, t('watchlist.detail.trailer')))
const itemCollections = computed(() => collections.value.filter((c) => (item.value?.collectionIds || []).map(String).includes(String(c._id))))

const target = computed(() => resolveTarget(item.value, defaults))
const openUrl = computed(() => buildOpenUrl(target.value, item.value))
const targetLabel = computed(() => (target.value?.type === 'custom' ? t('watchlist.detail.yourLink') : t(`watchlist.open.${target.value?.type}`)))

const resumeUrl = computed(() => {
  const url = item.value?.lastPage || item.value?.playback?.url
  return /^https?:\/\//i.test(url || '') ? url : null
})
const resumeHost = computed(() => {
  try { return new URL(resumeUrl.value).hostname.replace(/^www\./, '') } catch { return '' }
})
const playbackPct = computed(() => {
  const p = item.value?.playback
  return p?.duration > 0 ? Math.min(100, Math.round((p.position / p.duration) * 100)) : 0
})

const boosts = computed(() => (dna.settings.value.enabled ? interestCount(dna.settings.value, item.value) : 0))
const dnaUnused = computed(() => !movieDNAUses.some((u) => isPluginEnabled(u.pluginId)))
const resets = computed(() => resetActions(item.value))

function setStatus(status) {
  if (status !== item.value.status) patch({ status })
}

async function markWatched() {
  if (marking.value) return
  marking.value = true
  try {
    await patch(markWatchedPatch(item.value))
  } finally {
    marking.value = false
  }
}

function resetProgress(scope) {
  showReset.value = false
  patch(resetPatch(item.value, scope))
}

async function submitEdit(data) {
  await patch(data)
  showEdit.value = false
}

async function confirmDelete() {
  deleting.value = true
  try {
    await deleteItem(item.value._id)
    applyMembership(item.value.collectionIds || [], [])
    showDelete.value = false
    if (window.history.state?.back) router.back()
    else router.replace('/')
  } finally {
    deleting.value = false
  }
}

function openPoster() {
  if (openUrl.value) window.open(openUrl.value, '_blank', 'noopener,noreferrer')
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
          <button
            v-if="item"
            @click="showEdit = true"
            :title="t('watchlist.card.edit')"
            class="nuc-press cursor-pointer p-2 rounded-lg text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
          >
            <Icon name="edit" class="w-4 h-4" />
          </button>
        </template>
      </AppHeader>

      <main class="max-w-2xl mx-auto px-4 py-6 flex flex-col gap-5">
        <div v-if="loading" class="flex justify-center py-24">
          <Spinner class="w-6 h-6 text-slate-400 animate-spin" />
        </div>

        <div v-else-if="!item" class="text-center py-24 flex flex-col items-center gap-3">
          <p class="text-base font-semibold">{{ t('watchlist.detail.notFound') }}</p>
          <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.detail.notFoundHint') }}</p>
          <RouterLink to="/" class="text-sm text-indigo-600 dark:text-indigo-400 hover:underline">{{ t('watchlist.header.backToList') }}</RouterLink>
        </div>

        <template v-else>
          <div class="flex flex-col items-center gap-3 pb-2 text-center">
            <div
              :class="['w-48 sm:w-56 aspect-[2/3] overflow-hidden rounded-2xl bg-slate-100 dark:bg-slate-700/60 shadow-2xl shadow-black/30', openUrl ? 'cursor-pointer' : '']"
              :title="openUrl ? t('watchlist.card.openExternal') : undefined"
              @click="openPoster"
            >
              <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
              <div v-else class="w-full h-full flex items-center justify-center">
                <ArchiveBoxIcon class="w-10 h-10 text-slate-300 dark:text-slate-600" />
              </div>
            </div>
            <h1 class="mt-2 text-2xl font-bold tracking-tight">{{ item.title }}</h1>
            <p v-if="meta" class="text-sm text-slate-500 dark:text-slate-400">{{ meta }}</p>
            <div class="flex items-center justify-center gap-1.5 flex-wrap">
              <span :class="['text-xs font-medium px-2 py-0.5 rounded-full', TYPE_COLORS[item.type]]">
                {{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}
              </span>
              <span v-if="item.tmdbRating" class="text-xs font-medium px-2 py-0.5 rounded-full bg-amber-100 dark:bg-amber-900/40 text-amber-700 dark:text-amber-300">
                TMDb ★ {{ Number(item.tmdbRating).toFixed(1) }}
              </span>
            </div>
            <div class="inline-flex rounded-full bg-black/5 dark:bg-white/8 p-0.5" role="group" :aria-label="t('watchlist.form.status')">
              <button
                v-for="status in STATUSES"
                :key="status"
                @click="setStatus(status)"
                :aria-pressed="item.status === status"
                :class="['cursor-pointer text-xs font-medium px-3 py-1 rounded-full transition-colors', item.status === status ? STATUS_COLORS[status] : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white']"
              >
                {{ t('watchlist.status.' + status) }}
              </button>
            </div>
          </div>

          <div class="flex flex-col gap-2.5">
            <div class="flex items-center gap-2.5">
              <div
                v-if="item.status === 'completed'"
                class="flex-1 h-11 inline-flex items-center justify-center gap-2 rounded-full bg-green-500/15 text-green-600 dark:text-green-400 text-sm font-semibold"
              >
                <Icon name="checkBold" class="w-4 h-4" :sw="3" />
                {{ t('watchlist.detail.watched') }}
              </div>
              <button
                v-else
                @click="markWatched"
                :disabled="marking"
                class="nuc-press cursor-pointer flex-1 h-11 inline-flex items-center justify-center gap-2 rounded-full bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold transition-colors disabled:cursor-wait disabled:opacity-60"
              >
                <Icon name="check" class="w-4 h-4" :sw="2.5" />
                {{ t('watchlist.card.markWatched') }}
              </button>
              <button
                v-if="dna.settings.value.enabled"
                @click="dna.markInterested(item)"
                :title="t('watchlist.detail.interested')"
                :aria-label="t('watchlist.detail.interested')"
                :class="['nuc-press cursor-pointer w-11 h-11 shrink-0 flex items-center justify-center rounded-full bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15 transition-colors', boosts ? 'text-orange-500' : 'text-slate-500 dark:text-slate-300']"
              >
                <svg class="w-5 h-5" viewBox="0 0 24 24" :fill="boosts ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <path v-for="d in FLAME" :key="d" :d="d" />
                </svg>
              </button>
              <button
                @click="patch({ favorite: !item.favorite })"
                :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
                class="nuc-fav nuc-press cursor-pointer w-11 h-11 shrink-0 flex items-center justify-center rounded-full bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15 transition-colors"
                :class="item.favorite ? 'text-rose-500' : 'text-slate-500 dark:text-slate-300'"
              >
                <FavoriteHeart :active="item.favorite" class="w-5 h-5" />
              </button>
            </div>
            <button
              v-if="boosts"
              @click="showDna = true"
              class="cursor-pointer inline-flex items-center justify-center gap-1.5 text-xs text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
            >
              <Icon v-if="dnaUnused" name="info" class="w-3.5 h-3.5 shrink-0" />
              <svg v-else class="w-3.5 h-3.5 shrink-0 text-orange-500" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <path v-for="d in FLAME" :key="d" :d="d" />
              </svg>
              {{ dnaUnused ? t('watchlist.detail.boostedUnused', { count: boosts }) : t('watchlist.detail.boosted', { count: boosts }) }}
            </button>
          </div>

          <DetailSection v-if="isShow" :title="t('watchlist.progress.label')" flush>
            <button @click="showProgress = true" :class="[rowClass, 'flex-col items-stretch gap-2.5']">
              <span class="flex items-center gap-2">
                <ListBulletIcon class="w-4 h-4 text-slate-400 shrink-0" />
                <span class="flex-1 font-semibold">
                  {{ totals.hasProgress ? t('watchlist.detail.episodesOf', { watched: item.status === 'completed' ? totals.totalEp : totals.watchedEp, total: totals.totalEp }) : t('watchlist.card.trackEpisodes') }}
                </span>
                <span v-if="timeLeft" class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.card.timeLeft', { time: formatRuntime(timeLeft) }) }}</span>
                <Icon name="chevronRight" class="w-4 h-4 text-slate-400" />
              </span>
              <span v-if="totals.hasProgress" class="block h-2 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
                <span class="block h-full rounded-full transition-all duration-500" :class="item.status === 'completed' ? 'bg-green-500' : 'bg-indigo-500'" :style="{ width: `${Math.round(fraction * 100)}%` }" />
              </span>
            </button>
          </DetailSection>

          <DetailSection v-if="overview" :title="t('watchlist.detail.overview')">
            <p class="text-sm text-slate-700 dark:text-slate-200 leading-relaxed whitespace-pre-line">{{ overview }}</p>
          </DetailSection>

          <TrailersSection v-if="videos.length" :videos="videos" />

          <DetailSection :title="t('watchlist.form.yourRating')">
            <RatingControl :model-value="item.rating" :max="10" size="lg" @update:model-value="patch({ rating: $event })" />
          </DetailSection>

          <DetailSection v-if="item.streamingProvider" :title="t('watchlist.form.whereToWatch')" flush>
            <component
              :is="item.watchLink ? 'a' : 'div'"
              :href="item.watchLink || undefined"
              :target="item.watchLink ? '_blank' : undefined"
              :rel="item.watchLink ? 'noopener noreferrer' : undefined"
              :class="rowClass"
            >
              <img v-if="item.streamingLogo" :src="logoUrl(item.streamingLogo)" :alt="item.streamingProvider" class="w-8 h-8 rounded-lg object-cover" />
              <span class="flex-1">{{ item.streamingProvider }}</span>
              <Icon v-if="item.watchLink" name="externalLink" class="w-4 h-4 text-slate-400" />
            </component>
          </DetailSection>

          <DetailSection v-if="item.genres?.length" :title="t('watchlist.form.genres')">
            <div class="flex flex-wrap gap-1.5">
              <span v-for="g in item.genres" :key="g" :class="['text-xs font-medium px-2.5 py-1 rounded-full', genrePillClass(g)]">{{ g }}</span>
            </div>
          </DetailSection>

          <ItemPluginSections :item="item" />

          <DetailSection :title="t('watchlist.collections.label')" flush>
            <RouterLink v-for="c in itemCollections" :key="c._id" :to="`/collections/${c._id}`" :class="[rowClass, 'no-underline']">
              <Icon name="folder" class="w-4 h-4 text-violet-500" :sw="1.75" />
              <span class="flex-1 truncate">{{ c.name }}</span>
              <Icon name="chevronRight" class="w-4 h-4 text-slate-400" />
            </RouterLink>
            <button @click="showManage = true" :class="[rowClass, 'cursor-pointer']">
              <Icon name="plus" class="w-4 h-4 text-indigo-500" :sw="2.5" />
              <span class="flex-1">{{ itemCollections.length ? t('watchlist.detail.changeCollections') : t('watchlist.detail.addToCollection') }}</span>
            </button>
          </DetailSection>

          <DetailSection v-if="item.notes" :title="t('watchlist.card.notes')">
            <p class="text-sm text-slate-700 dark:text-slate-200 leading-relaxed whitespace-pre-line">{{ item.notes }}</p>
          </DetailSection>

          <DetailSection flush>
            <a v-if="resumeUrl" :href="resumeUrl" target="_blank" rel="noopener noreferrer" :class="[rowClass, 'flex-col items-stretch gap-2.5 no-underline']">
              <span class="flex items-center gap-2">
                <Icon name="play" class="w-4 h-4 text-blue-500" />
                <span class="flex-1">{{ t('watchlist.detail.continueWatching') }}</span>
                <span v-if="item.playback" class="text-xs tabular-nums text-slate-400 dark:text-slate-500">{{ clock(item.playback.position) }} / {{ clock(item.playback.duration) }}</span>
                <span v-else class="text-xs text-slate-400 dark:text-slate-500">{{ resumeHost }}</span>
              </span>
              <span v-if="item.playback" class="block h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
                <span class="block h-full rounded-full bg-blue-500" :style="{ width: `${playbackPct}%` }" />
              </span>
            </a>
            <a v-if="openUrl" :href="openUrl" target="_blank" rel="noopener noreferrer" :class="[rowClass, 'no-underline']">
              <Icon name="externalLink" class="w-4 h-4 text-sky-500" :sw="1.75" />
              <span class="flex-1">{{ t('watchlist.detail.openOn', { target: targetLabel }) }}</span>
            </a>
            <button v-if="resets.length" @click="showReset = true" :class="[rowClass, 'cursor-pointer']">
              <Icon name="refresh" class="w-4 h-4 text-amber-500" :sw="1.75" />
              <span class="flex-1">{{ t('watchlist.detail.resetProgress') }}</span>
            </button>
            <button @click="showDelete = true" :class="[rowClass, 'cursor-pointer !text-red-500 dark:!text-red-400']">
              <span class="flex-1">{{ t('watchlist.card.delete') }}</span>
            </button>
          </DetailSection>
        </template>
      </main>
    </div>

    <template v-if="item">
      <ItemFormModal :show="showEdit" :initial="item" @close="showEdit = false" @submit="submitEdit" @deleted="goBack" />
      <ManageCollectionsModal :show="showManage" :item="item" @close="showManage = false" @updated="setItem" />
      <SeasonProgressModal v-if="isShow" :show="showProgress" :item="item" @close="showProgress = false" @updated="setItem" />
      <MovieDNAModal :show="showDna" @close="showDna = false" />

      <TemplateModal
        :show="showDelete"
        :title="t('watchlist.card.removeTitle')"
        :message="t('watchlist.card.removeMessage', { title: item.title })"
        :confirm-label="t('watchlist.card.remove')"
        :busy="deleting"
        @confirm="confirmDelete"
        @cancel="showDelete = false"
      />

      <TemplateModal
        :show="showReset"
        header
        size="xs"
        :title="t('watchlist.detail.resetProgress')"
        :description="isShow ? t('watchlist.detail.resetShowHint') : t('watchlist.detail.resetMovieHint')"
        body-class="px-5 sm:px-6 pb-5 pt-3"
        @cancel="showReset = false"
      >
        <div class="flex flex-col gap-2">
          <button
            v-for="action in resets"
            :key="action.id"
            @click="resetProgress(action.id)"
            :class="['nuc-press cursor-pointer w-full rounded-lg px-3 py-2 text-sm font-medium transition-colors', action.destructive ? 'bg-red-500/10 hover:bg-red-500/20 text-red-600 dark:text-red-400' : 'bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15']"
          >
            {{ isShow ? t(`watchlist.detail.reset.${action.id}`) : t('watchlist.detail.resetProgress') }}
          </button>
        </div>
      </TemplateModal>
    </template>
  </div>
</template>
