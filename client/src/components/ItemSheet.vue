<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import TemplateModal from '@core/TemplateModal.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { Spinner, ICONS } from '@core/icons'
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
import {
  showTotals, watchedFraction, remainingMinutes, formatRuntime, metaLine, markWatchedPatch,
  resetActions, resetPatch, clock,
} from '@/utils/progress.js'
import TrailersSection from '@/components/TrailersSection.vue'
import ItemPluginSections from '@/components/ItemPluginSections.vue'
import RatingControl from '@/components/RatingControl.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ManageCollectionsModal from '@/components/ManageCollectionsModal.vue'
import SeasonProgressModal from '@/components/SeasonProgressModal.vue'
import { itemsChanged, closeItemSheet } from '@/composables/useItemSheet.js'
import GlassCircleButton from '@/ui/GlassCircleButton.vue'
import WlSection from '@/ui/WlSection.vue'
import WlRow from '@/ui/WlRow.vue'
import Glyph from '@/ui/Glyph.vue'
import EmptyState from '@/ui/EmptyState.vue'
import ContextMenu from '@core/ContextMenu.vue'
import { STATUS_COLOR, INTEREST, genreColor } from '@/ui/palette.js'

const props = defineProps({ id: { type: String, required: true } })

const { t } = useI18n()
const router = useRouter()
const { isPluginEnabled } = useRegistry()
const { defaults } = useOpenSettings()
const { collections, applyMembership } = useCollections()
const dna = useMovieDNA()

const STATUSES = ['planned', 'watching', 'completed']
const FLAME = [
  'M15.362 5.214A8.252 8.252 0 0 1 12 21 8.25 8.25 0 0 1 6.038 7.047 8.287 8.287 0 0 0 9 9.601a8.983 8.983 0 0 1 3.361-6.867 8.21 8.21 0 0 0 3 2.48Z',
  'M12 18a3.75 3.75 0 0 0 .495-7.468 5.99 5.99 0 0 0-1.925 3.547 5.975 5.975 0 0 1-2.133-1.001A3.75 3.75 0 0 0 12 18Z',
]

const item = ref(null)
const loading = ref(true)
const extras = ref(null)
const marking = ref(false)
const showEdit = ref(false)
const showManage = ref(false)
const showProgress = ref(false)
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
  itemsChanged()
  return updated
}

function setItem(updated) {
  item.value = updated
  itemsChanged()
}

const close = () => closeItemSheet(router)
const onKey = (e) => {
  // Nested modals handle their own Escape.
  if (e.key === 'Escape' && !document.querySelector('.tm-panel')) close()
}
onMounted(() => {
  document.body.style.overflow = 'hidden'
  window.addEventListener('keydown', onKey)
})
onBeforeUnmount(() => {
  document.body.style.overflow = ''
  window.removeEventListener('keydown', onKey)
})

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
    itemsChanged()
    close()
  } finally {
    deleting.value = false
  }
}

function openPoster() {
  if (openUrl.value) window.open(openUrl.value, '_blank', 'noopener,noreferrer')
}

// The ⋯ menu (iOS ItemMenu): status, collections, links and delete.
const menu = ref({ show: false, x: 0, y: 0 })
const menuItems = computed(() => [
  ...STATUSES.filter((s) => s !== item.value.status).map((s) => ({ label: t('watchlist.detail.markAs', { status: t('watchlist.status.' + s) }), icon: ICONS.check, action: () => setStatus(s) })),
  { divider: true },
  { label: t('watchlist.collections.manage'), icon: ICONS.folder, action: () => (showManage.value = true) },
  ...(isShow.value ? [{ label: t('watchlist.card.trackEpisodes'), icon: ICONS.check, action: () => (showProgress.value = true) }] : []),
  ...(openUrl.value ? [{ label: t('watchlist.detail.openOn', { target: targetLabel.value }), icon: ICONS.externalLink, action: openPoster }] : []),
  ...(resets.value.length ? [{ label: t('watchlist.detail.resetProgress'), icon: ICONS.refresh, action: () => (showReset.value = true) }] : []),
  { divider: true },
  { label: t('watchlist.card.delete'), iconTrash: true, danger: true, action: () => (showDelete.value = true) },
])
function openMenu(e) {
  const r = e.currentTarget.getBoundingClientRect()
  menu.value = { show: true, x: r.right - 220, y: r.bottom + 8 }
}
</script>

