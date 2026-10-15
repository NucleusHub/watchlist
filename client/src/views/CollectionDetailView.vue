<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import TemplateModal from '@core/TemplateModal.vue'
import ContextMenu from '@core/ContextMenu.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { ICONS } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { getItems, updateItem, saveCollectionOrder } from '@/api/watchlist.js'
import ItemCard from '@/components/ItemCard.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ManageCollectionsModal from '@/components/ManageCollectionsModal.vue'
import CollectionFormModal from '@/components/CollectionFormModal.vue'
import AddItemsModal from '@/components/AddItemsModal.vue'
import CollectionCover from '@/components/CollectionCover.vue'
import PageShell from '@/ui/PageShell.vue'
import GlassCircleButton from '@/ui/GlassCircleButton.vue'
import SegmentPills from '@/ui/SegmentPills.vue'
import Glyph from '@/ui/Glyph.vue'
import EmptyState from '@/ui/EmptyState.vue'
import { itemsVersion } from '@/composables/useItemSheet.js'

const props = defineProps({ id: { type: String, required: true } })

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const { collections, update, remove, reload, applyMembership, applyOrder } = useCollections()

const collection = computed(() => collections.value.find((c) => c._id === props.id) || null)
const notFound = ref(false)

const items = ref([])
const loading = ref(true)

const orderedItems = computed(() => {
  const order = (collection.value?.itemOrder || []).map(String)
  if (!order.length) return items.value
  const rank = new Map(order.map((id, i) => [id, i]))
  return [...items.value].sort(
    (a, b) => (rank.get(String(a._id)) ?? Infinity) - (rank.get(String(b._id)) ?? Infinity)
  )
})

const gridStyle = ref(localStorage.getItem('watchlist-grid') || 'small')
watch(gridStyle, (v) => localStorage.setItem('watchlist-grid', v))
const gridClass = computed(() => ({
  list: 'grid-cols-1 lg:grid-cols-2 gap-3',
  big: 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-5',
  small: 'grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-x-3 gap-y-4',
}[gridStyle.value]))
const LAYOUTS = [
  { key: 'list', label: 'watchlist.list.viewList', glyph: 'listBullet' },
  { key: 'big', label: 'watchlist.list.viewGrid2', glyph: 'grid2' },
  { key: 'small', label: 'watchlist.list.viewGrid3', glyph: 'grid3' },
]
const layoutGlyph = computed(() => LAYOUTS.find((l) => l.key === gridStyle.value)?.glyph ?? 'grid3')
const coverPosters = computed(() => {
  const c = collection.value
  if (c?.coverPosters?.length) return c.coverPosters
  return (c?.previewPosters?.length ? c.previewPosters : items.value.map((i) => i.posterUrl).filter(Boolean)).slice(0, c?.coverCount || 4)
})

// The ⋯ menu and the layout menu share one ContextMenu.
const menu = ref({ show: false, x: 0, y: 0, items: [] })
function openMenu(e, kind) {
  const r = e.currentTarget.getBoundingClientRect()
  const items = kind === 'layout'
    ? LAYOUTS.map((l) => ({ label: t(l.label), icon: gridStyle.value === l.key ? ICONS.check : ' ', action: () => (gridStyle.value = l.key) }))
    : [
        { label: t('watchlist.collections.rename'), icon: ICONS.pencil, action: () => (showRename.value = true) },
        ...(items.value.length > 1 ? [{ label: t('watchlist.collections.reorder'), icon: ICONS.menu, action: startReorder }] : []),
        { divider: true },
        { label: t('watchlist.collections.delete'), iconTrash: true, danger: true, action: () => (showDeleteCol.value = true) },
      ]
  menu.value = { show: true, x: r.right - 200, y: r.bottom + 8, items }
}

const searchQuery = ref('')
const activeStatus = ref('all')
const activeType = ref('all')
const onlyFavorite = ref(false)

const STATUS_TABS = computed(() => [
  { key: 'all', label: t('watchlist.status.all') },
  { key: 'planned', label: t('watchlist.status.planned') },
  { key: 'watching', label: t('watchlist.status.watching') },
  { key: 'completed', label: t('watchlist.status.completed') },
])
const TYPE_TABS = computed(() => [
  { key: 'all', label: t('watchlist.type.all') },
  { key: 'movie', label: t('watchlist.type.movies') },
  { key: 'show', label: t('watchlist.type.shows') },
])

