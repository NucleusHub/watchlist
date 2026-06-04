<script setup>
import { computed } from 'vue'
import { logoUrl } from '@/api/tmdb.js'

const props = defineProps({ items: { type: Array, required: true } })

function totalMinutes(list) {
  return list.reduce((s, i) => s + (i.type === 'movie' ? (i.runtime || 0) : (i.showRuntime || 0)), 0)
}

function fmtTime(min) {
  if (!min) return '—'
  const d = Math.floor(min / 1440)
  const h = Math.floor((min % 1440) / 60)
  const m = min % 60
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

const completed = computed(() => props.items.filter(i => i.status === 'completed'))
const watching  = computed(() => props.items.filter(i => i.status === 'watching'))
const planned   = computed(() => props.items.filter(i => i.status === 'planned'))
const movies    = computed(() => props.items.filter(i => i.type === 'movie'))
const shows     = computed(() => props.items.filter(i => i.type === 'show'))

const completedTime = computed(() => fmtTime(totalMinutes(completed.value)))
const watchingTime  = computed(() => fmtTime(totalMinutes(watching.value)))
const plannedTime   = computed(() => fmtTime(totalMinutes(planned.value)))
const totalTime     = computed(() => fmtTime(totalMinutes(props.items)))

const ratedItems = computed(() => props.items.filter(i => i.rating))
const avgRating  = computed(() => {
  if (!ratedItems.value.length) return null
  return (ratedItems.value.reduce((s, i) => s + i.rating, 0) / ratedItems.value.length).toFixed(1)
})

const tmdbItems = computed(() => props.items.filter(i => i.tmdbRating))
const avgTmdb   = computed(() => {
  if (!tmdbItems.value.length) return null
  return (tmdbItems.value.reduce((s, i) => s + i.tmdbRating, 0) / tmdbItems.value.length).toFixed(1)
})

const topProviders = computed(() => {
  const map = {}
  props.items.forEach(i => {
    if (i.streamingProvider) {
      if (!map[i.streamingProvider]) map[i.streamingProvider] = { name: i.streamingProvider, logo: i.streamingLogo, count: 0 }
      map[i.streamingProvider].count++
    }
  })
  return Object.values(map).sort((a, b) => b.count - a.count).slice(0, 5)
})

const topYears = computed(() => {
  const map = {}
  props.items.forEach(i => { if (i.year) map[i.year] = (map[i.year] || 0) + 1 })
  return Object.entries(map)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([year, count]) => ({ year: Number(year), count }))
})
</script>

