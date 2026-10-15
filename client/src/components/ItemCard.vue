<script setup>
// A title as a poster card, or as a list row in `list` layout (iOS ItemCard / ItemRow).
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import confetti from 'canvas-confetti'
import { updateItem, deleteItem } from '@/api/watchlist.js'
import { watchedFraction, metaLine, markWatchedPatch } from '@/utils/progress.js'
import { itemRoute } from '@/utils/routes.js'
import TemplateModal from '@core/TemplateModal.vue'
import ContextMenu from '@core/ContextMenu.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import SeasonProgressModal from '@/components/SeasonProgressModal.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { useCollections } from '@/composables/useCollections.js'
import { resolveTarget, buildOpenUrl } from '@/utils/openTarget.js'
import { watchlistIndicators } from '@/utils/pluginIndicators.js'
import { ICONS } from '@core/icons'
import Glyph from '@/ui/Glyph.vue'
import { STATUS_COLOR } from '@/ui/palette.js'

const { t } = useI18n()
const router = useRouter()
const { isPluginEnabled } = useRegistry()
const { defaults } = useOpenSettings()
const { applyMembership } = useCollections()

const indicators = computed(() => watchlistIndicators.filter((i) => isPluginEnabled(i.pluginId)))

const props = defineProps({
  item: { type: Object, required: true },
  gridStyle: { type: String, default: 'small' },
  collectionId: { type: String, default: null },
})
const emit = defineEmits(['updated', 'deleted', 'edit', 'manage-collections'])

const isList = computed(() => props.gridStyle === 'list')
const compact = computed(() => props.gridStyle === 'small')
const isShow = computed(() => props.item.type === 'show')
const done = computed(() => props.item.status === 'completed')
const fraction = computed(() => (isShow.value ? watchedFraction(props.item) : 0))
const meta = computed(() => metaLine(props.item, t))
const openUrl = computed(() => buildOpenUrl(resolveTarget(props.item, defaults), props.item))
// TMDb serves smaller renditions; small cards and list thumbnails don't need the w500 poster.
const poster = computed(() => {
  const url = props.item.posterUrl
  return url && props.gridStyle !== 'big' ? url.replace('/t/p/w500/', isList.value ? '/t/p/w154/' : '/t/p/w342/') : url
})

const cardRef = ref(null)
const showConfirm = ref(false)
const marking = ref(false)
const showProgress = ref(false)

const openDetail = () => router.push(itemRoute(props.item._id))

async function toggleFavorite() {
  emit('updated', await updateItem(props.item._id, { favorite: !props.item.favorite }))
}

