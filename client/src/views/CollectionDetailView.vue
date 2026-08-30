<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import AppHeader from '@core/AppHeader.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import TemplateModal from '@core/TemplateModal.vue'
import TrashIcon from '@core/TrashIcon.vue'
import FavoriteHeart from '@core/FavoriteHeart.vue'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { getItems, updateItem, saveCollectionOrder } from '@/api/watchlist.js'
import ArchiveBoxIcon from '@/assets/icons/archive-box.svg?component'
import ListIcon from '@/assets/icons/list.svg?component'
import ViewColumns2Icon from '@/assets/icons/view-columns-2.svg?component'
import ViewColumns3Icon from '@/assets/icons/view-columns-3.svg?component'
import ItemCard from '@/components/ItemCard.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ManageCollectionsModal from '@/components/ManageCollectionsModal.vue'
import CollectionFormModal from '@/components/CollectionFormModal.vue'
import AddItemsModal from '@/components/AddItemsModal.vue'
import SettingsButton from '@/components/SettingsButton.vue'

const props = defineProps({ id: { type: String, required: true } })

const { t } = useI18n()
const router = useRouter()
const { collections, update, remove, reload, applyMembership, applyOrder } = useCollections()

const collection = computed(() => collections.value.find((c) => c._id === props.id) || null)
const notFound = ref(false)

const items = ref([])
const loading = ref(true)

// Members in the collection's manual order: ids listed in `itemOrder` first (in
// that order), then anything not yet ordered (e.g. newly added) in load order.
const orderedItems = computed(() => {
  const order = (collection.value?.itemOrder || []).map(String)
  if (!order.length) return items.value
  const rank = new Map(order.map((id, i) => [id, i]))
  return [...items.value].sort(
    (a, b) => (rank.get(String(a._id)) ?? Infinity) - (rank.get(String(b._id)) ?? Infinity)
  )
})

// Match the main list's view-mode preference so the two feel like one surface.
const gridStyle = ref(localStorage.getItem('watchlist-grid') || 'small')
watch(gridStyle, (v) => localStorage.setItem('watchlist-grid', v))
const gridClass = computed(() => ({
  list:  'grid-cols-1',
  big:   'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4',
  small: 'grid-cols-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5',
}[gridStyle.value]))

// Search + filters over the manually-ordered members. Sorting is intentionally
// omitted here — the collection's own manual order is the ordering; filters and
// search only narrow what's shown, preserving that order.
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

// Modals.
const showEditItem = ref(false)
const editingItem = ref(null)
const showManage = ref(false)
const managingItem = ref(null)
const showRename = ref(false)
const showAdd = ref(false)
const showDeleteCol = ref(false)
const deletingBusy = ref(false)

// ── Manual reorder ──────────────────────────────────────────────────────────
// A dedicated mode over a single-column list: drag rows (desktop) or use the
// arrows (touch/keyboard). `draft` is edited live and only persisted on save.
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
// Jump an item to a typed 1-based position; everything else shifts to fill in.
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
onMounted(load)
watch(() => props.id, load)

// After any item change, keep the list scoped to this collection's members.
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
  // Prepend the newly-added members (already scoped to this collection).
  const ids = new Set(items.value.map((i) => i._id))
  items.value = [...added.filter((i) => !ids.has(i._id)), ...items.value]
}
</script>