const filtersActive = computed(
  () => !!searchQuery.value.trim() || activeStatus.value !== 'all' || activeType.value !== 'all' || onlyFavorite.value
)
function clearFilters() {
  searchQuery.value = ''
  activeStatus.value = 'all'
  activeType.value = 'all'
  onlyFavorite.value = false
}

const visible = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  return orderedItems.value.filter((i) => {
    const statusOk = activeStatus.value === 'all' || i.status === activeStatus.value
    const typeOk = activeType.value === 'all' || i.type === activeType.value
    const favOk = !onlyFavorite.value || i.favorite
    const searchOk = !q || i.title.toLowerCase().includes(q) || (i.notes && i.notes.toLowerCase().includes(q))
    return statusOk && typeOk && favOk && searchOk
  })
})

const showEditItem = ref(false)
const editingItem = ref(null)
const showManage = ref(false)
const managingItem = ref(null)
const showRename = ref(false)
const showAdd = ref(false)
const showDeleteCol = ref(false)
const deletingBusy = ref(false)

const reordering = ref(false)
const draft = ref([])
const savingOrder = ref(false)
const dragIndex = ref(null)

function startReorder() {
  draft.value = [...orderedItems.value]
  reordering.value = true
}
function cancelReorder() {
  reordering.value = false
  draft.value = []
  dragIndex.value = null
}
function move(from, to) {
  if (to < 0 || to >= draft.value.length) return
  const next = [...draft.value]
  const [row] = next.splice(from, 1)
  next.splice(to, 0, row)
  draft.value = next
}
function moveTo(i, value) {
  const n = Math.round(Number(value))
  if (!Number.isFinite(n)) return
  const to = Math.max(0, Math.min(draft.value.length - 1, n - 1))
  if (to !== i) move(i, to)
}
function onDragStart(i, e) {
  dragIndex.value = i
  if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move'
}
function onDragOver(i) {
  if (dragIndex.value === null || dragIndex.value === i) return
  move(dragIndex.value, i)
  dragIndex.value = i
}
function onDragEnd() {
  dragIndex.value = null
}
async function saveOrder() {
  if (savingOrder.value) return
  savingOrder.value = true
  try {
    const itemIds = draft.value.map((i) => i._id)
    await saveCollectionOrder(props.id, itemIds)
    applyOrder(props.id, itemIds)
    reordering.value = false
    draft.value = []
  } finally {
    savingOrder.value = false
  }
}

async function load() {
  loading.value = true
  try {
    items.value = await getItems({ collection: props.id })
    if (!collection.value) {
      await reload()
      if (!collection.value) notFound.value = true
    }
  } catch {
    notFound.value = !collection.value
  } finally {
    loading.value = false
  }
}
onMounted(() => {
  load()
  // Collections → ⋯ → Add titles lands here with ?add=1.
  if (route.query.add) {
    showAdd.value = true
    router.replace({ query: {} })
  }
})
watch(() => props.id, load)
watch(itemsVersion, load)

function reconcile(updated) {
  const inHere = (updated.collectionIds || []).map(String).includes(String(props.id))
  if (inHere) items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
  else items.value = items.value.filter((i) => i._id !== updated._id)
}
function handleDeleted(id) {
  items.value = items.value.filter((i) => i._id !== id)
}

function openEdit(item) {
  editingItem.value = item
  showEditItem.value = true
}
async function submitEdit(data) {
  const prev = editingItem.value.collectionIds || []
  const updated = await updateItem(editingItem.value._id, data)
  applyMembership(prev, updated.collectionIds || [])
  reconcile(updated)
  showEditItem.value = false
  editingItem.value = null
}
function openManage(item) {
  managingItem.value = item
  showManage.value = true
}
function onManaged(updated) {
  reconcile(updated)
}

async function submitRename(data) {
  await update(props.id, data)
  showRename.value = false
}
async function confirmDeleteCol() {
  deletingBusy.value = true
  try {
    await remove(props.id)
    router.push('/collections')
  } finally {
    deletingBusy.value = false
  }
}

function onItemsAdded(added) {
  const ids = new Set(items.value.map((i) => i._id))
  items.value = [...added.filter((i) => !ids.has(i._id)), ...items.value]
}
</script>