<template>
  <div class="fixed inset-0 z-[110] flex items-end sm:items-center justify-center sm:p-6">
    <div class="sheet-backdrop absolute inset-0 bg-black/45 backdrop-blur-md" @click="close" />
    <div
      role="dialog"
      aria-modal="true"
      class="sheet-panel wl-card relative w-full sm:max-w-[760px] h-[94vh] sm:h-auto sm:max-h-[90vh] overflow-y-auto overscroll-contain no-scrollbar rounded-t-[32px] sm:rounded-[32px] bg-[color-mix(in_oklab,var(--wl-base)_86%,transparent)] backdrop-blur-[40px] border-[0.5px] border-[var(--wl-glass-edge)] shadow-[0_30px_80px_-20px_rgb(0_0_0/0.6)]"
    >
      <div v-if="item?.posterUrl" class="absolute inset-x-0 top-0 h-[420px] overflow-hidden pointer-events-none" aria-hidden="true">
        <img :src="item.posterUrl" alt="" class="w-full h-full object-cover scale-125 blur-3xl opacity-45 [mask-image:linear-gradient(to_bottom,black,transparent)]" />
      </div>

      <div class="sticky top-0 z-10 flex items-center gap-2 px-4 pt-4 pb-2">
        <GlassCircleButton icon="close" :title="t('watchlist.detail.close')" @click="close" />
        <div class="flex-1" />
        <template v-if="item">
          <GlassCircleButton icon="pencil" :title="t('watchlist.card.edit')" @click="showEdit = true" />
          <GlassCircleButton icon="ellipsis" :title="t('watchlist.detail.more')" @click="openMenu" />
        </template>
      </div>

      <div class="relative px-5 sm:px-8 pb-8">

    <div v-if="loading" class="flex justify-center py-24">
      <Spinner class="w-6 h-6 text-[var(--wl-text-2)] animate-spin" />
    </div>

    <EmptyState v-else-if="!item" icon="film" :title="t('watchlist.detail.notFound')" :message="t('watchlist.detail.notFoundHint')" class="pt-16" />

    <template v-else>
      <div :class="['flex flex-col sm:flex-row items-center sm:items-end gap-4 sm:gap-6 text-center sm:text-left', boosts ? 'pb-3' : 'pb-7']">
        <div
          :class="['relative shrink-0 w-[170px] sm:w-[190px] aspect-[2/3] rounded-[22px] shadow-[0_18px_40px_-12px_rgb(0_0_0/0.6)]', openUrl ? 'cursor-pointer' : '']"
          :title="openUrl ? t('watchlist.detail.openOn', { target: targetLabel }) : undefined"
          @click="openPoster"
        >
          <div v-squircle class="absolute inset-0 rounded-[22px] overflow-hidden bg-[var(--wl-well)] grid place-items-center">
            <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
            <Glyph v-else :name="isShow ? 'tv' : 'film'" :sw="1" class="w-12 h-12 text-[var(--wl-text-2)]" />
          </div>
        </div>
        <div class="w-full min-w-0 flex flex-col items-center sm:items-start gap-2.5">
        <h1 class="text-[28px] leading-tight font-bold tracking-[-0.015em]">{{ item.title }}</h1>
        <p v-if="meta" class="text-[15px] text-[var(--wl-text-2)]">{{ meta }}</p>
        <div class="flex items-center justify-center sm:justify-start gap-1.5 flex-wrap">
          <span class="wl-tag">{{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}</span>
          <button type="button" class="wl-tag cursor-pointer hover:bg-[var(--wl-sep)] transition-colors" :title="t('watchlist.form.status')" @click="openMenu">
            <span class="w-1.5 h-1.5 rounded-full" :style="{ background: STATUS_COLOR[item.status] }" />
            {{ t('watchlist.status.' + item.status) }}
          </button>
          <span v-if="item.tmdbRating" class="wl-tag">TMDb ★ {{ Number(item.tmdbRating).toFixed(1) }}</span>
        </div>
      <div class="w-full flex items-center gap-2.5 pt-2">
          <div
            v-if="item.status === 'completed'"
            v-glass
            class="flex-1 h-[52px] rounded-full inline-flex items-center justify-center gap-2 text-base font-semibold"
            :style="{ color: STATUS_COLOR.completed }"
          >
            <Glyph name="checkBold" :sw="3" class="w-4 h-4" />
            {{ t('watchlist.detail.watched') }}
          </div>
          <button v-else type="button" :disabled="marking" class="wl-btn wl-btn-primary flex-1 !min-h-[52px] !text-base" @click="markWatched">
            <Glyph name="check" :sw="2.75" class="w-4 h-4" />
            {{ t('watchlist.card.markWatched') }}
          </button>
          <button
            v-if="dna.settings.value.enabled"
            type="button"
            :title="t('watchlist.detail.interested')"
            :aria-label="t('watchlist.detail.interested')"
            class="nuc-press cursor-pointer w-[52px] h-[52px] shrink-0 grid place-items-center rounded-full bg-[var(--wl-well)] hover:bg-[var(--wl-sep)] transition-colors"
            :style="{ color: boosts ? INTEREST : 'var(--wl-glyph)' }"
            @click="dna.markInterested(item)"
          >
            <svg class="w-6 h-6" viewBox="0 0 24 24" :fill="boosts ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path v-for="d in FLAME" :key="d" :d="d" />
            </svg>
          </button>
          <button
            type="button"
            :title="item.favorite ? t('watchlist.card.unfavorite') : t('watchlist.card.favorite')"
            :class="['nuc-fav nuc-press cursor-pointer w-[52px] h-[52px] shrink-0 grid place-items-center rounded-full bg-[var(--wl-well)] hover:bg-[var(--wl-sep)] transition-colors', item.favorite ? 'text-rose-500' : 'text-[var(--wl-glyph)]']"
            @click="patch({ favorite: !item.favorite })"
          >
            <FavoriteHeart :active="item.favorite" class="w-6 h-6" />
          </button>
        </div>
        </div>
      </div>

      <RouterLink
        v-if="boosts"
        to="/settings/moviedna"
        class="mb-7 flex items-center justify-center sm:justify-start gap-1.5 text-[13px] text-[var(--wl-text-2)] hover:text-[var(--wl-text)] no-underline transition-colors"
      >
        <Glyph v-if="dnaUnused" name="info" class="w-3.5 h-3.5 shrink-0" />
        <svg v-else class="w-3.5 h-3.5 shrink-0" :style="{ color: INTEREST }" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path v-for="d in FLAME" :key="d" :d="d" />
        </svg>
        {{ dnaUnused ? t('watchlist.detail.boostedUnused', { count: boosts }) : t('watchlist.detail.boosted', { count: boosts }) }}
      </RouterLink>

      <WlSection v-if="isShow" :title="t('watchlist.progress.label')">
        <button type="button" class="wl-row flex-col !items-stretch !gap-2.5 !py-3.5" @click="showProgress = true">
          <span class="flex items-center gap-2">
            <span class="flex-1 font-semibold">
              {{ totals.hasProgress ? t('watchlist.detail.episodesOf', { watched: item.status === 'completed' ? totals.totalEp : totals.watchedEp, total: totals.totalEp }) : t('watchlist.card.trackEpisodes') }}
            </span>
            <span v-if="timeLeft" class="text-sm text-[var(--wl-text-2)]">{{ t('watchlist.card.timeLeft', { time: formatRuntime(timeLeft) }) }}</span>
            <Glyph name="chevronRight" :sw="2.5" class="w-3.5 h-3.5 text-slate-400" />
          </span>
          <span v-if="totals.hasProgress" class="block h-1.5 bg-[var(--wl-well)] rounded-full overflow-hidden">
            <span class="block h-full rounded-full transition-all duration-500" :style="{ width: `${Math.round(fraction * 100)}%`, background: item.status === 'completed' ? STATUS_COLOR.completed : STATUS_COLOR.watching }" />
          </span>
        </button>
      </WlSection>

      <WlSection v-if="overview" :title="t('watchlist.detail.overview')" padded>
        <p class="text-[15px] leading-relaxed whitespace-pre-line">{{ overview }}</p>
      </WlSection>

      <TrailersSection v-if="videos.length" :videos="videos" />

      <WlSection :title="t('watchlist.form.yourRating')" padded>
        <RatingControl :model-value="item.rating" :max="10" size="lg" @update:model-value="patch({ rating: $event })" />
      </WlSection>

      <WlSection v-if="item.streamingProvider" :title="t('watchlist.form.whereToWatch')">
        <WlRow :href="item.watchLink || ''" :title="item.streamingProvider">
          <template #icon>
            <img v-if="item.streamingLogo" :src="logoUrl(item.streamingLogo)" :alt="item.streamingProvider" class="w-8 h-8 rounded-[8px] object-cover" />
          </template>
        </WlRow>
      </WlSection>

      <WlSection v-if="item.genres?.length" :title="t('watchlist.form.genres')" padded>
        <div class="flex flex-wrap gap-1.5">
          <span v-for="g in item.genres" :key="g" class="wl-chip !h-7 !text-white" :style="{ background: genreColor(g) }">{{ g }}</span>
        </div>
      </WlSection>

      <ItemPluginSections :item="item" />

      <WlSection :title="t('watchlist.collections.label')">
        <WlRow v-for="c in itemCollections" :key="c._id" :to="`/collections/${c._id}`" icon="folder" tint="violet" :title="c.name" chevron />
        <WlRow button icon="plus" tint="indigo" :title="itemCollections.length ? t('watchlist.detail.changeCollections') : t('watchlist.detail.addToCollection')" @click="showManage = true" />
      </WlSection>

      <WlSection v-if="item.notes" :title="t('watchlist.card.notes')" padded>
        <p class="text-[15px] leading-relaxed whitespace-pre-line">{{ item.notes }}</p>
      </WlSection>

      <WlSection>
        <a v-if="resumeUrl" :href="resumeUrl" target="_blank" rel="noopener noreferrer" class="wl-row flex-col !items-stretch !gap-2.5">
          <span class="flex items-center gap-2">
            <span class="flex-1">{{ t('watchlist.detail.continueWatching') }}</span>
            <span v-if="item.playback" class="text-sm tabular-nums text-[var(--wl-text-2)]">{{ clock(item.playback.position) }} / {{ clock(item.playback.duration) }}</span>
            <span v-else class="text-sm text-[var(--wl-text-2)]">{{ resumeHost }}</span>
          </span>
          <span v-if="item.playback" class="block h-1.5 bg-[var(--wl-well)] rounded-full overflow-hidden">
            <span class="block h-full rounded-full" :style="{ width: `${playbackPct}%`, background: STATUS_COLOR.watching }" />
          </span>
        </a>
        <WlRow v-if="openUrl" :href="openUrl" :title="t('watchlist.detail.openOn', { target: targetLabel })" />
        <WlRow v-if="resets.length" button :title="t('watchlist.detail.resetProgress')" @click="showReset = true" />
        <WlRow button danger :title="t('watchlist.card.delete')" @click="showDelete = true" />
      </WlSection>
    </template>
      </div>
    </div>
  </div>

  <template v-if="item">
    <ItemFormModal :show="showEdit" :initial="item" @close="showEdit = false" @submit="submitEdit" @deleted="itemsChanged(); close()" />
    <ManageCollectionsModal :show="showManage" :item="item" @close="showManage = false" @updated="setItem" />
    <SeasonProgressModal v-if="isShow" :show="showProgress" :item="item" @close="showProgress = false" @updated="setItem" />
    <ContextMenu :show="menu.show" :x="menu.x" :y="menu.y" :items="menuItems" @close="menu.show = false" />

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
          type="button"
          :class="['wl-btn', action.destructive ? 'wl-btn-secondary !text-[var(--wl-danger)]' : 'wl-btn-secondary']"
          @click="resetProgress(action.id)"
        >
          {{ isShow ? t(`watchlist.detail.reset.${action.id}`) : t('watchlist.detail.resetProgress') }}
        </button>
      </div>
    </TemplateModal>
  </template>
</template>

<style scoped>
.sheet-panel { animation: sheet-in 0.42s var(--nuc-ease) both; }
.sheet-backdrop { animation: nuc-fade 0.25s ease both; }
@keyframes sheet-in {
  from { opacity: 0; transform: translateY(40px) scale(0.98); }
  to { opacity: 1; transform: none; }
}
@media (prefers-reduced-motion: reduce) { .sheet-panel { animation: none; } }
</style>
