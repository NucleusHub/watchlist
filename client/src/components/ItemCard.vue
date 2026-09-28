<script setup>
import { ref, computed, watch } from 'vue'
import confetti from 'canvas-confetti'
import { updateItem, deleteItem } from '@/api/watchlist.js'
import { logoUrl } from '@/api/tmdb.js'
import { showTotals, watchedFraction, remainingMinutes } from '@/utils/progress.js'
import TemplateModal from '@core/TemplateModal.vue'
import TrashIcon from '@core/TrashIcon.vue'
import ContextMenu from '@core/ContextMenu.vue'
import { useLongPress } from '@/composables/useLongPress.js'
import { useSwipeActions } from '@/composables/useSwipeActions.js'
import { haptic } from '@/native.js'
import SeasonProgressModal from '@/components/SeasonProgressModal.vue'
import RatingControl from '@/components/RatingControl.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { useCollections } from '@/composables/useCollections.js'
import { resolveTarget, buildOpenUrl } from '@/utils/openTarget.js'
import { watchlistIndicators } from '@/utils/pluginIndicators.js'
import { Icon, ICONS } from '@core/icons'
import ArchiveBoxIcon from '@/assets/icons/archive-box.svg?component'
import ClockIcon from '@/assets/icons/clock.svg?component'
import ListBulletIcon from '@/assets/icons/list-bullet.svg?component'
import InfoCircleIcon from '@/assets/icons/info-circle.svg?component'
import StarIcon from '@/assets/icons/star.svg?component'
import CheckCircleIcon from '@/assets/icons/check-circle.svg?component'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { defaults } = useOpenSettings()
const { applyMembership } = useCollections()

const indicators = computed(() => watchlistIndicators.filter((i) => isPluginEnabled(i.pluginId)))

const props = defineProps({
  item: { type: Object, required: true },
  gridStyle: { type: String, default: 'small' },
  collectionId: { type: String, default: null },
})

const isList    = computed(() => props.gridStyle === 'list')
const isCompact = computed(() => props.gridStyle === 'list' || props.gridStyle === 'small')
const emit = defineEmits(['updated', 'deleted', 'edit', 'manage-collections'])

const STATUS_COLORS = {
  planned:   'bg-[#eb6834] dark:bg-[#d95926]',
  watching:  'bg-[#2a78d6] dark:bg-[#3987e5]',
  completed: 'bg-[#1baf7a] dark:bg-[#199e70]',
}

const TAG = 'shrink-0 text-xs font-medium px-2 py-0.5 rounded-full bg-black/[0.05] dark:bg-white/[0.08] text-slate-600 dark:text-white/70'

const CARD_GENRES = 2
const cardGenres = computed(() => (props.item.genres ?? []).slice(0, CARD_GENRES))
const extraGenres = computed(() => Math.max(0, (props.item.genres?.length ?? 0) - CARD_GENRES))

const cardRef = ref(null)
const deleting = ref(false)
const showConfirm = ref(false)
const marking = ref(false)
const showProgress = ref(false)
const showDetail = ref(false)

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
  haptic('Light')
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
  haptic('Light')
  marking.value = true
  try {
    const patch = { status: 'completed' }
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
  applyMembership(props.item.collectionIds || [], [])
  emit('deleted', props.item._id)
}

async function removeFromCollection() {
  if (!props.collectionId) return
  const prev = props.item.collectionIds || []
  const next = prev.filter((id) => String(id) !== String(props.collectionId))
  const updated = await updateItem(props.item._id, { collectionIds: next })
  applyMembership(prev, updated.collectionIds || next)
  emit('updated', updated)
}