<template>
  <PageShell wide back="/collections">
    <template v-if="collection" #actions>
      <template v-if="reordering">
        <button v-glass type="button" class="cursor-pointer h-10 px-4 rounded-full text-[15px] font-medium" @click="cancelReorder">{{ t('watchlist.form.cancel') }}</button>
        <button type="button" :disabled="savingOrder" class="wl-btn wl-btn-primary !min-h-10" @click="saveOrder">{{ t('watchlist.collections.done') }}</button>
      </template>
      <template v-else>
        <GlassCircleButton icon="plus" :title="t('watchlist.collections.addItems')" @click="showAdd = true" />
        <GlassCircleButton icon="ellipsis" :title="t('watchlist.collections.options')" @click="openMenu($event, 'more')" />
      </template>
    </template>

    <div v-if="loading && !collection" class="text-center py-16 text-[var(--wl-text-2)]">{{ t('watchlist.state.loading') }}</div>

    <EmptyState v-else-if="notFound" icon="folder" :message="t('watchlist.collections.notFound')" class="pt-16">
      <RouterLink to="/collections" class="wl-btn wl-btn-secondary mt-2">{{ t('watchlist.collections.backToCollections') }}</RouterLink>
    </EmptyState>

    <template v-else-if="collection">
      <div class="relative aspect-[16/7] max-h-72 w-full rounded-[26px] shadow-[0_14px_30px_-12px_rgb(0_0_0/0.45)] mb-6 nuc-in">
        <div v-squircle class="absolute inset-0 rounded-[26px] overflow-hidden">
          <CollectionCover :image="collection.coverUrl" :posters="coverPosters" />
          <div class="absolute inset-x-0 bottom-0 px-5 pt-12 pb-5 bg-gradient-to-b from-transparent to-black/70 text-white">
            <h1 class="text-[30px] leading-tight font-bold tracking-[-0.02em] [text-shadow:0_2px_8px_rgb(0_0_0/0.4)]">{{ collection.name }}</h1>
            <p class="text-sm font-medium opacity-80">{{ t('watchlist.collections.itemCount', { count: items.length }) }}</p>
          </div>
        </div>
      </div>
      <p v-if="collection.description" class="-mt-2 mb-6 px-1 text-[15px] leading-relaxed text-[var(--wl-text-2)]">{{ collection.description }}</p>

      <EmptyState v-if="!loading && !items.length" icon="folder" :message="t('watchlist.collections.emptyItemsHint')">
        <button type="button" class="wl-btn wl-btn-primary mt-2" @click="showAdd = true">
          <Glyph name="plus" :sw="2.75" class="w-4 h-4" />
          {{ t('watchlist.collections.addItems') }}
        </button>
      </EmptyState>

      <template v-else-if="reordering">
        <p class="flex items-center gap-2 mb-3 px-1 text-sm text-[var(--wl-text-2)]">
          <Glyph name="menu" class="w-4 h-4 shrink-0" />
          {{ t('watchlist.collections.reorderHint') }}
        </p>
        <ul class="flex flex-col gap-2 max-w-[680px]">
          <li
            v-for="(item, i) in draft"
            :key="item._id"
            draggable="true"
            :class="['wl-row wl-surface rounded-[20px] !py-2 select-none transition-transform', dragIndex === i ? 'scale-[1.01] ring-2 ring-[color-mix(in_oklab,var(--wl-accent)_45%,transparent)]' : '']"
            @dragstart="onDragStart(i, $event)"
            @dragover.prevent="onDragOver(i)"
            @dragend="onDragEnd"
          >
            <Glyph name="menu" class="w-4 h-4 shrink-0 cursor-grab active:cursor-grabbing text-[var(--wl-text-2)]" />
            <input
              :value="i + 1"
              type="number"
              min="1"
              :max="draft.length"
              inputmode="numeric"
              :title="t('watchlist.collections.positionHint')"
              class="pos-input w-9 h-9 shrink-0 rounded-[10px] bg-[var(--wl-well)] text-center text-sm font-semibold tabular-nums outline-none focus:ring-2 focus:ring-[var(--wl-accent)]"
              @change="moveTo(i, $event.target.value)"
              @keydown.enter.prevent="$event.target.blur()"
              @focus="$event.target.select()"
            />
            <div class="w-9 h-[54px] shrink-0 rounded-[6px] overflow-hidden bg-[var(--wl-well)] grid place-items-center">
              <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
              <Glyph v-else :name="item.type === 'show' ? 'tv' : 'film'" class="w-4 h-4 text-[var(--wl-text-2)]" />
            </div>
            <div class="flex-1 min-w-0">
              <p class="font-medium truncate">{{ item.title }}</p>
              <p class="wl-sub truncate">{{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}<span v-if="item.year"> · {{ item.year }}</span></p>
            </div>
            <div class="flex items-center shrink-0 gap-1">
              <button type="button" :disabled="i === 0" :title="t('watchlist.collections.moveUp')" class="cursor-pointer w-8 h-8 rounded-full grid place-items-center bg-[var(--wl-well)] disabled:opacity-30 disabled:cursor-default" @click="move(i, i - 1)">
                <Glyph name="chevronUp" :sw="2.5" class="w-4 h-4" />
              </button>
              <button type="button" :disabled="i === draft.length - 1" :title="t('watchlist.collections.moveDown')" class="cursor-pointer w-8 h-8 rounded-full grid place-items-center bg-[var(--wl-well)] disabled:opacity-30 disabled:cursor-default" @click="move(i, i + 1)">
                <Glyph name="chevronDown" :sw="2.5" class="w-4 h-4" />
              </button>
            </div>
          </li>
        </ul>
      </template>

      <template v-else-if="items.length">
        <div class="max-w-3xl mx-auto flex flex-col gap-3 mb-5">
          <div class="relative">
            <Glyph name="magnifier" :sw="2.25" class="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--wl-text-2)] pointer-events-none" />
            <input v-model="searchQuery" type="search" autocomplete="off" :placeholder="t('watchlist.collections.searchItems')" class="wl-field !pl-10 [&::-webkit-search-cancel-button]:hidden" />
          </div>
          <SegmentPills v-model="activeStatus" :items="STATUS_TABS" fill />
          <div class="flex items-center gap-2">
            <SegmentPills v-model="activeType" :items="TYPE_TABS" />
            <div class="flex-1" />
            <span class="hidden sm:block text-xs text-[var(--wl-text-2)] tabular-nums pr-1">{{ t('watchlist.list.showing', { shown: visible.length, total: items.length }) }}</span>
            <GlassCircleButton :title="t('watchlist.filter.favorites')" :class="['nuc-fav', onlyFavorite ? '!text-rose-500' : '']" @click="onlyFavorite = !onlyFavorite">
              <FavoriteHeart :active="onlyFavorite" class="w-[18px] h-[18px]" stroke-width="2" />
            </GlassCircleButton>
            <GlassCircleButton :icon="layoutGlyph" :title="t('watchlist.list.layout')" @click="openMenu($event, 'layout')" />
          </div>
        </div>

        <EmptyState v-if="!visible.length" icon="magnifier" :message="t('watchlist.collections.noMatches')">
          <button v-if="filtersActive" type="button" class="wl-btn wl-btn-secondary mt-2" @click="clearFilters">{{ t('watchlist.collections.clearFilters') }}</button>
        </EmptyState>

        <div v-else :class="['grid nuc-stagger', gridClass]" style="--nuc-step: 28ms">
          <ItemCard
            v-for="item in visible"
            :key="item._id"
            :item="item"
            :grid-style="gridStyle"
            :collection-id="id"
            @updated="reconcile"
            @deleted="handleDeleted"
            @edit="openEdit"
            @manage-collections="openManage"
          />
        </div>
      </template>
    </template>
  </PageShell>

  <ItemFormModal
    :show="showEditItem"
    :initial="editingItem"
    @close="showEditItem = false; editingItem = null"
    @submit="submitEdit"
    @deleted="handleDeleted"
  />
  <ManageCollectionsModal :show="showManage" :item="managingItem" @close="showManage = false" @updated="onManaged" />
  <CollectionFormModal :show="showRename" :initial="collection" @close="showRename = false" @submit="submitRename" />
  <AddItemsModal :show="showAdd" :collection-id="id" :member-ids="items.map((i) => i._id)" @close="showAdd = false" @added="onItemsAdded" />
  <ContextMenu :show="menu.show" :x="menu.x" :y="menu.y" :items="menu.items" @close="menu.show = false" />
  <TemplateModal
    :show="showDeleteCol"
    :title="t('watchlist.collections.deleteTitle')"
    :message="t('watchlist.collections.deleteMessage', { name: collection?.name })"
    :confirm-label="t('watchlist.collections.delete')"
    :busy="deletingBusy"
    @confirm="confirmDeleteCol"
    @cancel="showDeleteCol = false"
  />
</template>

<style scoped>
.pos-input::-webkit-outer-spin-button,
.pos-input::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}
.pos-input {
  -moz-appearance: textfield;
  appearance: textfield;
}
</style>
