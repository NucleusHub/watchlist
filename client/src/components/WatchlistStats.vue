<script setup>
import { computed, ref } from 'vue'
import { logoUrl } from '@/api/tmdb.js'
import { itemRuntime, watchedMinutes, remainingMinutes } from '@/utils/progress.js'
import { useI18n } from '@core/useI18n.js'
import StatsCustomizeModal from '@/components/StatsCustomizeModal.vue'
import { useCountUp } from '@/composables/useCountUp.js'
import { layoutRows, loadLayout, saveLayout, standardLayout } from '@/utils/statsLayout.js'

const { t } = useI18n()

const props = defineProps({ items: { type: Array, required: true } })

const sum = (list, fn) => list.reduce((s, i) => s + fn(i), 0)

// Numbers count up with `shown` (0 -> 1); counting time starts at 1m so it never flashes "—".
const shown = useCountUp()
const cnt = (n) => Math.round(n * shown.value)
const timeAt = (min) => fmtTime(min > 0 ? Math.max(1, Math.round(min * shown.value)) : 0)

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

const completedTime = computed(() => timeAt(sum(props.items, watchedMinutes)))
const watchingTime  = computed(() => timeAt(sum(watching.value, remainingMinutes)))
const plannedTime   = computed(() => timeAt(sum(planned.value, remainingMinutes)))
const totalTime     = computed(() => timeAt(sum(props.items, itemRuntime)))

const ratedItems = computed(() => props.items.filter(i => i.rating))
const avgRating  = computed(() => {
  if (!ratedItems.value.length) return null
  return ratedItems.value.reduce((s, i) => s + i.rating, 0) / ratedItems.value.length
})