const menu = ref({ show: false, x: 0, y: 0 })
const menuItems = computed(() => {
  const items = [
    { label: t('watchlist.card.edit'), icon: ICONS.pencil, action: () => emit('edit', props.item) },
    { label: t('watchlist.collections.manage'), icon: ICONS.folder, action: () => emit('manage-collections', props.item) },
  ]
  if (isShow.value) {
    items.push({ label: t('watchlist.card.trackEpisodes'), icon: ICONS.menu, action: () => (showProgress.value = true) })
  }
  if (props.collectionId) {
    items.push({ label: t('watchlist.collections.removeFromThis'), icon: ICONS.minus, action: removeFromCollection })
  }
  items.push(
    { label: props.item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite'), iconHeart: true, iconActive: props.item.favorite, action: toggleFavorite },
    { divider: true },
    { label: t('watchlist.card.delete'), iconTrash: true, danger: true, action: () => (showConfirm.value = true) },
  )
  return items.map((it) => (it.action ? { ...it, action: () => { haptic('Light'); it.action() } } : it))
})
function openMenu(e) {
  menu.value = { show: true, x: e.clientX, y: e.clientY }
}
const longPress = useLongPress(({ x, y }) => {
  menu.value = { show: true, x, y }
})
const isCompleted = computed(() => props.item.status === 'completed')
const swipe = useSwipeActions({
  enabled: computed(() => isList.value),
  shortDir: 1,
  // Nothing left to complete on a completed item, so its swipe favorites it instead.
  onShort: () => (isCompleted.value ? toggleFavorite() : markWatched()),
  onFull: () => { showConfirm.value = true },
})
watch(showConfirm, (v) => { if (!v && !deleting.value) swipe.reset() })
// Whether the swipe will favorite (fills when armed) or unfavorite (empties).
const swipeHeartFilled = computed(() => props.item.favorite !== swipe.shortArmed.value)
const swipeStyle = computed(() => {
  const x = swipe.offset.value
  if (!x) return undefined
  return { transform: `translateX(${x}px)`, opacity: swipe.leaving.value ? 0 : 1 }
})

function openMenuFrom(e) {
  const r = e.currentTarget.getBoundingClientRect()
  menu.value = { show: true, x: r.right, y: r.bottom + 6 }
}
</script>

<template>
  <div
    :class="['relative h-full', { 'z-10': menu.show }]"
    :data-no-swipe="isList ? '' : undefined"
    v-on="swipe.handlers"
    @click.capture="swipe.onClickCapture"
  >
  <template v-if="isList && swipe.offset.value">
    <div
      v-if="swipe.offset.value > 0"
      :class="['swipe-bg', isCompleted ? 'swipe-fav' : 'swipe-done', { 'is-armed': swipe.shortArmed.value }]"
      :style="{ width: `${swipe.offset.value + 24}px` }"
    >
      <svg v-if="isCompleted" viewBox="0 0 24 24" class="swipe-icon w-6 h-6" stroke="currentColor" stroke-width="2" stroke-linejoin="round" :fill="swipeHeartFilled ? 'currentColor' : 'none'">
        <path d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z" />
      </svg>
      <Icon v-else name="checkBold" class="swipe-icon w-6 h-6" :sw="3" />
    </div>
    <div
      v-else
      :class="['swipe-bg swipe-del', { 'is-armed': swipe.fullArmed.value }]"
      :style="{ width: `${-swipe.offset.value + 24}px` }"
    >
      <TrashIcon class="swipe-icon w-6 h-6" stroke-width="2" />
    </div>
  </template>
  <div
    ref="cardRef"
    v-on="longPress.handlers"
    @click.capture="longPress.onClickCapture"
    @contextmenu.prevent="openMenu"
    :style="swipeStyle"
    :class="['item-card lg-glass group h-full rounded-2xl overflow-hidden flex', isList ? 'flex-row' : 'flex-col', swipe.dragging.value ? 'is-dragging' : '', { 'is-pressing': longPress.pressing.value, 'is-lifted': menu.show }]"
  >
    <div
      :class="['relative shrink-0 overflow-hidden bg-black/[0.05] dark:bg-white/[0.05]', isList ? 'w-[52px] h-[78px] self-center ml-2 my-2 rounded-lg' : 'w-full aspect-[2/3]', openUrl ? 'cursor-pointer group/poster' : '']"
      @click="openPoster"
      :title="openUrl ? t('watchlist.card.openExternal') : undefined"
    >
      <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" draggable="false" class="w-full h-full object-cover" />
      <div v-else class="w-full h-full flex items-center justify-center">
        <ArchiveBoxIcon class="w-8 h-8 text-slate-300 dark:text-slate-600" />
      </div>

      <div v-if="indicators.length" class="absolute bottom-1.5 right-1.5 z-20 hidden sm:flex">
        <component
          v-for="ind in indicators"
          :key="ind.pluginId"
          :is="ind.component"
          :item="item"
          variant="overlay"
        />
      </div>

      <div
        v-if="openUrl"
        class="pointer-events-none absolute inset-0 hidden sm:flex items-center justify-center bg-black/0 group-hover/poster:bg-black/30 transition-colors"
      >
        <Icon name="externalLink" class="w-5 h-5 text-white opacity-0 group-hover/poster:opacity-100 transition-opacity drop-shadow" />
      </div>

      <template v-if="!isList">
      <button
        v-if="item.status === 'planned'"
        @click.stop="markWatched"
        :disabled="marking"
        :title="t('watchlist.card.markWatched')"
        class="cursor-pointer watched-btn absolute top-2 left-2 w-7 h-7 rounded-full border-2 border-white/60 bg-black/30 backdrop-blur-md shadow-[inset_0_1px_0_rgba(255,255,255,0.25)] flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-all duration-200 hover:border-white hover:bg-black/50 hover:scale-110 disabled:cursor-wait"
      >
        <Icon name="checkBold" class="w-3.5 h-3.5 text-white/80" :sw="3" />
      </button>

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

      <div
        v-else
        class="absolute top-2 left-2 w-7 h-7 rounded-full bg-green-500 flex items-center justify-center shadow-md"
      >
        <Icon name="checkBold" class="w-3.5 h-3.5 text-white" :sw="3" />
      </div>

      <button
        v-if="isShow"
        @click.stop="showProgress = true"
        :title="t('watchlist.card.trackEpisodes')"
        class="cursor-pointer watched-btn absolute top-10 left-2 w-7 h-7 rounded-full border-2 border-white/60 bg-black/30 backdrop-blur-md shadow-[inset_0_1px_0_rgba(255,255,255,0.25)] flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 hover:border-white hover:bg-black/50 hover:scale-110"
      >
        <ListBulletIcon class="w-3.5 h-3.5 text-white/80" />
      </button>
      </template>

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

      <button
        v-if="!isList"
        @click.stop="toggleFavorite"
        :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
        class="nuc-fav nuc-press cursor-pointer absolute top-2 right-2 w-7 h-7 rounded-full bg-black/30 backdrop-blur-md shadow-[inset_0_1px_0_rgba(255,255,255,0.25)] flex items-center justify-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-all duration-200 hover:bg-black/50 hover:scale-110"
        :class="{ '!opacity-100': item.favorite }"
      >
        <FavoriteHeart :active="item.favorite" class="w-4 h-4 text-white/80" />
      </button>

      <button
        v-if="!isList"
        type="button"
        @click.stop="showDetail = true"
        :title="t('watchlist.card.details')"
        class="sm:hidden nuc-press cursor-pointer absolute bottom-1.5 right-1.5 w-7 h-7 rounded-full bg-black/30 backdrop-blur-md shadow-[inset_0_1px_0_rgba(255,255,255,0.25)] flex items-center justify-center text-white/80 transition-all duration-200 hover:bg-black/50 hover:scale-110"
      >
        <InfoCircleIcon class="w-4 h-4" />
      </button>
    </div>

    <div :class="['flex-1 flex flex-col min-w-0', isList ? 'py-2.5 pl-3 pr-1 gap-0.5' : isCompact ? 'p-3 gap-1' : 'p-4 gap-1.5']">
      <div class="flex items-start justify-between gap-1.5">
        <h3
          :class="['font-semibold text-slate-900 dark:text-white text-sm leading-tight', !isList ? 'line-clamp-2 sm:line-clamp-none' : '', openUrl ? 'cursor-pointer hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors' : '']"
          :title="openUrl ? t('watchlist.card.openExternal') : undefined"
          @click="openPoster"
        >{{ item.title }}</h3>
        <div v-if="!isList" class="hidden sm:flex gap-0.5 shrink-0">
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

      <div v-if="meta || item.tmdbRating" :class="['items-start gap-1.5', isList ? 'flex' : 'hidden sm:flex']">
        <p v-if="meta" class="min-w-0 flex-1 text-xs text-slate-400 dark:text-slate-500 leading-snug line-clamp-2">{{ meta }}</p>
        <div v-if="item.tmdbRating" class="shrink-0 flex items-center gap-0.5 text-xs text-amber-400 mt-px">
          <StarIcon class="w-3 h-3 fill-current" />
          {{ item.tmdbRating }}
        </div>
      </div>

      <p v-if="!isList && runtimeLabel" class="sm:hidden text-xs text-slate-400 dark:text-slate-500">{{ runtimeLabel }}</p>

      <p v-if="item.notes && !isCompact" class="hidden sm:block text-xs text-slate-500 dark:text-slate-400 leading-relaxed line-clamp-2">{{ item.notes }}</p>

      <div :class="['mt-auto flex flex-col', isList ? 'gap-1 pt-1' : isCompact ? 'gap-1.5 pt-1.5' : 'gap-2 pt-2']">
        <template v-if="isShow">
          <button
            v-if="totals.totalEp > 0"
            @click.stop="showProgress = true"
            :title="t('watchlist.card.trackProgressCount', { watched: totals.watchedEp, total: totals.totalEp })"
            class="cursor-pointer group/prog flex flex-col gap-1 w-full text-left"
          >
            <div v-if="!isList" :class="['items-center justify-between gap-2 text-xs min-w-0', 'hidden sm:flex']">
              <span class="min-w-0 truncate text-slate-500 dark:text-slate-400">{{ t('watchlist.card.episodeProgress', { watched: item.status === 'completed' ? totals.totalEp : totals.watchedEp, total: totals.totalEp }) }}</span>
              <span v-if="remainingLabel" class="shrink-0 text-slate-400 dark:text-slate-500">{{ remainingLabel }}</span>
            </div>
            <div class="h-1 bg-black/[0.07] dark:bg-white/10 rounded-full overflow-hidden">
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

        <div :class="['items-center gap-1.5 flex-wrap', isList ? 'flex' : 'hidden sm:flex']">
          <span :class="TAG">
            {{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}
          </span>
          <button
            @click="cycleStatus"
            :class="[TAG, 'cursor-pointer inline-flex items-center gap-1.5 transition-opacity hover:opacity-80']"
            :title="t('watchlist.card.cycleStatus')"
          >
            <span :class="['w-1.5 h-1.5 rounded-full', STATUS_COLORS[item.status]]" />
            {{ t('watchlist.status.' + item.status) }}
          </button>
          <template v-if="gridStyle !== 'small'">
            <span
              v-for="g in cardGenres"
              :key="g"
              :class="TAG"
            >
              {{ g }}
            </span>
            <span v-if="extraGenres" class="shrink-0 text-xs text-slate-400 dark:text-slate-500">+{{ extraGenres }}</span>
          </template>
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

    <div v-if="isList" class="shrink-0 flex flex-col items-center justify-center gap-1 pr-2 py-2">
      <button
        v-if="item.status !== 'completed'"
        @click.stop="markWatched"
        :disabled="marking"
        :title="t('watchlist.card.markWatched')"
        :class="['list-act nuc-press cursor-pointer disabled:cursor-wait', item.status === 'watching' ? 'bg-blue-500 text-white hover:bg-green-500 group/clock' : 'list-act-idle']"
      >
        <template v-if="item.status === 'watching'">
          <ClockIcon class="w-3.5 h-3.5 group-hover/clock:hidden" />
          <Icon name="checkBold" class="w-3.5 h-3.5 hidden group-hover/clock:block" :sw="3" />
        </template>
        <Icon v-else name="checkBold" class="w-3.5 h-3.5" :sw="3" />
      </button>
      <span v-else class="list-act bg-green-500 text-white">
        <Icon name="checkBold" class="w-3.5 h-3.5" :sw="3" />
      </span>
      <button
        @click.stop="toggleFavorite"
        :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
        class="list-act list-act-idle nuc-fav nuc-press cursor-pointer"
      >
        <FavoriteHeart :active="item.favorite" class="w-4 h-4" />
      </button>
      <button
        @click.stop="openMenuFrom"
        :title="t('watchlist.header.menu')"
        class="list-act list-act-idle nuc-press cursor-pointer"
      >
        <Icon name="kebab" class="w-4 h-4" />
      </button>
    </div>
  </div>
  </div>

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
              @click="$emit('manage-collections', item); showDetail = false"
              :title="t('watchlist.collections.manage')"
              class="nuc-press cursor-pointer p-1.5 rounded-lg text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            >
              <Icon name="folder" class="w-5 h-5" :sw="1.75" />
            </button>
            <button
              @click="showConfirm = true"
              :title="t('watchlist.card.delete')"
              class="nuc-trash nuc-press cursor-pointer p-1.5 rounded-lg text-slate-400 hover:text-red-500 dark:hover:text-red-400 hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            >
              <TrashIcon class="w-5 h-5" stroke-width="1.75" />
            </button>
          </div>

          <div v-if="item.genres?.length" class="flex items-center gap-1.5 flex-wrap">
            <span
              v-for="g in item.genres"
              :key="g"
              :class="TAG"
            >
              {{ g }}
            </span>
          </div>

          <div class="flex items-center gap-1.5 flex-wrap">
            <span :class="TAG">
              {{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}
            </span>
            <button
              @click="cycleStatus"
              :class="[TAG, 'cursor-pointer inline-flex items-center gap-1.5 transition-opacity hover:opacity-80']"
              :title="t('watchlist.card.cycleStatus')"
            >
              <span :class="['w-1.5 h-1.5 rounded-full', STATUS_COLORS[item.status]]" />
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

      <button
        v-if="item.status !== 'completed'"
        @click="markWatched"
        :disabled="marking"
        class="nuc-press cursor-pointer self-start inline-flex items-center gap-1.5 bg-green-600/90 hover:bg-green-500 text-white text-sm font-medium px-3 py-1.5 rounded-lg transition-colors disabled:cursor-wait disabled:opacity-60"
      >
        <Icon name="check" class="w-4 h-4" :sw="2.5" />
        {{ t('watchlist.card.markWatched') }}
      </button>

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

  <ContextMenu :show="menu.show" :x="menu.x" :y="menu.y" :items="menuItems" @close="menu.show = false" />
</template>

<style scoped>
.watched-btn {
  transition: opacity 0.2s ease, transform 0.15s ease, background-color 0.15s ease, border-color 0.15s ease;
}

.watched-btn:active {
  transform: scale(0.9);
}

.item-card {
  -webkit-touch-callout: none;
  -webkit-user-select: none;
  user-select: none;
}
.item-card {
  transition: transform 0.35s cubic-bezier(0.2, 0.9, 0.3, 1), opacity 0.22s ease, box-shadow 0.3s ease;
}
.item-card.is-dragging { transition: none; }
@media (hover: hover) {
  .item-card:hover { transform: translateY(-2px); }
}
.item-card.is-pressing {
  transform: scale(0.96);
  transition: transform 0.3s cubic-bezier(0.3, 0.6, 0.3, 1);
}
.item-card.is-lifted {
  animation: card-lift 0.4s cubic-bezier(0.2, 0.9, 0.3, 1.2) forwards;
  box-shadow: 0 26px 50px -14px rgba(15, 23, 42, 0.45), 0 0 0 1px rgba(99, 102, 241, 0.25);
}
.dark .item-card.is-lifted {
  box-shadow: 0 26px 56px -14px rgba(0, 0, 0, 0.85), 0 0 0 1px rgba(167, 139, 250, 0.3);
}
@keyframes card-lift {
  0% { transform: scale(0.96); }
  55% { transform: scale(1.045); }
  100% { transform: scale(1.02); }
}

.swipe-bg {
  position: absolute;
  top: 0;
  bottom: 0;
  display: flex;
  align-items: center;
  border-radius: 1rem;
  color: #fff;
  transition: background-color 0.2s ease;
}
.swipe-del {
  right: 0;
  justify-content: flex-end;
  padding-right: 22px;
  background: rgba(239, 68, 68, 0.55);
}
.swipe-del.is-armed { background: #ef4444; }
.swipe-done {
  left: 0;
  justify-content: flex-start;
  padding-left: 22px;
  background: rgba(27, 175, 122, 0.5);
}
.swipe-done.is-armed { background: #1baf7a; }
.swipe-fav {
  left: 0;
  justify-content: flex-start;
  padding-left: 22px;
  background: rgba(244, 63, 94, 0.5);
}
.swipe-fav.is-armed { background: #f43f5e; }
.swipe-icon {
  transition: transform 0.25s cubic-bezier(0.2, 0.9, 0.3, 1.4);
}
.is-armed .swipe-icon { transform: scale(1.3); }

@media (prefers-reduced-motion: reduce) {
  .item-card.is-lifted { animation: none; }
}

.list-act {
  width: 28px;
  height: 28px;
  border-radius: 9999px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background-color 0.15s ease, color 0.15s ease;
}
.list-act-idle {
  color: rgb(100 116 139);
  background: rgba(15, 23, 42, 0.06);
  box-shadow: inset 0 0 0 1px rgba(15, 23, 42, 0.06);
}
.dark .list-act-idle {
  color: rgba(255, 255, 255, 0.7);
  background: rgba(255, 255, 255, 0.08);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.1), inset 0 0 0 1px rgba(255, 255, 255, 0.06);
}
.list-act-idle:hover { color: rgb(15 23 42); }
.dark .list-act-idle:hover { color: #fff; }
</style>
