<script setup>
import { ref, computed } from 'vue'
import confetti from 'canvas-confetti'
import { updateItem, deleteItem } from '@/api/watchlist.js'
import { logoUrl } from '@/api/tmdb.js'
import { showTotals, watchedFraction, remainingMinutes } from '@/utils/progress.js'
import TemplateModal from '@core/TemplateModal.vue'
import SeasonProgressModal from '@/components/SeasonProgressModal.vue'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({
  item: { type: Object, required: true },
  gridStyle: { type: String, default: 'small' },
})

const isList    = computed(() => props.gridStyle === 'list')
const isCompact = computed(() => props.gridStyle === 'list' || props.gridStyle === 'small')
const emit = defineEmits(['updated', 'deleted', 'edit'])

const STATUS_COLORS = {
  planned:   'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300',
  watching:  'bg-blue-100  dark:bg-blue-900  text-blue-700  dark:text-blue-300',
  completed: 'bg-green-100 dark:bg-green-900 text-green-700 dark:text-green-300',
}

const TYPE_COLORS = {
  movie: 'bg-purple-900 text-purple-300',
  show: 'bg-amber-900 text-amber-300',
}

const cardRef = ref(null)
const deleting = ref(false)
const showConfirm = ref(false)
const marking = ref(false)
const showProgress = ref(false)

// Show progress: episode totals, percentage and remaining runtime.
const totals = computed(() => showTotals(props.item))
const progressPct = computed(() => {
  if (props.item.status === 'completed') return 100
  return totals.value.totalEp ? Math.round((totals.value.watchedEp / totals.value.totalEp) * 100) : 0
})
const isShow = computed(() => props.item.type === 'show')
const isPartial = computed(
  () => props.item.status !== 'completed' && totals.value.watchedEp > 0 && totals.value.watchedEp < totals.value.totalEp
)
const remainingLabel = computed(() => {
  if (!isPartial.value) return null
  return t('watchlist.card.timeLeft', { time: formatRuntime(remainingMinutes(props.item)) })
})

function handleProgressUpdated(updated) {
  emit('updated', updated)
}

function formatRuntime(minutes) {
  if (!minutes) return null
  if (minutes < 60) return `${minutes} min`
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return m ? `${h}h ${m}m` : `${h}h`
}

const meta = computed(() => {
  const parts = []
  if (props.item.year) parts.push(props.item.year)
  if (props.item.type === 'movie') {
    const rt = formatRuntime(props.item.runtime)
    if (rt) parts.push(rt)
  } else {
    if (props.item.seasons) parts.push(t(props.item.seasons === 1 ? 'watchlist.card.seasonOne' : 'watchlist.card.seasonMany', { count: props.item.seasons }))
    if (props.item.episodes) parts.push(t('watchlist.card.episodesShort', { count: props.item.episodes }))
    const rt = formatRuntime(props.item.showRuntime)
    if (rt) parts.push(rt)
  }
  return parts.join(' · ')
})

async function cycleStatus() {
  const order = ['planned', 'watching', 'completed']
  const next = order[(order.indexOf(props.item.status) + 1) % order.length]
  const updated = await updateItem(props.item._id, { status: next })
  emit('updated', updated)
}

async function markWatched() {
  if (marking.value) return
  marking.value = true
  try {
    const patch = { status: 'completed' }
    // Fill season progress so the bar and progress modal stay consistent.
    if (props.item.type === 'show' && props.item.seasonProgress?.length) {
      patch.seasonProgress = props.item.seasonProgress.map((s) => ({ ...s, watched: s.episodeCount }))
    }
    const updated = await updateItem(props.item._id, patch)
    emit('updated', updated)
    fireConfetti()
  } finally {
    marking.value = false
  }
}

function fireConfetti() {
  const rect = cardRef.value?.getBoundingClientRect()
  if (!rect) return
  const x = (rect.left + rect.width / 2) / window.innerWidth
  const y = (rect.top + rect.height / 2) / window.innerHeight
  const colors = ['#6366f1', '#a78bfa', '#34d399', '#fbbf24', '#f472b6']

  confetti({ particleCount: 70, spread: 80, origin: { x, y }, colors, scalar: 0.85, startVelocity: 30 })
  setTimeout(() => {
    confetti({ particleCount: 40, spread: 50, origin: { x, y: y - 0.04 }, colors, scalar: 0.65, startVelocity: 18, gravity: 0.6 })
  }, 130)
}

async function confirmDelete() {
  showConfirm.value = false
  deleting.value = true
  await deleteItem(props.item._id)
  emit('deleted', props.item._id)
}
</script>