const tmdbItems = computed(() => props.items.filter(i => i.tmdbRating))
const avgTmdb   = computed(() => {
  if (!tmdbItems.value.length) return null
  return tmdbItems.value.reduce((s, i) => s + i.tmdbRating, 0) / tmdbItems.value.length
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
const avg = (v) => (v == null ? '—' : (v * shown.value).toFixed(1))

const layout = ref(loadLayout())
const customizing = ref(false)
function setLayout(next) {
  layout.value = next
  saveLayout(next)
}

const available = computed(() => {
  const cards = new Set(layout.value.map((e) => e.card))
  if (!topProviders.value.length) cards.delete('availableOn')
  if (!topYears.value.length) cards.delete('topYears')
  return cards
})
const rows = computed(() => layoutRows(layout.value, available.value))
const pct = (n) => (props.items.length ? (n / props.items.length) * 100 : 0)
const CARD = 'glass wl-card rounded-[var(--wl-r-card)] p-5 flex flex-col gap-1'
const LABEL = 'text-[13px] font-semibold text-[var(--wl-text-2)] uppercase tracking-[0.04em]'
const numClass = (size) => (size === 'small' ? 'text-2xl' : 'text-3xl')
</script>


<template>
  <div class="flex flex-col gap-3">
    <div class="flex justify-end">
      <button
        type="button"
        class="wl-btn wl-btn-secondary !min-h-9 !px-3.5 !text-[13px]"
        @click="customizing = true"
      >
        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M10.5 6h9.75M10.5 6a1.5 1.5 0 11-3 0m3 0a1.5 1.5 0 10-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-9.75 0h9.75" /></svg>
        {{ t('watchlist.stats.customize') }}
      </button>
    </div>

    <div v-if="!rows.length" class="text-center py-12 text-slate-400 dark:text-slate-500">
      <p class="font-medium text-slate-600 dark:text-slate-300">{{ t('watchlist.stats.nothingShown') }}</p>
      <p class="text-sm mt-1">{{ t('watchlist.stats.nothingShownHint') }}</p>
    </div>

    <div v-for="(row, r) in rows" :key="r" :class="['grid gap-3', row.length === 2 ? 'grid-cols-2' : 'grid-cols-1']">
      <template v-for="entry in row" :key="entry.card">

        <div v-if="entry.card === 'watched' && entry.size === 'large'" :class="[CARD, 'gap-3 p-5']">
          <p :class="LABEL">{{ t('watchlist.stats.watched') }}</p>
          <p class="text-4xl font-bold text-[#1BAF7A] tabular-nums">{{ completedTime }}</p>
          <div class="flex h-3.5 rounded-full overflow-hidden bg-slate-200 dark:bg-slate-700">
            <div class="bg-[#1BAF7A] h-full" :style="{ width: `${pct(completed.length) * shown}%` }" />
            <div class="bg-[#2A78D6] h-full" :style="{ width: `${pct(watching.length) * shown}%` }" />
            <div class="bg-slate-400 dark:bg-slate-500 h-full" :style="{ width: `${pct(planned.length) * shown}%` }" />
          </div>
          <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-500 dark:text-slate-400">
            <span class="inline-flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-[#1BAF7A]" />{{ t('watchlist.status.completed') }} <span class="tabular-nums">{{ cnt(completed.length) }}</span></span>
            <span class="inline-flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-[#2A78D6]" />{{ t('watchlist.status.watching') }} <span class="tabular-nums">{{ cnt(watching.length) }}</span></span>
            <span class="inline-flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-slate-400 dark:bg-slate-500" />{{ t('watchlist.status.planned') }} <span class="tabular-nums">{{ cnt(planned.length) }}</span></span>
          </div>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.watchedNote') }}</p>
        </div>

        <div v-else-if="entry.card === 'watched'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.watched') }}</p>
          <p class="text-2xl font-bold text-[#1BAF7A] tabular-nums">{{ completedTime }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.titlesWatched', { count: cnt(completed.length) }) }}</p>
        </div>

        <div v-else-if="entry.card === 'inProgress'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.inProgress') }}</p>
          <p :class="[numClass(entry.size), 'font-bold text-[#2A78D6] tabular-nums']">{{ watchingTime }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.titlesLeft', { count: cnt(watching.length) }) }}</p>
        </div>

        <div v-else-if="entry.card === 'planned'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.planned') }}</p>
          <p :class="[numClass(entry.size), 'font-bold text-slate-500 dark:text-slate-300 tabular-nums']">{{ plannedTime }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.titlesLeft', { count: cnt(planned.length) }) }}</p>
        </div>

        <div v-else-if="entry.card === 'total'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.total') }}</p>
          <p :class="[numClass(entry.size), 'font-bold text-indigo-600 dark:text-indigo-400 tabular-nums']">{{ totalTime }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.titles', { count: cnt(items.length) }) }}</p>
        </div>

        <div v-else-if="entry.card === 'ratings' && entry.size === 'small'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.ratings') }}</p>
          <p class="text-2xl font-bold text-amber-400 tabular-nums">{{ avg(avgRating) }} <span class="text-xs font-normal text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.yours') }}</span></p>
          <p class="text-xs text-slate-400 dark:text-slate-500 tabular-nums">TMDb {{ avg(avgTmdb) }}</p>
        </div>

        <div v-else-if="entry.card === 'ratings'" :class="[CARD, 'gap-3']">
          <p :class="LABEL">{{ t('watchlist.stats.ratings') }}</p>
          <div class="flex items-center justify-around flex-1 pt-1">
            <div class="flex flex-col items-center gap-1">
              <p class="text-3xl font-bold text-amber-400 tabular-nums">{{ avg(avgRating) }}</p>
              <p class="text-xs text-slate-400 dark:text-slate-500 text-center">{{ t('watchlist.stats.yourAvg') }}</p>
              <p v-if="ratedItems.length" class="text-xs text-slate-400 dark:text-slate-600">{{ t('watchlist.stats.rated', { count: ratedItems.length }) }}</p>
            </div>
            <div class="w-px h-12 bg-slate-200 dark:bg-slate-700" />
            <div class="flex flex-col items-center gap-1">
              <p class="text-3xl font-bold text-slate-500 dark:text-slate-300 tabular-nums">{{ avg(avgTmdb) }}</p>
              <p class="text-xs text-slate-400 dark:text-slate-500 text-center">{{ t('watchlist.stats.tmdbAvg') }}</p>
              <p v-if="tmdbItems.length" class="text-xs text-slate-400 dark:text-slate-600">{{ t('watchlist.stats.rated', { count: tmdbItems.length }) }}</p>
            </div>
          </div>
        </div>

        <div v-else-if="entry.card === 'byType' && entry.size === 'small'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.typeBreakdown') }}</p>
          <p class="text-2xl font-bold text-[#1BAF7A] tabular-nums">{{ cnt(completed.length) }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.ofWatched', { total: items.length }) }}</p>
        </div>

        <div v-else-if="entry.card === 'byType'" :class="[CARD, 'gap-3']">
          <p :class="LABEL">{{ t('watchlist.stats.typeBreakdown') }}</p>
          <div class="flex flex-col gap-3">
            <div v-for="row in [
              { key: 'movies', list: movies, badge: 'bg-purple-100 dark:bg-purple-900 text-purple-700 dark:text-purple-300', bar: 'bg-purple-500' },
              { key: 'shows', list: shows, badge: 'bg-amber-100 dark:bg-amber-900 text-amber-700 dark:text-amber-300', bar: 'bg-amber-500' },
            ]" :key="row.key">
              <div class="flex items-center justify-between mb-1.5">
                <div class="flex items-center gap-2">
                  <span :class="['text-xs px-2 py-0.5 rounded-full', row.badge]">{{ t(`watchlist.stats.${row.key}`) }}</span>
                  <span class="text-sm font-medium text-slate-900 dark:text-white tabular-nums">{{ cnt(row.list.length) }}</span>
                </div>
                <span class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.done', { count: cnt(row.list.filter(i => i.status === 'completed').length) }) }}</span>
              </div>
              <div class="h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
                <div :class="['h-full rounded-full', row.bar]" :style="{ width: `${pct(row.list.length) * shown}%` }" />
              </div>
            </div>
          </div>
        </div>

        <div v-else-if="entry.card === 'availableOn' && entry.size === 'small'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.availableOn') }}</p>
          <p class="text-2xl font-bold text-violet-400 tabular-nums">{{ cnt(topProviders[0].count) }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500 truncate">{{ t('watchlist.stats.titlesOn', { name: topProviders[0].name }) }}</p>
        </div>

        <div v-else-if="entry.card === 'availableOn'" :class="[CARD, 'gap-3']">
          <p :class="LABEL">{{ t('watchlist.stats.availableOn') }}</p>
          <div class="flex flex-col gap-2">
            <div v-for="p in topProviders" :key="p.name" class="flex items-center gap-2.5">
              <img v-if="p.logo" :src="logoUrl(p.logo)" :alt="p.name" class="w-5 h-5 rounded shrink-0 object-cover" />
              <div v-else class="w-5 h-5 rounded bg-slate-200 dark:bg-slate-700 shrink-0" />
              <span class="text-sm text-slate-700 dark:text-slate-300 flex-1 truncate">{{ p.name }}</span>
              <span class="text-xs font-medium text-slate-500 dark:text-slate-400 tabular-nums">{{ cnt(p.count) }}</span>
            </div>
          </div>
        </div>

        <div v-else-if="entry.card === 'topYears' && entry.size === 'small'" :class="CARD">
          <p :class="LABEL">{{ t('watchlist.stats.topYears') }}</p>
          <p class="text-2xl font-bold text-rose-400 tabular-nums">{{ cnt(topYears[0].count) }}</p>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.stats.titlesFrom', { year: topYears[0].year }) }}</p>
        </div>

        <div v-else-if="entry.card === 'topYears'" :class="[CARD, 'gap-3']">
          <p :class="LABEL">{{ t('watchlist.stats.topYears') }}</p>
          <div class="flex flex-col gap-2">
            <div v-for="y in topYears" :key="y.year" class="flex items-center gap-2">
              <span class="text-sm text-slate-500 dark:text-slate-400 w-11 shrink-0">{{ y.year }}</span>
              <div class="flex-1 h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
                <div class="h-full bg-indigo-500 rounded-full" :style="{ width: `${(y.count / topYears[0].count) * 100 * shown}%` }" />
              </div>
              <span class="text-xs text-slate-400 dark:text-slate-500 w-4 text-right shrink-0 tabular-nums">{{ cnt(y.count) }}</span>
            </div>
          </div>
        </div>

      </template>
    </div>

    <StatsCustomizeModal
      :show="customizing"
      :entries="layout"
      @update="setLayout"
      @reset="setLayout(standardLayout())"
      @close="customizing = false"
    />
  </div>
</template>