async function markWatched() {
  if (marking.value || done.value) return
  marking.value = true
  try {
    emit('updated', await updateItem(props.item._id, markWatchedPatch(props.item)))
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
  await deleteItem(props.item._id)
  applyMembership(props.item.collectionIds || [], [])
  emit('deleted', props.item._id)
}

async function removeFromCollection() {
  const prev = props.item.collectionIds || []
  const next = prev.filter((id) => String(id) !== String(props.collectionId))
  const updated = await updateItem(props.item._id, { collectionIds: next })
  applyMembership(prev, updated.collectionIds || next)
  emit('updated', updated)
}

const menu = ref({ show: false, x: 0, y: 0 })
const menuItems = computed(() => [
  { label: t('watchlist.card.details'), icon: ICONS.eye, action: openDetail },
  ...(openUrl.value ? [{ label: t('watchlist.card.openExternal'), icon: ICONS.externalLink, action: () => window.open(openUrl.value, '_blank', 'noopener,noreferrer') }] : []),
  { label: t('watchlist.card.edit'), icon: ICONS.pencil, action: () => emit('edit', props.item) },
  ...(isShow.value ? [{ label: t('watchlist.card.trackEpisodes'), icon: ICONS.check, action: () => (showProgress.value = true) }] : []),
  { label: t('watchlist.collections.manage'), icon: ICONS.folder, action: () => emit('manage-collections', props.item) },
  ...(props.collectionId ? [{ label: t('watchlist.collections.removeFromThis'), icon: ICONS.minus, action: removeFromCollection }] : []),
  { label: props.item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite'), iconHeart: true, iconActive: props.item.favorite, action: toggleFavorite },
  { divider: true },
  { label: t('watchlist.card.delete'), iconTrash: true, danger: true, action: () => (showConfirm.value = true) },
])
const openMenu = (e) => (menu.value = { show: true, x: e.clientX, y: e.clientY })
</script>

<template>
  <!-- List layout: a glass row. -->
  <div
    v-if="isList"
    ref="cardRef"
    class="wl-row wl-surface rounded-[20px] !py-2.5 !px-3.5 cursor-pointer"
    @click="openDetail"
    @contextmenu.prevent="openMenu"
  >
    <div v-squircle class="relative w-[52px] h-[78px] shrink-0 rounded-[8px] overflow-hidden bg-[var(--wl-well)] grid place-items-center">
      <img v-if="item.posterUrl" :src="poster" :alt="item.title" loading="lazy" decoding="async" class="w-full h-full object-cover" />
      <Glyph v-else :name="isShow ? 'tv' : 'film'" :sw="1.25" class="w-6 h-6 text-[var(--wl-text-2)]" />
    </div>
    <div class="min-w-0 flex-1 flex flex-col gap-1">
      <h3 :class="['font-semibold leading-snug line-clamp-2', done ? 'text-[var(--wl-text-2)]' : '']">{{ item.title }}</h3>
      <p v-if="meta" class="wl-sub truncate">{{ meta }}</p>
      <div class="flex items-center gap-1.5 flex-wrap">
        <span class="wl-tag"><span class="w-1.5 h-1.5 rounded-full" :style="{ background: STATUS_COLOR[item.status] }" />{{ t('watchlist.status.' + item.status) }}</span>
        <span v-if="item.genres?.[0]" class="wl-tag">{{ item.genres[0] }}</span>
        <span v-if="item.rating" class="wl-tag text-amber-500">★ {{ item.rating }}</span>
      </div>
    </div>
    <div class="flex flex-col gap-2 shrink-0">
      <button
        type="button"
        :disabled="marking"
        :title="done ? t('watchlist.detail.watched') : t('watchlist.card.markWatched')"
        class="nuc-press cursor-pointer w-7 h-7 rounded-full grid place-items-center"
        :style="done ? { background: STATUS_COLOR.completed } : item.status === 'watching' ? { background: STATUS_COLOR.watching } : { boxShadow: 'inset 0 0 0 1.6px var(--wl-text-2)' }"
        @click.stop="markWatched"
      >
        <Glyph v-if="done" name="checkBold" :sw="3" class="w-3.5 h-3.5 text-white" />
        <Glyph v-else-if="item.status === 'watching'" name="clock" :sw="2.25" class="w-3.5 h-3.5 text-white" />
      </button>
      <button
        type="button"
        :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
        :class="['nuc-fav nuc-press cursor-pointer w-7 h-7 rounded-full grid place-items-center', item.favorite ? 'text-rose-500' : 'text-[var(--wl-text-2)]']"
        @click.stop="toggleFavorite"
      >
        <FavoriteHeart :active="item.favorite" class="w-[18px] h-[18px]" />
      </button>
    </div>
  </div>

  <!-- Grid layouts: the poster with its buttons, the title under it. -->
  <div v-else ref="cardRef" class="group flex flex-col gap-2 cursor-pointer" @click="openDetail" @contextmenu.prevent="openMenu">
    <div
      :class="['relative aspect-[2/3] shadow-[0_8px_20px_-8px_rgb(0_0_0/0.45)] transition-transform duration-300 group-hover:-translate-y-1', compact ? 'rounded-[14px]' : 'rounded-[18px]']"
    >
      <div v-squircle :class="['absolute inset-0 overflow-hidden bg-[var(--wl-well)] grid place-items-center', compact ? 'rounded-[14px]' : 'rounded-[18px]']">
        <img v-if="item.posterUrl" :src="poster" :alt="item.title" loading="lazy" decoding="async" class="w-full h-full object-cover" />
        <Glyph v-else :name="isShow ? 'tv' : 'film'" :sw="1" class="w-9 h-9 text-[var(--wl-text-2)]" />
      </div>

      <button
        type="button"
        :disabled="marking"
        :title="done ? t('watchlist.detail.watched') : t('watchlist.card.markWatched')"
        :class="['absolute rounded-full grid place-items-center nuc-press cursor-pointer transition-transform hover:scale-110', compact ? 'top-1.5 left-1.5 w-[26px] h-[26px]' : 'top-2 left-2 w-[30px] h-[30px]']"
        :style="done ? { background: STATUS_COLOR.completed } : item.status === 'watching' ? { background: STATUS_COLOR.watching + 'e6' } : { background: 'rgb(0 0 0 / 0.35)', boxShadow: 'inset 0 0 0 1.6px rgb(255 255 255 / 0.85)' }"
        @click.stop="markWatched"
      >
        <Glyph v-if="done" name="checkBold" :sw="3.25" class="w-[45%] h-[45%] text-white" />
        <Glyph v-else-if="item.status === 'watching'" name="clock" :sw="2.25" class="w-[50%] h-[50%] text-white" />
      </button>

      <button
        v-if="item.favorite || !compact"
        type="button"
        :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
        :class="['nuc-fav absolute rounded-full grid place-items-center bg-black/35 text-white nuc-press cursor-pointer transition-transform hover:scale-110', compact ? 'top-1.5 right-1.5 w-[26px] h-[26px]' : 'top-2 right-2 w-[30px] h-[30px]']"
        @click.stop="toggleFavorite"
      >
        <FavoriteHeart :active="item.favorite" class="w-[60%] h-[60%]" stroke-width="2" />
      </button>

      <div v-if="indicators.length" class="absolute bottom-2 right-2 hidden sm:flex" @click.stop>
        <component :is="ind.component" v-for="ind in indicators" :key="ind.pluginId" :item="item" variant="overlay" />
      </div>

      <div v-if="fraction > 0 && fraction < 1" class="absolute inset-x-2.5 bottom-2.5 h-1 rounded-full bg-white/25 overflow-hidden">
        <div class="h-full rounded-full" :style="{ width: `${fraction * 100}%`, background: STATUS_COLOR.watching }" />
      </div>
    </div>

    <div class="px-0.5 flex flex-col gap-0.5">
      <h3 :class="['font-semibold leading-snug line-clamp-2', compact ? 'text-[13px]' : 'text-[15px]', done ? 'text-[var(--wl-text-2)]' : '']">{{ item.title }}</h3>
      <p v-if="meta" :class="['text-[var(--wl-text-2)] truncate', compact ? 'text-[11px]' : 'text-xs']">{{ meta }}</p>
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

  <SeasonProgressModal v-if="isShow" :show="showProgress" :item="item" @close="showProgress = false" @updated="emit('updated', $event)" />

  <ContextMenu :show="menu.show" :x="menu.x" :y="menu.y" :items="menuItems" @close="menu.show = false" />
</template>
