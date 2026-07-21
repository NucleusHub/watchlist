<script setup>
import { ref, computed } from 'vue'
import confetti from 'canvas-confetti'
import { updateItem, deleteItem } from '@/api/watchlist.js'
import { logoUrl } from '@/api/tmdb.js'
import { showTotals, watchedFraction, remainingMinutes } from '@/utils/progress.js'
import TemplateModal from '@core/TemplateModal.vue'
import TrashIcon from '@core/TrashIcon.vue'
import SeasonProgressModal from '@/components/SeasonProgressModal.vue'
import RatingControl from '@/components/RatingControl.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { resolveTarget, buildOpenUrl } from '@/utils/openTarget.js'
import { watchlistIndicators } from '@/utils/pluginIndicators.js'
import { Icon } from '@core/icons'
import ArchiveBoxIcon from '@/assets/icons/archive-box.svg?component'
import ClockIcon from '@/assets/icons/clock.svg?component'
import ListBulletIcon from '@/assets/icons/list-bullet.svg?component'
import InfoCircleIcon from '@/assets/icons/info-circle.svg?component'
import StarIcon from '@/assets/icons/star.svg?component'
import CheckCircleIcon from '@/assets/icons/check-circle.svg?component'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { defaults } = useOpenSettings()

// Plugin-contributed card badges (e.g. In Common's "others watching this"),
// filtered to the ones enabled for this user. Empty badges render no DOM.
const indicators = computed(() => watchlistIndicators.filter((i) => isPluginEnabled(i.pluginId)))

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
// Grid (non-list) cards stay minimal — title + one metric — and reveal the full
// metadata/actions in this on-demand detail modal (the ⓘ button on the poster).
const showDetail = ref(false)

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

// Poster click destination — item override, else the per-type global default.
const openUrl = computed(() => buildOpenUrl(resolveTarget(props.item, defaults), props.item))

function openPoster() {
  if (openUrl.value) window.open(openUrl.value, '_blank', 'noopener,noreferrer')
}

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

// The single metric grid cards show for movies (shows use the progress bar).
const runtimeLabel = computed(() => (isShow.value ? null : formatRuntime(props.item.runtime)))

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

