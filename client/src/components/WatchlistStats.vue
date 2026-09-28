<script setup>
import { computed } from 'vue'
import { logoUrl } from '@/api/tmdb.js'
import { itemRuntime, watchedMinutes, remainingMinutes } from '@/utils/progress.js'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({ items: { type: Array, required: true } })

const sum = (list, fn) => list.reduce((s, i) => s + fn(i), 0)

function fmtTime(min) {
  if (!min) return '—'
  const d = Math.floor(min / 1440)
  const h = Math.floor((min % 1440) / 60)
  const m = min % 60
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

const byStatus = (s) => props.items.filter((i) => i.status === s)
const completed = computed(() => byStatus('completed'))
const watching = computed(() => byStatus('watching'))
const planned = computed(() => byStatus('planned'))

const STATUS = computed(() => [
  { key: 'completed', label: t('watchlist.status.completed'), count: completed.value.length, cls: 'st-completed' },
  { key: 'watching', label: t('watchlist.status.watching'), count: watching.value.length, cls: 'st-watching' },
  { key: 'planned', label: t('watchlist.status.planned'), count: planned.value.length, cls: 'st-planned' },
])
const statusSegments = computed(() => STATUS.value.filter((s) => s.count > 0))

const watchedTime = computed(() => fmtTime(sum(props.items, watchedMinutes)))

const tiles = computed(() => [
  { label: t('watchlist.stats.inProgress'), value: fmtTime(sum(watching.value, remainingMinutes)), note: t('watchlist.stats.titlesLeft', { count: watching.value.length }) },
  { label: t('watchlist.stats.planned'), value: fmtTime(sum(planned.value, remainingMinutes)), note: t('watchlist.stats.titlesLeft', { count: planned.value.length }) },
  { label: t('watchlist.stats.total'), value: fmtTime(sum(props.items, itemRuntime)), note: t('watchlist.stats.titles', { count: props.items.length }) },
])

const avgOf = (list, key) => (list.length ? (list.reduce((s, i) => s + i[key], 0) / list.length).toFixed(1) : null)
const ratedItems = computed(() => props.items.filter((i) => i.rating))
const tmdbItems = computed(() => props.items.filter((i) => i.tmdbRating))
const avgRating = computed(() => avgOf(ratedItems.value, 'rating'))
const avgTmdb = computed(() => avgOf(tmdbItems.value, 'tmdbRating'))

const types = computed(() =>
  [
    { key: 'movie', label: t('watchlist.stats.movies') },
    { key: 'show', label: t('watchlist.stats.shows') },
  ].map((ty) => {
    const all = props.items.filter((i) => i.type === ty.key)
    const done = all.filter((i) => i.status === 'completed').length
    return { ...ty, total: all.length, done, pct: all.length ? (done / all.length) * 100 : 0 }
  })
)

const topProviders = computed(() => {
  const map = {}
  for (const i of props.items) {
    if (!i.streamingProvider) continue
    map[i.streamingProvider] ??= { name: i.streamingProvider, logo: i.streamingLogo, count: 0 }
    map[i.streamingProvider].count++
  }
  return Object.values(map).sort((a, b) => b.count - a.count).slice(0, 5)
})

const topYears = computed(() => {
  const map = {}
  for (const i of props.items) if (i.year) map[i.year] = (map[i.year] || 0) + 1
  return Object.entries(map)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([year, count]) => ({ year: Number(year), count }))
})

const barWidth = (count, max) => `${Math.max(4, (count / max) * 100)}%`
</script>

