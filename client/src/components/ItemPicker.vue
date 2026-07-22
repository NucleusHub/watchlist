<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { Icon } from '@core/icons'
import ArchiveBoxIcon from '@/assets/icons/archive-box.svg?component'
import { useI18n } from '@core/useI18n.js'
import { getItems } from '@/api/watchlist.js'

// Searchable multi-select over the user's watchlist items. Selection is a plain
// array of ids bound with v-model; the caller decides what to do with them
// (assign to a new collection, add to an existing one, …). Shared by the create
// modal and the "add items" modal so the row markup lives in one place.
const { t } = useI18n()

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  // Ids to hide from the list (e.g. items already in the collection).
  exclude: { type: Array, default: () => [] },
  // Scroll container sizing, so each host can size the list to its layout.
  listClass: { type: String, default: 'max-h-72 overflow-y-auto' },
})
// `update:selectedItems` is optional — it hands the caller the full selected
// item objects (e.g. so a cover preview can read their posters).
const emit = defineEmits(['update:modelValue', 'update:selectedItems'])

const allItems = ref([])
const loading = ref(false)
const search = ref('')

onMounted(async () => {
  loading.value = true
  try {
    allItems.value = await getItems()
  } catch {
    allItems.value = []
  } finally {
    loading.value = false
  }
})

watch(
  [() => props.modelValue, allItems],
  () => {
    const sel = new Set(props.modelValue.map(String))
    emit('update:selectedItems', allItems.value.filter((i) => sel.has(String(i._id))))
  },
  { immediate: true, deep: true }
)

const selected = computed(() => new Set(props.modelValue.map(String)))
const excludeSet = computed(() => new Set(props.exclude.map(String)))

const candidates = computed(() => {
  const q = search.value.trim().toLowerCase()
  return allItems.value
    .filter((i) => !excludeSet.value.has(String(i._id)))
    .filter((i) => !q || i.title.toLowerCase().includes(q))
})

function toggle(id) {
  const key = String(id)
  const next = new Set(selected.value)
  next.has(key) ? next.delete(key) : next.add(key)
  emit('update:modelValue', [...next])
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="relative shrink-0">
      <Icon name="search" class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 dark:text-slate-500 pointer-events-none" />
      <input
        v-model="search"
        type="text"
        :placeholder="t('watchlist.collections.searchItems')"
        class="w-full bg-black/5 dark:bg-white/8 text-slate-900 dark:text-white rounded-lg pl-9 pr-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
      />
    </div>

    <div v-if="loading" class="py-10 text-center text-sm text-slate-400 dark:text-slate-500">
      {{ t('watchlist.state.loading') }}
    </div>
    <div v-else-if="!candidates.length" class="py-10 text-center text-sm text-slate-400 dark:text-slate-500">
      {{ excludeSet.size ? t('watchlist.collections.allAdded') : t('watchlist.collections.noItems') }}
    </div>
    <div v-else :class="['flex flex-col gap-0.5', listClass]">
      <button
        v-for="item in candidates"
        :key="item._id"
        type="button"
        class="cursor-pointer flex items-center gap-3 px-2.5 py-2 rounded-lg text-left transition-colors hover:bg-black/[0.04] dark:hover:bg-white/5"
        @click="toggle(item._id)"
      >
        <span
          :class="[
            'w-5 h-5 shrink-0 rounded-md border flex items-center justify-center transition-colors',
            selected.has(String(item._id)) ? 'bg-indigo-600 border-indigo-600 text-white' : 'border-slate-300 dark:border-slate-600',
          ]"
        >
          <Icon v-if="selected.has(String(item._id))" name="checkBold" class="w-3 h-3" :sw="3" />
        </span>
        <div class="w-8 h-11 shrink-0 rounded overflow-hidden bg-slate-100 dark:bg-slate-700 flex items-center justify-center">
          <img v-if="item.posterUrl" :src="item.posterUrl" :alt="item.title" class="w-full h-full object-cover" />
          <ArchiveBoxIcon v-else class="w-4 h-4 text-slate-300 dark:text-slate-600" />
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-slate-900 dark:text-white truncate">{{ item.title }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500">
            {{ item.type === 'movie' ? t('watchlist.type.movie') : t('watchlist.type.show') }}<span v-if="item.year"> · {{ item.year }}</span>
          </p>
        </div>
      </button>
    </div>
  </div>
</template>