async function toggleFavorite() {
  const updated = await updateItem(props.item._id, { favorite: !props.item.favorite })
  emit('updated', updated)
}

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
  <div ref="cardRef" :class="['group rounded-xl overflow-hidden flex transition-all duration-200 ease-out hover:-translate-y-0.5 backdrop-blur-sm shadow-sm', isList ? 'flex-row' : 'flex-col', item.status === 'completed' ? 'bg-green-50/80 dark:bg-green-900/20 ring-1 ring-inset ring-green-500/50 dark:ring-green-500/25 shadow-green-500/10' : item.status === 'watching' ? 'bg-blue-50/80 dark:bg-blue-900/20 ring-1 ring-inset ring-blue-500/50 dark:ring-blue-500/25 shadow-blue-500/10' : 'bg-white/70 dark:bg-slate-800/70 border border-white/60 dark:border-white/8 hover:bg-white/85 dark:hover:bg-slate-800/85 hover:shadow-md']">
    <!-- Poster — fixed 2:3 box in grid views (like Shelf), stretches to row height in list view -->
    <div
      :class="['relative shrink-0 overflow-hidden bg-slate-100 dark:bg-slate-700/60', isList ? 'w-14 self-stretch' : 'w-full aspect-[2/3]', openUrl ? 'cursor-pointer group/poster' : '']"
      @click="openPoster"
      :title="openUrl ? t('watchlist.card.openExternal') : undefined"
    >
      <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
      <div v-else class="w-full h-full flex items-center justify-center">
        <ArchiveBoxIcon class="w-8 h-8 text-slate-300 dark:text-slate-600" />
      </div>

      <!-- Plugin card badges (e.g. In Common) — an absolute overlay so they never
           add to the card's height. Bottom-right, hidden on phone where the
           details (ⓘ) button lives there; the corner is free on desktop. Renders
           no visible box without a match. -->
      <div v-if="indicators.length" class="absolute bottom-1.5 right-1.5 z-20 hidden sm:flex">
        <component
          v-for="ind in indicators"
          :key="ind.pluginId"
          :is="ind.component"
          :item="item"
          variant="overlay"
        />
      </div>

      <!-- Open-on-click affordance — reveals on poster hover (desktop only) -->
      <div
        v-if="openUrl"
        class="pointer-events-none absolute inset-0 hidden sm:flex items-center justify-center bg-black/0 group-hover/poster:bg-black/30 transition-colors"
      >
        <Icon name="externalLink" class="w-5 h-5 text-white opacity-0 group-hover/poster:opacity-100 transition-opacity drop-shadow" />
      </div>

      <!-- Watch checkbox — hover to reveal on planned -->
      <button
        v-if="item.status === 'planned'"
        @click.stop="markWatched"
        :disabled="marking"
        :title="t('watchlist.card.markWatched')"
        class="cursor-pointer watched-btn absolute top-2 left-2 w-7 h-7 rounded-full border-2 border-white/60 bg-black/40 backdrop-blur-sm flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-all duration-200 hover:border-white hover:bg-black/60 hover:scale-110 disabled:cursor-wait"
      >
        <Icon name="checkBold" class="w-3.5 h-3.5 text-white/80" :sw="3" />
      </button>

      <!-- Clock badge — always visible on watching, swaps to checkmark on hover -->
      <button
        v-else-if="item.status === 'watching'"
        @click.stop="markWatched"
        :disabled="marking"
        :title="t('watchlist.card.markWatched')"
        class="cursor-pointer watched-btn absolute top-2 left-2 w-7 h-7 rounded-full bg-blue-500 shadow-md flex items-center justify-center transition-all duration-200 hover:bg-green-500 hover:scale-110 disabled:cursor-wait group/clock"
      >
        <ClockIcon class="w-3.5 h-3.5 text-white group-hover/clock:hidden" />
        <Icon name="checkBold" class="w-3.5 h-3.5 text-white hidden group-hover/clock:block" :sw="3" />
      </button>

      <!-- Green checkmark — always visible on completed -->
      <div
        v-else
        class="absolute top-2 left-2 w-7 h-7 rounded-full bg-green-500 flex items-center justify-center shadow-md"
      >
        <Icon name="checkBold" class="w-3.5 h-3.5 text-white" :sw="3" />
      </div>

      <!-- Progress button — opens the season/episode modal (shows only) -->
      <button
        v-if="isShow"
        @click.stop="showProgress = true"
        :title="t('watchlist.card.trackEpisodes')"
        class="cursor-pointer watched-btn absolute top-10 left-2 w-7 h-7 rounded-full border-2 border-white/60 bg-black/40 backdrop-blur-sm flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 hover:border-white hover:bg-black/60 hover:scale-110"
      >
        <ListBulletIcon class="w-3.5 h-3.5 text-white/80" />
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

      <!-- Favorite heart — always visible when favorited, reveals on hover otherwise -->
      <button
        @click.stop="toggleFavorite"
        :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
        class="nuc-fav nuc-press cursor-pointer absolute top-2 right-2 w-7 h-7 rounded-full bg-black/40 backdrop-blur-sm flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-all duration-200 hover:bg-black/60 hover:scale-110"
        :class="{ '!opacity-100': item.favorite }"
      >
        <FavoriteHeart :active="item.favorite" class="w-4 h-4 text-white/80" />
      </button>

      <!-- Details (ⓘ) — phone grid cards stay lean; this opens the full metadata
           + actions. Phone-only: on desktop the card already shows everything. -->
      <button
        v-if="!isList"
        type="button"
        @click.stop="showDetail = true"
        :title="t('watchlist.card.details')"
        class="sm:hidden nuc-press cursor-pointer absolute bottom-1.5 right-1.5 w-7 h-7 rounded-full bg-black/40 backdrop-blur-sm flex items-center justify-center text-white/80 transition-all duration-200 hover:bg-black/60 hover:scale-110"
      >
        <InfoCircleIcon class="w-4 h-4" />
      </button>
    </div>

    <!-- Content — full on desktop and in list view; on phone the grid cards
         (non-list) collapse to title + one metric, with the rest behind the ⓘ
         detail button. The `sm:` toggles below express "phone grid only". -->
    <div :class="['flex-1 flex flex-col min-w-0', isList ? 'p-2 gap-0.5' : isCompact ? 'p-3 gap-1' : 'p-4 gap-1.5']">
      <div class="flex items-start justify-between gap-1.5">
        <h3
          :class="['font-semibold text-slate-900 dark:text-white text-sm leading-tight', !isList ? 'line-clamp-2 sm:line-clamp-none' : '', openUrl ? 'cursor-pointer hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors' : '']"
          :title="openUrl ? t('watchlist.card.openExternal') : undefined"
          @click="openPoster"
        >{{ item.title }}</h3>
        <!-- Edit/delete — hidden on phone grid (use the ⓘ detail there). -->
        <div :class="['gap-0.5 shrink-0', isList ? 'flex' : 'hidden sm:flex']">
          <button
            @click="$emit('edit', item)"
            class="nuc-press cursor-pointer text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white transition-colors p-1 rounded"
            :title="t('watchlist.card.edit')"
          >
            <Icon name="edit" class="w-3.5 h-3.5" />
          </button>
          <button
            @click="showConfirm = true"
            :disabled="deleting"
            class="nuc-trash nuc-press cursor-pointer text-slate-400 dark:text-slate-500 hover:text-red-500 dark:hover:text-red-400 transition-colors p-1 rounded disabled:opacity-40 disabled:cursor-default"
            :title="t('watchlist.card.delete')"
          >
            <TrashIcon class="w-3.5 h-3.5" stroke-width="2" />
          </button>
        </div>
      </div>

      <!-- Metadata line + TMDB rating — hidden on phone grid. -->
      <div v-if="meta || item.tmdbRating" :class="['items-center gap-1.5', isList ? 'flex' : 'hidden sm:flex']">
        <p v-if="meta" class="text-xs text-slate-400 dark:text-slate-500">{{ meta }}</p>
        <div v-if="item.tmdbRating" class="flex items-center gap-0.5 text-xs text-amber-400 ml-auto">
          <StarIcon class="w-3 h-3 fill-current" />
          {{ item.tmdbRating }}
        </div>
      </div>

      <!-- Movie runtime — phone grid only (desktop shows it in the meta line). -->
      <p v-if="!isList && runtimeLabel" class="sm:hidden text-xs text-slate-400 dark:text-slate-500">{{ runtimeLabel }}</p>

      <!-- Season progress (shows) -->
      <template v-if="isShow">
        <button
          v-if="totals.totalEp > 0"
          @click.stop="showProgress = true"
          :title="t('watchlist.card.trackProgressCount', { watched: totals.watchedEp, total: totals.totalEp })"
          class="cursor-pointer group/prog flex flex-col gap-1 w-full text-left"
        >
          <!-- Episode-count label — grid views, hidden on phone (bar stays). -->
          <div v-if="!isList" :class="['items-center justify-between gap-2 text-xs', 'hidden sm:flex']">
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
          <CheckCircleIcon class="w-3.5 h-3.5" />
          {{ t('watchlist.card.trackProgress') }}
        </button>
      </template>

      <!-- Notes (big desktop cards only) — hidden on phone. -->
      <p v-if="item.notes && !isCompact" class="hidden sm:block text-xs text-slate-500 dark:text-slate-400 leading-relaxed">{{ item.notes }}</p>

      <!-- Type · status · rating — hidden on phone grid. -->
      <div :class="['items-center gap-1.5 flex-wrap mt-auto', isCompact ? 'pt-1' : 'pt-1.5', isList ? 'flex' : 'hidden sm:flex']">
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
        <RatingControl
          v-if="item.rating && !isCompact"
          :model-value="item.rating"
          :max="10"
          readonly
          size="sm"
          :show-value="false"
          class="ml-auto"
        />
        <span v-else-if="item.rating" class="text-xs text-amber-400 font-medium ml-auto">
          ★ {{ item.rating }}/10
        </span>
      </div>
    </div>
  </div>

  <!-- Full details — the "on demand" view behind the ⓘ button on grid cards. -->
  <TemplateModal
    :show="showDetail"
    header
    size="md"
    z="z-[150]"
    :title="item.title"
    :description="meta || ''"
    body-class="px-5 sm:px-6 pb-6 pt-2"
    @cancel="showDetail = false"
  >
    <div class="flex flex-col gap-5">
      <div class="flex gap-4">
        <!-- Poster -->
        <div
          :class="['relative w-28 shrink-0 overflow-hidden rounded-xl bg-slate-100 dark:bg-slate-700/60 aspect-[2/3] ring-1 ring-black/5 dark:ring-white/10', openUrl ? 'cursor-pointer' : '']"
          @click="openPoster"
          :title="openUrl ? t('watchlist.card.openExternal') : undefined"
        >
          <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
          <div v-else class="w-full h-full flex items-center justify-center">
            <ArchiveBoxIcon class="w-8 h-8 text-slate-300 dark:text-slate-600" />
          </div>
        </div>

        <div class="flex-1 min-w-0 flex flex-col gap-3">
          <!-- Actions -->
          <div class="flex items-center gap-0.5 -mt-0.5">
            <button
              v-if="openUrl"
              @click="openPoster"
              :title="t('watchlist.card.openExternal')"
              class="nuc-press cursor-pointer p-1.5 rounded-lg text-slate-400 hover:text-indigo-600 dark:hover:text-indigo-400 hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            >
              <Icon name="externalLink" class="w-5 h-5" :sw="1.75" />
            </button>
            <button
              @click="toggleFavorite"
              :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
              class="nuc-fav nuc-press cursor-pointer p-1.5 rounded-lg hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
              :class="item.favorite ? 'text-rose-500' : 'text-slate-400'"
            >
              <FavoriteHeart :active="item.favorite" class="w-5 h-5" />
            </button>
            <button
              @click="$emit('edit', item); showDetail = false"
              :title="t('watchlist.card.edit')"
              class="nuc-press cursor-pointer p-1.5 rounded-lg text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            >
              <Icon name="edit" class="w-5 h-5" :sw="1.75" />
            </button>
            <button
              @click="showConfirm = true"
              :title="t('watchlist.card.delete')"
              class="nuc-trash nuc-press cursor-pointer p-1.5 rounded-lg text-slate-400 hover:text-red-500 dark:hover:text-red-400 hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            >
              <TrashIcon class="w-5 h-5" stroke-width="1.75" />
            </button>
          </div>

          <!-- Type · status · TMDb rating -->
          <div class="flex items-center gap-1.5 flex-wrap">
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
            <span v-if="item.tmdbRating" class="inline-flex items-center gap-0.5 text-xs text-amber-400">
              <StarIcon class="w-3 h-3 fill-current" />
              {{ item.tmdbRating }}
            </span>
            <component
              v-for="ind in indicators"
              :key="ind.pluginId"
              :is="ind.component"
              :item="item"
            />
          </div>

          <!-- Your rating -->
          <RatingControl
            v-if="item.rating"
            :model-value="item.rating"
            :max="10"
            readonly
            size="sm"
            show-value
          />
        </div>
      </div>

      <!-- Season progress (shows) -->
      <div v-if="isShow" class="flex flex-col gap-2.5 rounded-xl bg-white/60 dark:bg-slate-800/50 border border-white/60 dark:border-white/8 p-4">
        <template v-if="totals.totalEp > 0">
          <div class="flex items-center justify-between gap-2 text-sm">
            <span class="text-slate-500 dark:text-slate-400">{{ t('watchlist.card.episodeProgress', { watched: item.status === 'completed' ? totals.totalEp : totals.watchedEp, total: totals.totalEp }) }}</span>
            <span v-if="remainingLabel" class="text-slate-400 dark:text-slate-500">{{ remainingLabel }}</span>
          </div>
          <div class="h-2 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
            <div class="h-full rounded-full transition-all duration-500" :class="item.status === 'completed' ? 'bg-green-500' : 'bg-indigo-500'" :style="{ width: `${progressPct}%` }" />
          </div>
        </template>
        <button
          @click="showProgress = true"
          class="nuc-press cursor-pointer self-start inline-flex items-center gap-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-3 py-1.5 rounded-lg transition-colors"
        >
          <ListBulletIcon class="w-4 h-4" />
          {{ t('watchlist.card.trackEpisodes') }}
        </button>
      </div>

      <!-- Mark as watched -->
      <button
        v-if="item.status !== 'completed'"
        @click="markWatched"
        :disabled="marking"
        class="nuc-press cursor-pointer self-start inline-flex items-center gap-1.5 bg-green-600/90 hover:bg-green-500 text-white text-sm font-medium px-3 py-1.5 rounded-lg transition-colors disabled:cursor-wait disabled:opacity-60"
      >
        <Icon name="check" class="w-4 h-4" :sw="2.5" />
        {{ t('watchlist.card.markWatched') }}
      </button>

      <!-- Notes -->
      <div v-if="item.notes" class="flex flex-col gap-1">
        <p class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35">{{ t('watchlist.card.notes') }}</p>
        <p class="text-sm text-slate-600 dark:text-slate-300 leading-relaxed whitespace-pre-line">{{ item.notes }}</p>
      </div>
    </div>
  </TemplateModal>

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