<template>
  <div class="stats flex flex-col gap-3">
    <section class="lg-glass rounded-3xl p-5">
      <p class="stats-label">{{ t('watchlist.stats.watched') }}</p>
      <p class="mt-1 text-5xl font-semibold tracking-tight text-slate-900 dark:text-white">{{ watchedTime }}</p>
      <p class="mt-1 text-xs text-slate-500 dark:text-white/50">{{ t('watchlist.stats.watchedNote') }}</p>

      <div v-if="items.length" class="mt-5">
        <div class="flex h-2.5 gap-[2px] rounded-full overflow-hidden" role="img" :aria-label="STATUS.map((s) => `${s.label} ${s.count}`).join(', ')">
          <div
            v-for="s in statusSegments"
            :key="s.key"
            :class="['h-full', s.cls]"
            :style="{ flexGrow: s.count }"
            :title="`${s.label}: ${s.count}`"
          />
        </div>
        <ul class="mt-3 flex flex-wrap gap-x-4 gap-y-1.5">
          <li v-for="s in STATUS" :key="s.key" class="flex items-center gap-1.5 text-sm">
            <span :class="['w-2 h-2 rounded-full', s.cls]" />
            <span class="text-slate-600 dark:text-white/70">{{ s.label }}</span>
            <span class="font-semibold text-slate-900 dark:text-white">{{ s.count }}</span>
          </li>
        </ul>
      </div>
    </section>

    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <section v-for="tile in tiles" :key="tile.label" class="lg-glass rounded-3xl p-4">
        <p class="stats-label">{{ tile.label }}</p>
        <p class="mt-1.5 text-2xl font-semibold text-slate-900 dark:text-white">{{ tile.value }}</p>
        <p class="mt-0.5 text-xs text-slate-500 dark:text-white/50">{{ tile.note }}</p>
      </section>

      <section class="lg-glass rounded-3xl p-4">
        <p class="stats-label">{{ t('watchlist.stats.ratings') }}</p>
        <div class="mt-1.5 flex items-end gap-4">
          <div>
            <p class="text-2xl font-semibold text-slate-900 dark:text-white">{{ avgRating ?? '—' }}</p>
            <p class="mt-0.5 text-xs text-slate-500 dark:text-white/50">{{ t('watchlist.stats.yourAvg') }}</p>
          </div>
          <div>
            <p class="text-2xl font-semibold text-slate-900 dark:text-white">{{ avgTmdb ?? '—' }}</p>
            <p class="mt-0.5 text-xs text-slate-500 dark:text-white/50">{{ t('watchlist.stats.tmdbAvg') }}</p>
          </div>
        </div>
      </section>
    </div>

    <section class="lg-glass rounded-3xl p-5">
      <p class="stats-label">{{ t('watchlist.stats.typeBreakdown') }}</p>
      <div class="mt-3 flex flex-col gap-4">
        <div v-for="ty in types" :key="ty.key">
          <div class="flex items-baseline justify-between gap-3">
            <span class="text-sm font-medium text-slate-900 dark:text-white">
              {{ ty.label }} <span class="font-normal text-slate-500 dark:text-white/50">{{ ty.total }}</span>
            </span>
            <span class="text-xs text-slate-500 dark:text-white/50">{{ t('watchlist.stats.done', { count: ty.done }) }}</span>
          </div>
          <div class="mt-2 h-2 rounded-full meter-track overflow-hidden" :title="`${ty.done} / ${ty.total}`">
            <div class="h-full rounded-full st-completed transition-[width] duration-700 ease-out" :style="{ width: `${ty.pct}%` }" />
          </div>
        </div>
      </div>
    </section>

    <div v-if="topProviders.length || topYears.length" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <section v-if="topProviders.length" class="lg-glass rounded-3xl p-5">
        <p class="stats-label">{{ t('watchlist.stats.availableOn') }}</p>
        <ul class="mt-3 flex flex-col gap-3">
          <li v-for="p in topProviders" :key="p.name" class="bar-row" :title="`${p.name}: ${p.count}`">
            <div class="flex items-center gap-2 min-w-0">
              <img v-if="p.logo" :src="logoUrl(p.logo)" :alt="p.name" class="w-5 h-5 rounded-md shrink-0 object-cover" />
              <span v-else class="w-5 h-5 rounded-md shrink-0 meter-track" />
              <span class="text-sm text-slate-700 dark:text-white/80 truncate">{{ p.name }}</span>
            </div>
            <div class="flex items-center gap-2">
              <div class="flex-1 h-2 flex">
                <div class="h-full bar-fill" :style="{ width: barWidth(p.count, topProviders[0].count) }" />
              </div>
              <span class="w-5 text-right text-xs font-medium tabular-nums text-slate-600 dark:text-white/70">{{ p.count }}</span>
            </div>
          </li>
        </ul>
      </section>

      <section v-if="topYears.length" class="lg-glass rounded-3xl p-5">
        <p class="stats-label">{{ t('watchlist.stats.topYears') }}</p>
        <ul class="mt-3 flex flex-col gap-3">
          <li v-for="y in topYears" :key="y.year" class="flex items-center gap-3" :title="`${y.year}: ${y.count}`">
            <span class="w-10 shrink-0 text-sm tabular-nums text-slate-600 dark:text-white/70">{{ y.year }}</span>
            <div class="flex-1 h-2 flex">
              <div class="h-full bar-fill" :style="{ width: barWidth(y.count, topYears[0].count) }" />
            </div>
            <span class="w-5 text-right text-xs font-medium tabular-nums text-slate-600 dark:text-white/70">{{ y.count }}</span>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>

<style scoped>
.stats {
  --st-completed: #1baf7a;
  --st-watching: #2a78d6;
  --st-planned: #eb6834;
  --accent: #6366f1;
  --track: rgba(15, 23, 42, 0.08);
}
.dark .stats {
  --st-completed: #199e70;
  --st-watching: #3987e5;
  --st-planned: #d95926;
  --accent: #818cf8;
  --track: rgba(255, 255, 255, 0.09);
}

.stats-label {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: rgb(100 116 139);
}
.dark .stats-label { color: rgba(255, 255, 255, 0.45); }

.st-completed { background: var(--st-completed); }
.st-watching { background: var(--st-watching); }
.st-planned { background: var(--st-planned); }
.meter-track { background: var(--track); }

.bar-row {
  display: grid;
  grid-template-columns: minmax(0, 7.5rem) 1fr;
  align-items: center;
  gap: 12px;
}

.bar-fill {
  background: var(--accent);
  border-radius: 0 4px 4px 0;
  transition: width 0.7s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.15s ease;
}
li:hover .bar-fill { opacity: 0.8; }
</style>
