<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { getItems, createItem, updateItem } from '@/api/watchlist.js'
import { genreFacets, hasGenre } from '@/utils/genres.js'
import { watchlistSurfaces } from '@/utils/pluginSurfaces.js'
import ItemCard from '@/components/ItemCard.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ManageCollectionsModal from '@/components/ManageCollectionsModal.vue'
import ContextMenu from '@core/ContextMenu.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { useWatchlistHost } from '@/composables/useWatchlistHost.js'
import { itemsVersion } from '@/composables/useItemSheet.js'
import { ICONS } from '@core/icons'
import HomeShell from '@/ui/HomeShell.vue'
import SegmentPills from '@/ui/SegmentPills.vue'
import GlassCircleButton from '@/ui/GlassCircleButton.vue'
import Glyph from '@/ui/Glyph.vue'
import EmptyState from '@/ui/EmptyState.vue'
import { genreColor } from '@/ui/palette.js'

const { t } = useI18n()
const { applyMembership } = useCollections()
const { isPluginEnabled } = useRegistry()
const { placementOf } = useOpenSettings()

const panelSurfaces = computed(() =>
  watchlistSurfaces.filter((s) => isPluginEnabled(s.pluginId) && placementOf(s) === 'panel')
)

const gridStyle = ref(localStorage.getItem('watchlist-grid') || 'small')
watch(gridStyle, (val) => localStorage.setItem('watchlist-grid', val))
const gridClass = computed(() => ({
  list: 'grid-cols-1 lg:grid-cols-2 gap-3',
  big: 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-5',
  small: 'grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-x-3 gap-y-4',
}[gridStyle.value]))

const items = ref([])
const host = useWatchlistHost({ items: () => items.value, changed: () => load() })
const loading = ref(true)
const error = ref(null)
const showModal = ref(false)
const editingItem = ref(null)
const modalResetKey = ref(0)
const showManage = ref(false)
const managingItem = ref(null)
const activeStatus = ref('planned')
const activeType = ref('all')
const onlyFavorite = ref(false)
const sortBy = ref('alphabetical')
const sortDir = ref('asc')
const activeGenres = ref([])

const STATUS_TABS = computed(() => ['all', 'planned', 'watching', 'completed'].map((key) => ({ key, label: t('watchlist.status.' + key) })))
const TYPE_TABS = computed(() => [
  { key: 'all', label: t('watchlist.type.all') },
  { key: 'movie', label: t('watchlist.type.movies') },
  { key: 'show', label: t('watchlist.type.shows') },
])

// A–Z goes up, the rest come down, as on iOS.
const SORTS = [
  { key: 'alphabetical', label: 'watchlist.sort.alphabetical', dir: 'asc' },
  { key: 'dateAdded', label: 'watchlist.sort.dateAdded', dir: 'desc' },
  { key: 'dateReleased', label: 'watchlist.sort.dateReleased', dir: 'desc' },
  { key: 'rating', label: 'watchlist.sort.rating', dir: 'desc' },
  { key: 'runtime', label: 'watchlist.sort.runtime', dir: 'desc' },
]
const LAYOUTS = [
  { key: 'list', label: 'watchlist.list.viewList', glyph: 'listBullet' },
  { key: 'big', label: 'watchlist.list.viewGrid2', glyph: 'grid2' },
  { key: 'small', label: 'watchlist.list.viewGrid3', glyph: 'grid3' },
]

function pickSort(key) {
  if (sortBy.value === key) sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
  else {
    sortBy.value = key
    sortDir.value = SORTS.find((s) => s.key === key).dir
  }
}