<template>
  <div class="relative min-h-screen bg-slate-100 dark:bg-[#0d0d1a] text-slate-900 dark:text-white overflow-x-hidden">
    <BackgroundBlobs />
    <div class="relative z-10">
      <AppHeader>
        <template #left>
          <RouterLink
            to="/collections"
            class="cursor-pointer p-2 rounded-lg text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors no-underline"
            :title="t('watchlist.collections.back')"
          >
            <Icon name="arrowLeft" class="w-5 h-5" />
          </RouterLink>
          <p v-if="collection" class="text-sm font-semibold text-slate-900 dark:text-white truncate max-w-[40vw]">{{ collection.name }}</p>
        </template>

        <template #right>
          <!-- Reorder mode: only Cancel / Done. -->
          <template v-if="reordering">
            <button
              @click="cancelReorder"
              class="cursor-pointer px-3 py-2 text-sm font-medium text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15 rounded-lg transition-colors"
            >
              {{ t('watchlist.form.cancel') }}
            </button>
            <button
              @click="saveOrder"
              :disabled="savingOrder"
              class="nuc-press cursor-pointer bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors disabled:opacity-50"
            >
              {{ t('watchlist.collections.done') }}
            </button>
          </template>

          <template v-else>
            <SettingsButton />
            <button
              v-if="collection"
              @click="showAdd = true"
              :title="t('watchlist.collections.addItems')"
              class="group nuc-press cursor-pointer flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-3 sm:px-4 py-2 rounded-lg transition-colors"
            >
              <Icon name="plus" class="w-4 h-4 nuc-pop" :sw="2.5" />
              <span class="hidden sm:inline">{{ t('watchlist.collections.addItems') }}</span>
            </button>
            <button
              v-if="collection && items.length > 1"
              @click="startReorder"
              :title="t('watchlist.collections.reorder')"
              class="cursor-pointer p-2 text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            >
              <Icon name="menu" class="w-4 h-4" />
            </button>
            <button
              v-if="collection"
              @click="showRename = true"
              :title="t('watchlist.collections.rename')"
              class="cursor-pointer p-2 text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            >
              <Icon name="edit" class="w-4 h-4" />
            </button>
            <button
              v-if="collection"
              @click="showDeleteCol = true"
              :title="t('watchlist.collections.delete')"
              class="nuc-trash cursor-pointer p-2 text-slate-400 hover:text-red-500 dark:hover:text-red-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            >
              <TrashIcon class="w-4 h-4" stroke-width="2" />
            </button>
          </template>
        </template>
      </AppHeader>

      <main class="max-w-4xl mx-auto px-4 py-6 flex flex-col gap-6">
        <!-- Collection meta -->
        <div v-if="collection" class="flex items-start gap-4">
          <div class="w-12 h-12 shrink-0 rounded-2xl bg-gradient-to-br from-indigo-500/20 to-purple-500/10 dark:from-indigo-500/25 dark:to-purple-500/10 text-indigo-600 dark:text-indigo-300 flex items-center justify-center ring-1 ring-inset ring-white/50 dark:ring-white/10">
            <Icon name="folder" class="w-6 h-6" :sw="1.5" />
          </div>
          <div class="min-w-0 flex flex-col gap-1 pt-0.5">
            <h1 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-white truncate">{{ collection.name }}</h1>
            <p class="text-sm text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.itemCount', { count: items.length }) }}</p>
            <p v-if="collection.description" class="text-sm text-slate-500 dark:text-slate-400 mt-1 leading-relaxed">{{ collection.description }}</p>
          </div>
        </div>

        <div v-if="loading" class="text-center py-16 text-slate-400 dark:text-slate-500">{{ t('watchlist.state.loading') }}</div>

        <div v-else-if="notFound" class="text-center py-16 flex flex-col items-center gap-3">
          <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.collections.notFound') }}</p>
          <RouterLink to="/collections" class="text-sm text-indigo-600 dark:text-indigo-400 hover:underline">{{ t('watchlist.collections.backToCollections') }}</RouterLink>
        </div>

        <!-- Empty collection -->
        <div v-else-if="!items.length" class="text-center py-16 flex flex-col items-center gap-4">
          <div class="w-14 h-14 rounded-2xl bg-indigo-500/10 dark:bg-indigo-500/15 text-indigo-600 dark:text-indigo-300 flex items-center justify-center">
            <Icon name="folder" class="w-7 h-7" :sw="1.5" />
          </div>
          <p class="text-sm text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.emptyItemsHint') }}</p>
          <button
            @click="showAdd = true"
            class="nuc-press cursor-pointer inline-flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors"
          >
            <Icon name="plus" class="w-4 h-4" :sw="2.5" />
            {{ t('watchlist.collections.addItems') }}
          </button>
        </div>

        <!-- Reorder mode: drag, type a position, or use the arrows. -->
        <template v-else-if="reordering">
          <div class="flex items-center gap-2 -mt-2 text-sm text-slate-400 dark:text-slate-500">
            <Icon name="menu" class="w-4 h-4 shrink-0" />
            <span>{{ t('watchlist.collections.reorderHint') }}</span>
          </div>
          <ul class="flex flex-col gap-2">
            <li
              v-for="(item, i) in draft"
              :key="item._id"
              draggable="true"
              @dragstart="onDragStart(i, $event)"
              @dragover.prevent="onDragOver(i)"
              @dragend="onDragEnd"
              :class="[
                'group flex items-center gap-2.5 sm:gap-3 p-2 rounded-xl border bg-white/80 dark:bg-slate-800/70 backdrop-blur-sm transition-all duration-150 select-none',
                dragIndex === i
                  ? 'border-indigo-400/70 ring-2 ring-indigo-400/40 shadow-lg shadow-indigo-500/10 opacity-95 scale-[1.01]'
                  : 'border-white/60 dark:border-white/8 shadow-sm hover:border-indigo-300/70 dark:hover:border-indigo-400/25',
              ]"
            >
              <!-- Drag handle -->
              <span
                class="shrink-0 cursor-grab active:cursor-grabbing text-slate-300 dark:text-slate-600 group-hover:text-slate-400 dark:group-hover:text-slate-400 transition-colors"
                :title="t('watchlist.collections.reorder')"
              >
                <Icon name="menu" class="w-4 h-4" />
              </span>

              <!-- Editable position — type a number to jump there. -->
              <input
                :value="i + 1"
                type="number"
                min="1"
                :max="draft.length"
                inputmode="numeric"
                :title="t('watchlist.collections.positionHint')"
                @change="moveTo(i, $event.target.value)"
                @keydown.enter.prevent="$event.target.blur()"
                @focus="$event.target.select()"
                class="pos-input w-9 h-9 shrink-0 rounded-lg bg-black/[0.04] dark:bg-white/8 text-center text-sm font-semibold tabular-nums text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:bg-white dark:focus:bg-slate-700 transition-colors"
              />

              <!-- Poster -->
              <div class="w-9 h-12 shrink-0 rounded-md overflow-hidden bg-slate-100 dark:bg-slate-700 flex items-center justify-center ring-1 ring-black/5 dark:ring-white/10">
                <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
                <ArchiveBoxIcon v-else class="w-4 h-4 text-slate-300 dark:text-slate-600" />
              </div>

              <!-- Title -->
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-slate-900 dark:text-white truncate">{{ item.title }}</p>
                <p class="text-xs text-slate-400 dark:text-slate-500 truncate">
                  {{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}<span v-if="item.year"> · {{ item.year }}</span>
                </p>
              </div>

              <!-- Up / down -->
              <div class="flex items-center shrink-0 rounded-lg bg-black/[0.03] dark:bg-white/5 p-0.5 gap-0.5">
                <button
                  type="button"
                  :disabled="i === 0"
                  @click="move(i, i - 1)"
                  :title="t('watchlist.collections.moveUp')"
                  class="cursor-pointer w-7 h-7 rounded-md flex items-center justify-center text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-white dark:hover:bg-white/10 transition-colors disabled:opacity-25 disabled:cursor-default disabled:hover:bg-transparent"
                >
                  <Icon name="chevronUp" class="w-4 h-4" :sw="2.5" />
                </button>
                <button
                  type="button"
                  :disabled="i === draft.length - 1"
                  @click="move(i, i + 1)"
                  :title="t('watchlist.collections.moveDown')"
                  class="cursor-pointer w-7 h-7 rounded-md flex items-center justify-center text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-white dark:hover:bg-white/10 transition-colors disabled:opacity-25 disabled:cursor-default disabled:hover:bg-transparent"
                >
                  <Icon name="chevronDown" class="w-4 h-4" :sw="2.5" />
                </button>
              </div>
            </li>
          </ul>
        </template>

        <template v-else>
          <!-- Controls: search · status · type · favorite · layout -->
          <div class="glass rounded-2xl p-2 flex flex-col gap-2.5">
            <div class="relative">
              <Icon name="search" class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 dark:text-slate-500 pointer-events-none" />
              <input
                v-model="searchQuery"
                type="text"
                :placeholder="t('watchlist.header.search')"
                autocomplete="off"
                class="w-full pl-9 pr-8 py-1.5 text-sm bg-black/5 dark:bg-white/8 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-slate-500 rounded-lg border border-transparent focus:border-indigo-500/50 focus:outline-none focus:bg-white dark:focus:bg-white/12 transition-all"
              />
              <button
                v-if="searchQuery"
                @click="searchQuery = ''"
                class="cursor-pointer absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
              >
                <Icon name="close" class="w-3.5 h-3.5" :sw="2.5" />
              </button>
            </div>

            <div class="h-px bg-black/[0.06] dark:bg-white/8 -mx-2" />

            <div class="flex items-center gap-3">
              <div class="min-w-0 flex-1 overflow-x-auto no-scrollbar">
                <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1">
                  <button
                    v-for="tab in STATUS_TABS"
                    :key="tab.key"
                    @click="activeStatus = tab.key"
                    :class="[
                      'cursor-pointer whitespace-nowrap px-3.5 py-1.5 rounded-lg text-sm font-medium transition-all',
                      activeStatus === tab.key ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                    ]"
                  >
                    {{ tab.label }}
                  </button>
                </div>
              </div>
              <span class="hidden sm:block shrink-0 text-xs text-slate-400 dark:text-slate-500 tabular-nums pr-1">
                {{ t('watchlist.list.showing', { shown: visible.length, total: items.length }) }}
              </span>
            </div>

            <div class="h-px bg-black/[0.06] dark:bg-white/8 -mx-2" />

            <div class="flex flex-col gap-2.5 lg:flex-row lg:items-center lg:justify-between">
              <div class="flex items-center gap-2 self-start">
                <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1">
                  <button
                    v-for="tab in TYPE_TABS"
                    :key="tab.key"
                    @click="activeType = tab.key"
                    :class="[
                      'cursor-pointer whitespace-nowrap px-3.5 py-1.5 rounded-lg text-sm font-medium transition-all',
                      activeType === tab.key ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                    ]"
                  >
                    {{ tab.label }}
                  </button>
                </div>
                <button
                  @click="onlyFavorite = !onlyFavorite"
                  :title="t('watchlist.filter.favorites')"
                  :class="[
                    'nuc-fav nuc-press cursor-pointer inline-flex items-center gap-1.5 h-9 px-3 rounded-xl text-sm font-medium transition-colors',
                    onlyFavorite ? 'bg-rose-500/15 text-rose-600 dark:text-rose-400' : 'bg-black/[0.04] dark:bg-white/5 text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                  ]"
                >
                  <FavoriteHeart :active="onlyFavorite" class="w-4 h-4" />
                  <span class="hidden sm:inline">{{ t('watchlist.filter.favorites') }}</span>
                </button>
              </div>

              <div class="flex items-center h-9 bg-black/[0.05] dark:bg-white/5 rounded-lg p-1 gap-0.5 self-start">
                <button @click="gridStyle = 'list'" :title="t('watchlist.list.viewList')" :class="['cursor-pointer h-full px-2.5 rounded-md inline-flex items-center transition-colors', gridStyle === 'list' ? 'text-indigo-600 dark:text-white bg-white dark:bg-white/15 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">
                  <ListIcon class="w-4 h-4" />
                </button>
                <button @click="gridStyle = 'big'" :title="t('watchlist.list.viewGrid2')" :class="['cursor-pointer h-full px-2.5 rounded-md inline-flex items-center transition-colors', gridStyle === 'big' ? 'text-indigo-600 dark:text-white bg-white dark:bg-white/15 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">
                  <ViewColumns2Icon class="w-4 h-4" />
                </button>
                <button @click="gridStyle = 'small'" :title="t('watchlist.list.viewGrid3')" :class="['cursor-pointer h-full px-2.5 rounded-md inline-flex items-center transition-colors', gridStyle === 'small' ? 'text-indigo-600 dark:text-white bg-white dark:bg-white/15 shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-white']">
                  <ViewColumns3Icon class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>

          <!-- No matches for the active filters -->
          <div v-if="!visible.length" class="text-center py-12 flex flex-col items-center gap-3">
            <p class="text-sm text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.noMatches') }}</p>
            <button
              v-if="filtersActive"
              @click="clearFilters"
              class="cursor-pointer text-sm text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              {{ t('watchlist.collections.clearFilters') }}
            </button>
          </div>

          <div v-else class="grid gap-3 nuc-stagger" :class="gridClass" style="--nuc-step: 32ms">
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
      </main>

      <ItemFormModal
        :show="showEditItem"
        :initial="editingItem"
        @close="showEditItem = false; editingItem = null"
        @submit="submitEdit"
      />
      <ManageCollectionsModal
        :show="showManage"
        :item="managingItem"
        @close="showManage = false"
        @updated="onManaged"
      />
      <CollectionFormModal
        :show="showRename"
        :initial="collection"
        @close="showRename = false"
        @submit="submitRename"
      />
      <AddItemsModal
        :show="showAdd"
        :collection-id="id"
        :member-ids="items.map((i) => i._id)"
        @close="showAdd = false"
        @added="onItemsAdded"
      />
      <TemplateModal
        :show="showDeleteCol"
        :title="t('watchlist.collections.deleteTitle')"
        :message="t('watchlist.collections.deleteMessage', { name: collection?.name })"
        :confirm-label="t('watchlist.collections.delete')"
        :busy="deletingBusy"
        @confirm="confirmDeleteCol"
        @cancel="showDeleteCol = false"
      />
    </div>
  </div>
</template>

<style scoped>
/* The position field is a number input, but the up/down spinners are redundant
   next to the move buttons — hide them for a clean pill. */
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
