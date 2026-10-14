<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { hasTMDbKey, searchPeople } from '@/api/tmdb.js'
import { CREW_JOBS, creditFromPerson } from '@/utils/credits.js'
import { useI18n } from '@core/useI18n.js'
import { Icon } from '@core/icons'

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
})
const emit = defineEmits(['update:modelValue'])

const { t } = useI18n()
const query = ref('')
const results = ref([])
const SEARCH_DELAY = 300
const MAX_RESULTS = 5
let timer = null
let searchId = 0

const trimmed = computed(() => query.value.trim())
const credits = computed(() => props.modelValue || [])
const initials = (name) => name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase()
const jobsFor = (credit) => (credit.cast || CREW_JOBS.includes(credit.role) || !credit.role ? CREW_JOBS : [...CREW_JOBS, credit.role])

watch(trimmed, (q) => {
  clearTimeout(timer)
  results.value = []
  if (q.length < 2 || !hasTMDbKey.value) return
  const id = ++searchId
  timer = setTimeout(async () => {
    const found = await searchPeople(q).catch(() => [])
    if (id !== searchId) return
    const added = new Set(credits.value.map((c) => c.personId).filter(Boolean))
    results.value = found.filter((p) => !added.has(p.id)).slice(0, MAX_RESULTS)
  }, SEARCH_DELAY)
})
onBeforeUnmount(() => clearTimeout(timer))

function append(credit) {
  emit('update:modelValue', [...credits.value, credit])
  query.value = ''
  results.value = []
}

function addTyped() {
  if (trimmed.value) append({ name: trimmed.value, role: '', cast: true, personId: null, photo: null })
}

function patch(index, change) {
  emit('update:modelValue', credits.value.map((c, i) => (i === index ? { ...c, ...change } : c)))
}

function setPart(index, value) {
  patch(index, value === '' ? { cast: true, role: '' } : { cast: false, role: value })
}

function remove(index) {
  emit('update:modelValue', credits.value.filter((_, i) => i !== index))
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <ul v-if="credits.length" class="flex flex-col gap-1.5">
      <li v-for="(credit, i) in credits" :key="`${credit.personId ?? credit.name}-${i}`" class="flex items-center gap-2.5 rounded-lg bg-slate-100 dark:bg-slate-700/60 px-2.5 py-1.5">
        <img v-if="credit.photo" :src="credit.photo" :alt="credit.name" class="h-9 w-9 shrink-0 rounded-full object-cover" />
        <span v-else class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-slate-200 dark:bg-slate-600 text-xs font-semibold text-slate-500 dark:text-slate-300">{{ initials(credit.name) }}</span>
        <div class="min-w-0 flex-1">
          <p class="flex items-center gap-1 text-sm text-slate-900 dark:text-white">
            <span class="truncate">{{ credit.name }}</span>
            <span v-if="credit.personId" :title="t('watchlist.form.creditsFromTmdb')" class="shrink-0 text-indigo-500">
              <Icon name="check" class="h-3.5 w-3.5" :sw="3" />
            </span>
          </p>
          <input
            v-if="credit.cast"
            :value="credit.role"
            @input="patch(i, { role: $event.target.value })"
            :placeholder="t('watchlist.form.creditsCharacter')"
            class="w-full bg-transparent text-xs text-slate-500 dark:text-slate-400 placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none"
          />
        </div>
        <select
          :value="credit.cast ? '' : credit.role"
          @change="setPart(i, $event.target.value)"
          class="cursor-pointer shrink-0 rounded-full bg-white dark:bg-slate-800 px-2.5 py-1 text-xs font-medium text-indigo-600 dark:text-indigo-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
        >
          <option value="">{{ t('watchlist.form.creditsCast') }}</option>
          <option v-for="job in jobsFor(credit)" :key="job" :value="job">{{ CREW_JOBS.includes(job) ? t(`watchlist.form.job.${job}`) : job }}</option>
        </select>
        <button
          type="button"
          @click="remove(i)"
          :title="t('watchlist.form.creditsRemove', { name: credit.name })"
          class="nuc-press cursor-pointer shrink-0 p-1 text-slate-400 hover:text-red-500 dark:hover:text-red-400 transition-colors"
        >
          <Icon name="close" class="h-4 w-4" :sw="2.5" />
        </button>
      </li>
    </ul>

    <div class="flex gap-2">
      <input
        v-model="query"
        @keydown.enter.prevent="addTyped"
        autocomplete="off"
        :placeholder="hasTMDbKey ? t('watchlist.form.creditsAddSearch') : t('watchlist.form.creditsAdd')"
        class="min-w-0 flex-1 bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
      />
      <button
        v-if="trimmed"
        type="button"
        @click="addTyped"
        class="nuc-press cursor-pointer shrink-0 rounded-lg bg-indigo-600 hover:bg-indigo-500 px-3 text-sm font-medium text-white transition-colors"
      >{{ t('watchlist.form.creditsAddButton') }}</button>
    </div>

    <ul v-if="results.length" class="flex flex-col overflow-hidden rounded-lg border border-slate-200 dark:border-slate-600">
      <li v-for="person in results" :key="person.id">
        <button
          type="button"
          @click="append(creditFromPerson(person))"
          class="cursor-pointer flex w-full items-center gap-3 px-3 py-1.5 text-left hover:bg-slate-100 dark:hover:bg-slate-600 transition-colors"
        >
          <img v-if="person.photo" :src="person.photo" :alt="person.name" class="h-8 w-8 shrink-0 rounded-full object-cover" />
          <span v-else class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-slate-200 dark:bg-slate-600 text-[10px] font-semibold text-slate-500 dark:text-slate-300">{{ initials(person.name) }}</span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-slate-900 dark:text-white">{{ person.name }}</span>
            <span v-if="person.knownFor" class="block text-xs text-slate-500 dark:text-slate-400">{{ person.knownFor }}</span>
          </span>
          <Icon name="plus" class="h-4 w-4 shrink-0 text-indigo-500" :sw="2.5" />
        </button>
      </li>
    </ul>

    <p class="text-xs text-slate-400 dark:text-slate-500">{{ hasTMDbKey ? t('watchlist.form.creditsHintKey') : t('watchlist.form.creditsHint') }}</p>
  </div>
</template>
