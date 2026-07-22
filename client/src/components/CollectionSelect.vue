<script setup>
import { ref, computed } from 'vue'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'

// Toggle-list of the user's collections with inline "create new", bound with
// v-model (array of collection ids). Shared by the add/edit item form and the
// per-item "manage collections" modal so the selection UI lives in one place.
const { t } = useI18n()
const { collections, create } = useCollections()

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  listClass: { type: String, default: 'max-h-64 overflow-y-auto' },
})
const emit = defineEmits(['update:modelValue'])

const search = ref('')
const creating = ref(false)

const selected = computed(() => new Set(props.modelValue.map(String)))

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  return q ? collections.value.filter((c) => c.name.toLowerCase().includes(q)) : collections.value
})
const exactExists = computed(() =>
  filtered.value.some((c) => c.name.toLowerCase() === search.value.trim().toLowerCase())
)

function toggle(id) {
  const key = String(id)
  const next = new Set(selected.value)
  next.has(key) ? next.delete(key) : next.add(key)
  emit('update:modelValue', [...next])
}

async function createInline() {
  const name = search.value.trim()
  if (!name || creating.value) return
  creating.value = true
  try {
    const col = await create({ name })
    emit('update:modelValue', [...props.modelValue, col._id])
    search.value = ''
  } finally {
    creating.value = false
  }
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="relative shrink-0">
      <Icon name="search" class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 dark:text-slate-500 pointer-events-none" />
      <input
        v-model="search"
        type="text"
        :placeholder="t('watchlist.collections.searchOrCreate')"
        class="w-full bg-black/5 dark:bg-white/8 text-slate-900 dark:text-white rounded-lg pl-9 pr-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
        @keydown.enter.prevent="createInline"
      />
    </div>

    <div :class="['flex flex-col gap-0.5', listClass]">
      <button
        v-for="col in filtered"
        :key="col._id"
        type="button"
        class="cursor-pointer flex items-center gap-3 px-2.5 py-2 rounded-lg text-left transition-colors hover:bg-black/[0.04] dark:hover:bg-white/5"
        @click="toggle(col._id)"
      >
        <span
          :class="[
            'w-5 h-5 shrink-0 rounded-md border flex items-center justify-center transition-colors',
            selected.has(String(col._id)) ? 'bg-indigo-600 border-indigo-600 text-white' : 'border-slate-300 dark:border-slate-600',
          ]"
        >
          <Icon v-if="selected.has(String(col._id))" name="checkBold" class="w-3 h-3" :sw="3" />
        </span>
        <span class="flex-1 min-w-0">
          <span class="block text-sm font-medium text-slate-900 dark:text-white truncate">{{ col.name }}</span>
          <span class="block text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.itemCount', { count: col.itemCount || 0 }) }}</span>
        </span>
      </button>

      <button
        v-if="search.trim() && !exactExists"
        type="button"
        :disabled="creating"
        class="cursor-pointer flex items-center gap-3 px-2.5 py-2 rounded-lg text-left text-indigo-600 dark:text-indigo-400 hover:bg-indigo-50 dark:hover:bg-indigo-500/10 transition-colors disabled:opacity-50"
        @click="createInline"
      >
        <span class="w-5 h-5 shrink-0 rounded-md border border-dashed border-indigo-400 flex items-center justify-center">
          <Icon name="plus" class="w-3 h-3" :sw="2.5" />
        </span>
        <span class="text-sm font-medium truncate">{{ t('watchlist.collections.createNamed', { name: search.trim() }) }}</span>
      </button>

      <p v-if="!collections.length && !search.trim()" class="px-2.5 py-6 text-center text-sm text-slate-400 dark:text-slate-500">
        {{ t('watchlist.collections.noneYetHint') }}
      </p>
    </div>
  </div>
</template>