<template>
  <div ref="cardRef" :class="['group rounded-xl overflow-hidden flex flex-row transition-all backdrop-blur-sm shadow-sm', isList ? '' : isCompact ? 'min-h-28' : 'min-h-36', item.status === 'completed' ? 'bg-green-50/80 dark:bg-green-900/20 ring-1 ring-inset ring-green-500/50 dark:ring-green-500/25 shadow-green-500/10' : item.status === 'watching' ? 'bg-blue-50/80 dark:bg-blue-900/20 ring-1 ring-inset ring-blue-500/50 dark:ring-blue-500/25 shadow-blue-500/10' : 'bg-white/70 dark:bg-slate-800/70 border border-white/60 dark:border-white/8 hover:bg-white/85 dark:hover:bg-slate-800/85 hover:shadow-md']">
    <!-- Poster -->
    <div :class="['relative shrink-0 self-stretch overflow-hidden bg-slate-100 dark:bg-slate-700/60', isList ? 'w-14' : isCompact ? 'w-20' : 'w-24']">
      <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
      <div v-else class="w-full h-full flex items-center justify-center">
        <svg class="w-8 h-8 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h1.5C5.496 19.5 6 18.996 6 18.375m-3.75.125-.375-12a1.125 1.125 0 011.125-1.125h15.75A1.125 1.125 0 0120.625 6.5l-.375 12M6 18.375V7.875C6 7.254 6.504 6.75 7.125 6.75h9.75C17.496 6.75 18 7.254 18 7.875v10.5m0 0c0 .621-.504 1.125-1.125 1.125H7.125" />
        </svg>
      </div>

      <!-- Watch checkbox — hover to reveal on planned -->
      <button
        v-if="item.status === 'planned'"
        @click.stop="markWatched"
        :disabled="marking"
        :title="t('watchlist.card.markWatched')"
        class="cursor-pointer watched-btn absolute top-2 left-2 w-7 h-7 rounded-full border-2 border-white/60 bg-black/40 backdrop-blur-sm flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-all duration-200 hover:border-white hover:bg-black/60 hover:scale-110 disabled:cursor-wait"
      >
        <svg class="w-3.5 h-3.5 text-white/80" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
        </svg>
      </button>

      <!-- Clock badge — always visible on watching, swaps to checkmark on hover -->
      <button
        v-else-if="item.status === 'watching'"
        @click.stop="markWatched"
        :disabled="marking"
        :title="t('watchlist.card.markWatched')"
        class="cursor-pointer watched-btn absolute top-2 left-2 w-7 h-7 rounded-full bg-blue-500 shadow-md flex items-center justify-center transition-all duration-200 hover:bg-green-500 hover:scale-110 disabled:cursor-wait group/clock"
      >
        <svg class="w-3.5 h-3.5 text-white group-hover/clock:hidden" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6l4 2m6-2a10 10 0 11-20 0 10 10 0 0120 0z" />
        </svg>
        <svg class="w-3.5 h-3.5 text-white hidden group-hover/clock:block" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
        </svg>
      </button>

      <!-- Green checkmark — always visible on completed -->
      <div
        v-else
        class="absolute top-2 left-2 w-7 h-7 rounded-full bg-green-500 flex items-center justify-center shadow-md"
      >
        <svg class="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
        </svg>
      </div>

      <!-- Progress button — opens the season/episode modal (shows only) -->
      <button
        v-if="isShow"
        @click.stop="showProgress = true"
        :title="t('watchlist.card.trackEpisodes')"
        class="cursor-pointer watched-btn absolute top-10 left-2 w-7 h-7 rounded-full border-2 border-white/60 bg-black/40 backdrop-blur-sm flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 hover:border-white hover:bg-black/60 hover:scale-110"
      >
        <svg class="w-3.5 h-3.5 text-white/80" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.008v.008H3.75V6.75zm0 5.25h.008v.008H3.75V12zm0 5.25h.008v.008H3.75v-.008z" />
        </svg>
      </button>

      <!-- Streaming logo -->
      <a
        v-if="item.streamingLogo"
        :href="item.watchLink || undefined"
        :target="item.watchLink ? '_blank' : undefined"
        :rel="item.watchLink ? 'noopener noreferrer' : undefined"
        class="absolute bottom-1.5 left-1.5"
        :class="item.watchLink ? 'cursor-pointer' : 'cursor-default'"
        @click.stop
      >
        <img :src="logoUrl(item.streamingLogo)" :alt="item.streamingProvider" class="w-6 h-6 rounded-md object-cover shadow-md" />
      </a>
    </div>

    <!-- Content -->
    <div :class="['flex-1 flex flex-col min-w-0', isList ? 'p-2 gap-0.5' : isCompact ? 'p-3 gap-1' : 'p-4 gap-1.5']">
      <div class="flex items-start justify-between gap-1.5">
        <h3 class="font-semibold text-slate-900 dark:text-white text-sm leading-tight">{{ item.title }}</h3>
        <div class="flex gap-0.5 shrink-0">
          <button
            @click="$emit('edit', item)"
            class="cursor-pointer text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white transition-colors p-1 rounded"
            :title="t('watchlist.card.edit')"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
          </button>
          <button
            @click="showConfirm = true"
            :disabled="deleting"
            class="cursor-pointer text-slate-400 dark:text-slate-500 hover:text-red-500 dark:hover:text-red-400 transition-colors p-1 rounded disabled:opacity-40 disabled:cursor-default"
            :title="t('watchlist.card.delete')"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </button>
        </div>
      </div>

      <div v-if="meta || item.tmdbRating" class="flex items-center gap-1.5">
        <p v-if="meta" class="text-xs text-slate-400 dark:text-slate-500">{{ meta }}</p>
        <div v-if="item.tmdbRating" class="flex items-center gap-0.5 text-xs text-amber-400 ml-auto">
          <svg class="w-3 h-3 fill-current" viewBox="0 0 24 24">
            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
          </svg>
          {{ item.tmdbRating }}
        </div>
      </div>

      <!-- Season progress (shows) -->
      <template v-if="isShow">
        <button
          v-if="totals.totalEp > 0"
          @click.stop="showProgress = true"
          :title="t('watchlist.card.trackProgressCount', { watched: totals.watchedEp, total: totals.totalEp })"
          class="cursor-pointer group/prog flex flex-col gap-1 w-full text-left"
        >
          <div v-if="!isList" class="flex items-center justify-between gap-2 text-xs">
            <span class="text-slate-500 dark:text-slate-400">{{ t('watchlist.card.episodeProgress', { watched: item.status === 'completed' ? totals.totalEp : totals.watchedEp, total: totals.totalEp }) }}</span>
            <span v-if="remainingLabel" class="text-slate-400 dark:text-slate-500">{{ remainingLabel }}</span>
          </div>
          <div class="h-1.5 bg-slate-200/80 dark:bg-slate-700/80 rounded-full overflow-hidden">
            <div
              class="h-full rounded-full transition-all duration-300"
              :class="item.status === 'completed' ? 'bg-green-500' : 'bg-indigo-500 group-hover/prog:bg-indigo-400'"
              :style="{ width: `${progressPct}%` }"
            />
          </div>
        </button>
        <button
          v-else
          @click.stop="showProgress = true"
          class="cursor-pointer self-start flex items-center gap-1 text-xs text-slate-400 dark:text-slate-500 hover:text-indigo-500 dark:hover:text-indigo-400 transition-colors"
        >
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          {{ t('watchlist.card.trackProgress') }}
        </button>
      </template>

      <p v-if="item.notes && !isCompact" class="text-xs text-slate-500 dark:text-slate-400 leading-relaxed">{{ item.notes }}</p>

      <div :class="['flex items-center gap-1.5 flex-wrap mt-auto', isCompact ? 'pt-1' : 'pt-1.5']">
        <span :class="['text-xs font-medium px-2 py-0.5 rounded-full', TYPE_COLORS[item.type]]">
          {{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}
        </span>
        <button
          @click="cycleStatus"
          :class="['cursor-pointer text-xs font-medium px-2 py-0.5 rounded-full transition-opacity hover:opacity-80', STATUS_COLORS[item.status]]"
          :title="t('watchlist.card.cycleStatus')"
        >
          {{ t('watchlist.status.' + item.status) }}
        </button>
        <span v-if="item.rating" class="text-xs text-amber-400 font-medium ml-auto">
          ★ {{ item.rating }}/10
        </span>
      </div>
    </div>
  </div>

  <TemplateModal
    :show="showConfirm"
    :title="t('watchlist.card.removeTitle')"
    :message="t('watchlist.card.removeMessage', { title: item.title })"
    :confirm-label="t('watchlist.card.remove')"
    @confirm="confirmDelete"
    @cancel="showConfirm = false"
  />

  <SeasonProgressModal
    v-if="isShow"
    :show="showProgress"
    :item="item"
    @close="showProgress = false"
    @updated="handleProgressUpdated"
  />
</template>

<style scoped>
.watched-btn {
  transition: opacity 0.2s ease, transform 0.15s ease, background-color 0.15s ease, border-color 0.15s ease;
}

.watched-btn:active {
  transform: scale(0.9);
}
</style>