<template>
  <div class="flex flex-col gap-4">

    <!-- Watchtime -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <div class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-1 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">Watched</p>
        <p class="text-2xl font-bold text-green-400">{{ completedTime }}</p>
        <p class="text-xs text-slate-400 dark:text-slate-500">{{ completed.length }} titles</p>
      </div>
      <div class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-1 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">In progress</p>
        <p class="text-2xl font-bold text-blue-400">{{ watchingTime }}</p>
        <p class="text-xs text-slate-400 dark:text-slate-500">{{ watching.length }} titles</p>
      </div>
      <div class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-1 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">Planned</p>
        <p class="text-2xl font-bold text-slate-500 dark:text-slate-300">{{ plannedTime }}</p>
        <p class="text-xs text-slate-400 dark:text-slate-500">{{ planned.length }} titles</p>
      </div>
      <div class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-1 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">Total</p>
        <p class="text-2xl font-bold text-indigo-600 dark:text-indigo-400">{{ totalTime }}</p>
        <p class="text-xs text-slate-400 dark:text-slate-500">{{ items.length }} titles</p>
      </div>
    </div>

    <!-- Type breakdown + Ratings -->
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <div class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-3 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">Type breakdown</p>
        <div class="flex flex-col gap-3">
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <div class="flex items-center gap-2">
                <span class="text-xs px-2 py-0.5 rounded-full bg-purple-100 dark:bg-purple-900 text-purple-700 dark:text-purple-300">Movies</span>
                <span class="text-sm font-medium text-slate-900 dark:text-white">{{ movies.length }}</span>
              </div>
              <span class="text-xs text-slate-400 dark:text-slate-500">{{ movies.filter(i => i.status === 'completed').length }} done</span>
            </div>
            <div class="h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
              <div class="h-full bg-purple-500 rounded-full transition-all" :style="{ width: `${items.length ? movies.length / items.length * 100 : 0}%` }" />
            </div>
          </div>
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <div class="flex items-center gap-2">
                <span class="text-xs px-2 py-0.5 rounded-full bg-amber-100 dark:bg-amber-900 text-amber-700 dark:text-amber-300">Shows</span>
                <span class="text-sm font-medium text-slate-900 dark:text-white">{{ shows.length }}</span>
              </div>
              <span class="text-xs text-slate-400 dark:text-slate-500">{{ shows.filter(i => i.status === 'completed').length }} done</span>
            </div>
            <div class="h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
              <div class="h-full bg-amber-500 rounded-full transition-all" :style="{ width: `${items.length ? shows.length / items.length * 100 : 0}%` }" />
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-3 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">Ratings</p>
        <div class="flex items-center justify-around flex-1 pt-1">
          <div class="flex flex-col items-center gap-1">
            <p class="text-3xl font-bold text-amber-400">{{ avgRating ?? '—' }}</p>
            <p class="text-xs text-slate-400 dark:text-slate-500 text-center">your avg</p>
            <p v-if="ratedItems.length" class="text-xs text-slate-400 dark:text-slate-600">{{ ratedItems.length }} rated</p>
          </div>
          <div class="w-px h-12 bg-slate-200 dark:bg-slate-700" />
          <div class="flex flex-col items-center gap-1">
            <p class="text-3xl font-bold text-slate-500 dark:text-slate-300">{{ avgTmdb ?? '—' }}</p>
            <p class="text-xs text-slate-400 dark:text-slate-500 text-center">TMDb avg</p>
            <p v-if="tmdbItems.length" class="text-xs text-slate-400 dark:text-slate-600">{{ tmdbItems.length }} rated</p>
          </div>
        </div>
      </div>
    </div>

    <!-- Streaming + Years -->
    <div v-if="topProviders.length || topYears.length" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <div v-if="topProviders.length" class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-3 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">Available on</p>
        <div class="flex flex-col gap-2">
          <div v-for="p in topProviders" :key="p.name" class="flex items-center gap-2.5">
            <img v-if="p.logo" :src="logoUrl(p.logo)" :alt="p.name" class="w-5 h-5 rounded shrink-0 object-cover" />
            <div v-else class="w-5 h-5 rounded bg-slate-200 dark:bg-slate-700 shrink-0" />
            <span class="text-sm text-slate-700 dark:text-slate-300 flex-1 truncate">{{ p.name }}</span>
            <span class="text-xs font-medium text-slate-500 dark:text-slate-400">{{ p.count }}</span>
          </div>
        </div>
      </div>

      <div v-if="topYears.length" class="bg-white dark:bg-slate-800 rounded-xl p-4 flex flex-col gap-3 shadow-sm dark:shadow-none">
        <p class="text-xs text-slate-400 dark:text-slate-500 uppercase tracking-wide">Top release years</p>
        <div class="flex flex-col gap-2">
          <div v-for="y in topYears" :key="y.year" class="flex items-center gap-2">
            <span class="text-sm text-slate-500 dark:text-slate-400 w-11 shrink-0">{{ y.year }}</span>
            <div class="flex-1 h-1.5 bg-slate-700 rounded-full overflow-hidden">
              <div class="h-full bg-indigo-500 rounded-full" :style="{ width: `${(y.count / topYears[0].count) * 100}%` }" />
            </div>
            <span class="text-xs text-slate-400 dark:text-slate-500 w-4 text-right shrink-0">{{ y.count }}</span>
          </div>
        </div>
      </div>
    </div>

  </div>
</template>