const menu = ref({ show: false, x: 0, y: 0, items: [] })
function openMenu(e, kind) {
  const r = e.currentTarget.getBoundingClientRect()
  const tick = ICONS.check
  const items = kind === 'sort'
    ? [
        ...SORTS.map((s) => ({ label: t(s.label), icon: sortBy.value === s.key ? tick : ' ', action: () => pickSort(s.key) })),
        { divider: true },
        { label: t(sortDir.value === 'asc' ? 'watchlist.sort.ascending' : 'watchlist.sort.descending'), icon: sortDir.value === 'asc' ? ICONS.chevronUp : ICONS.chevronDown, action: () => (sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc') },
      ]
    : LAYOUTS.map((l) => ({ label: t(l.label), icon: gridStyle.value === l.key ? tick : ' ', action: () => (gridStyle.value = l.key) }))
  menu.value = { show: true, x: r.right - 192, y: r.bottom + 8, items }
}
const layoutGlyph = computed(() => LAYOUTS.find((l) => l.key === gridStyle.value)?.glyph ?? 'grid3')
const sortActive = computed(() => sortBy.value !== 'alphabetical' || sortDir.value !== 'asc')

const preGenre = computed(() =>
  items.value.filter((i) =>
    (activeStatus.value === 'all' || i.status === activeStatus.value) &&
    (activeType.value === 'all' || i.type === activeType.value) &&
    (!onlyFavorite.value || i.favorite)
  )
)

const genreOptions = computed(() => genreFacets(preGenre.value))
const isGenreOn = (name) => activeGenres.value.some((g) => g.toLowerCase() === name.toLowerCase())
function toggleGenre(name) {
  const next = activeGenres.value.filter((g) => g.toLowerCase() !== name.toLowerCase())
  if (next.length === activeGenres.value.length) next.push(name)
  activeGenres.value = next
}

// Drop selections missing from the current facets, or they would filter invisibly.
watch(genreOptions, (opts) => {
  if (!activeGenres.value.length) return
  const available = new Set(opts.map((o) => o.name.toLowerCase()))
  const kept = activeGenres.value.filter((g) => available.has(g.toLowerCase()))
  if (kept.length !== activeGenres.value.length) activeGenres.value = kept
})

const filtered = computed(() => {
  const base = activeGenres.value.length
    ? preGenre.value.filter((i) => activeGenres.value.some((g) => hasGenre(i, g)))
    : preGenre.value
  const dir = sortDir.value === 'asc' ? 1 : -1
  return [...base].sort((a, b) => {
    switch (sortBy.value) {
      case 'dateAdded': return (new Date(a.dateAdded) - new Date(b.dateAdded)) * dir
      case 'dateReleased': return ((a.year ?? 0) - (b.year ?? 0)) * dir
      case 'rating': return ((a.rating ?? a.tmdbRating ?? 0) - (b.rating ?? b.tmdbRating ?? 0)) * dir
      case 'runtime': {
        const rt = (i) => (i.type === 'movie' ? i.runtime : i.showRuntime) ?? 0
        return (rt(a) - rt(b)) * dir
      }
      default: return a.title.localeCompare(b.title) * dir
    }
  })
})

function clearFilters() {
  activeStatus.value = 'all'
  activeType.value = 'all'
  onlyFavorite.value = false
  activeGenres.value = []
}

async function load() {
  loading.value = !items.value.length
  error.value = null
  try {
    items.value = await getItems()
  } catch {
    error.value = t('watchlist.state.loadError')
  } finally {
    loading.value = false
  }
}

async function handleSubmit(data, addAnother = false) {
  if (editingItem.value) {
    const prev = editingItem.value.collectionIds || []
    const updated = await updateItem(editingItem.value._id, data)
    applyMembership(prev, updated.collectionIds || [])
    items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
    closeModal()
  } else {
    const created = await createItem(data)
    applyMembership([], created.collectionIds || [])
    items.value.unshift(created)
    if (addAnother) modalResetKey.value++
    else closeModal()
  }
}

function openAdd() {
  editingItem.value = null
  showModal.value = true
}
function openEdit(item) {
  editingItem.value = item
  showModal.value = true
}
function closeModal() {
  showModal.value = false
  editingItem.value = null
}
function handleUpdated(updated) {
  items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
}
function openManage(item) {
  managingItem.value = item
  showManage.value = true
}
function handleDeleted(id) {
  items.value = items.value.filter((i) => i._id !== id)
}

onMounted(load)
watch(itemsVersion, load)
</script>

<template>
  <HomeShell :items="items" addable :search-prompt="t('watchlist.search.promptAll')" @add="openAdd">
    <div v-if="loading" class="text-center py-16 text-[var(--wl-text-2)]">{{ t('watchlist.state.loading') }}</div>

    <EmptyState v-else-if="error" icon="warning" :title="error">
      <button type="button" class="wl-btn wl-btn-secondary mt-2" @click="load">{{ t('watchlist.state.retry') }}</button>
    </EmptyState>

    <EmptyState v-else-if="!items.length" icon="film" :title="t('watchlist.empty.title')" :message="t('watchlist.empty.message')" class="pt-16">
      <button type="button" class="wl-btn wl-btn-primary mt-3 w-full max-w-[280px]" @click="openAdd">{{ t('watchlist.empty.add') }}</button>
    </EmptyState>

    <template v-else>
      <div class="flex flex-col gap-4 mb-5">
        <component
          :is="s.component"
          v-for="s in panelSurfaces"
          :key="s.pluginId"
          :items="items"
          :host="host"
          placement="panel"
          @changed="load"
        />
      </div>

      <div class="max-w-3xl mx-auto flex flex-col gap-3 mb-5">
        <SegmentPills v-model="activeStatus" :items="STATUS_TABS" fill />

        <div class="flex items-center gap-2">
          <SegmentPills v-model="activeType" :items="TYPE_TABS" />
          <div class="flex-1" />
          <span class="hidden sm:block text-xs text-[var(--wl-text-2)] tabular-nums pr-1">
            {{ t('watchlist.list.showing', { shown: filtered.length, total: items.length }) }}
          </span>
          <GlassCircleButton
            :title="t('watchlist.filter.favorites')"
            :active="onlyFavorite"
            :class="['nuc-fav', onlyFavorite ? '!text-rose-500' : '']"
            @click="onlyFavorite = !onlyFavorite"
          >
            <FavoriteHeart :active="onlyFavorite" class="w-[18px] h-[18px]" stroke-width="2" />
          </GlassCircleButton>
          <GlassCircleButton icon="sortArrows" :title="t('watchlist.sort.title')" :active="sortActive" @click="openMenu($event, 'sort')" />
          <GlassCircleButton :icon="layoutGlyph" :title="t('watchlist.list.layout')" @click="openMenu($event, 'layout')" />
        </div>

        <div v-if="genreOptions.length" class="-mx-4 px-4 overflow-x-auto no-scrollbar">
          <div class="inline-flex items-center gap-1.5 py-0.5">
            <button
              v-for="g in genreOptions"
              :key="g.name"
              type="button"
              class="wl-chip nuc-press cursor-pointer transition-colors"
              :style="isGenreOn(g.name) ? { background: genreColor(g.name), color: '#fff' } : undefined"
              @click="toggleGenre(g.name)"
            >
              {{ g.name }}
              <span :class="['tabular-nums', isGenreOn(g.name) ? 'text-white/70' : 'text-[var(--wl-text-2)]']">{{ g.count }}</span>
            </button>
          </div>
        </div>
      </div>

      <EmptyState v-if="!filtered.length" icon="magnifier" :title="t('watchlist.search.noMatches')" :message="t('watchlist.filter.noMatches')">
        <button type="button" class="wl-btn wl-btn-secondary mt-2" @click="clearFilters">{{ t('watchlist.filter.clear') }}</button>
      </EmptyState>

      <div v-else :class="['grid nuc-stagger', gridClass]" style="--nuc-step: 28ms">
        <ItemCard
          v-for="item in filtered"
          :key="item._id"
          :item="item"
          :grid-style="gridStyle"
          @updated="handleUpdated"
          @deleted="handleDeleted"
          @edit="openEdit"
          @manage-collections="openManage"
        />
      </div>
    </template>
  </HomeShell>

  <ItemFormModal
    :show="showModal"
    :initial="editingItem"
    :reset-key="modalResetKey"
    @close="closeModal"
    @submit="handleSubmit"
    @deleted="handleDeleted"
  />
  <ManageCollectionsModal :show="showManage" :item="managingItem" @close="showManage = false" @updated="handleUpdated" />
  <ContextMenu :show="menu.show" :x="menu.x" :y="menu.y" :items="menu.items" @close="menu.show = false" />
</template>
