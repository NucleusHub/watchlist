<script setup>
import { ref, computed, watch } from 'vue'
import { updateItem } from '@/api/watchlist.js'
import { searchMulti, fetchTvDetail, buildSeasonProgress } from '@/api/tmdb.js'
import { deriveStatus } from '@/utils/progress.js'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { Icon, Spinner } from '@core/icons'

const { t } = useI18n()

const props = defineProps({
  show: { type: Boolean, default: false },
  item: { type: Object, default: null },
})
const emit = defineEmits(['close', 'updated'])

const seasons = ref([])
const loading = ref(false)
const saving = ref(false)
const loadError = ref(false)

function cloneProgress(sp) {
  return (sp || []).map((s) => ({
    seasonNumber: s.seasonNumber,
    name: s.name || t('watchlist.progress.season', { number: s.seasonNumber }),
    episodeCount: s.episodeCount || 0,
    watched: Math.min(s.watched || 0, s.episodeCount || 0),
  }))
}

async function loadSeasons() {
  const item = props.item
  if (item.seasonProgress?.length) {
    seasons.value = cloneProgress(item.seasonProgress)
    return
  }
  loading.value = true
  loadError.value = false
  try {
    const results = await searchMulti(item.title)
    const tv = results.filter((r) => r.media_type === 'tv')
    let match = tv[0]
    if (item.year) {
      const exact = tv.find((r) => r.first_air_date?.slice(0, 4) === String(item.year))
      if (exact) match = exact
    }
    if (match) {
      const detail = await fetchTvDetail(match.id)
      const built = buildSeasonProgress(detail)
      if (built.length) {
        seasons.value = built
        return
      }
    }
    throw new Error('no seasons')
  } catch {
    if (item.episodes) {
      seasons.value = [{ seasonNumber: 1, name: t('watchlist.progress.allEpisodes'), episodeCount: item.episodes, watched: 0 }]
    } else {
      seasons.value = []
      loadError.value = true
    }
  } finally {
    loading.value = false
  }
}

watch(
  () => props.show,
  (val) => {
    if (val && props.item) loadSeasons()
  },
  { immediate: true }
)

const totalEp = computed(() => seasons.value.reduce((s, x) => s + (x.episodeCount || 0), 0))
const watchedEp = computed(() =>
  seasons.value.reduce((s, x) => s + Math.min(x.watched || 0, x.episodeCount || 0), 0)
)
const pct = computed(() => (totalEp.value ? Math.round((watchedEp.value / totalEp.value) * 100) : 0))

const timeLeft = computed(() => {
  const total = props.item?.showRuntime || 0
  if (!total || !totalEp.value) return null
  const left = Math.round(total * (1 - watchedEp.value / totalEp.value))
  return fmtTime(left)
})

function fmtTime(min) {
  if (min <= 0) return '0m'
  const d = Math.floor(min / 1440)
  const h = Math.floor((min % 1440) / 60)
  const m = min % 60
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

function seasonState(s) {
  if (!s.episodeCount) return 'empty'
  if (s.watched >= s.episodeCount) return 'full'
  if (s.watched > 0) return 'partial'
  return 'empty'
}

function toggleSeason(s) {
  s.watched = s.watched >= s.episodeCount ? 0 : s.episodeCount
}

function step(s, delta) {
  s.watched = Math.max(0, Math.min(s.episodeCount, (s.watched || 0) + delta))
}

function markAll() {
  seasons.value.forEach((s) => (s.watched = s.episodeCount))
}
function resetAll() {
  seasons.value.forEach((s) => (s.watched = 0))
}

const allWatched = computed(() => totalEp.value > 0 && watchedEp.value >= totalEp.value)

async function save() {
  if (saving.value) return
  saving.value = true
  try {
    const seasonProgress = cloneProgress(seasons.value)
    const patch = {
      seasonProgress,
      seasons: seasonProgress.length || props.item.seasons || null,
      episodes: totalEp.value || props.item.episodes || null,
      status: deriveStatus(watchedEp.value, totalEp.value),
    }
    const updated = await updateItem(props.item._id, patch)
    emit('updated', updated)
    emit('close')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <TemplateModal :show="show" size="md" @cancel="$emit('close')">
    <div class="flex flex-col max-h-[85vh]">

          <div class="px-5 pt-5 pb-4 border-b border-white/30 dark:border-white/8 shrink-0">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="text-xs text-slate-500 dark:text-slate-400 uppercase tracking-wide">{{ t('watchlist.progress.label') }}</p>
                <h2 class="text-base font-semibold text-slate-900 dark:text-white truncate">{{ item?.title }}</h2>
              </div>
              <button
                @click="$emit('close')"
                :aria-label="t('watchlist.progress.close')"
                class="cursor-pointer shrink-0 p-1.5 -mr-1 text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 rounded-lg transition-colors"
              >
                <Icon name="close" class="w-4 h-4" :sw="2.5" />
              </button>
            </div>

            <div v-if="totalEp" class="mt-3">
              <div class="flex items-end justify-between mb-1.5">
                <span class="text-sm font-medium text-slate-700 dark:text-slate-200">{{ t('watchlist.progress.epCount', { watched: watchedEp, total: totalEp }) }}</span>
                <span class="text-xs" :class="allWatched ? 'text-green-500' : 'text-slate-500 dark:text-slate-400'">
                  <template v-if="allWatched">{{ t('watchlist.progress.allWatched') }}</template>
                  <template v-else-if="timeLeft">{{ t('watchlist.card.timeLeft', { time: timeLeft }) }}</template>
                </span>
              </div>
              <div class="h-1.5 bg-slate-200 dark:bg-slate-700 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full transition-all duration-300"
                  :class="allWatched ? 'bg-green-500' : 'bg-indigo-500'"
                  :style="{ width: `${pct}%` }"
                />
              </div>
            </div>
          </div>

          <div class="flex-1 overflow-y-auto px-3 py-3">
            <div v-if="loading" class="flex items-center justify-center py-12 text-slate-400 dark:text-slate-500 gap-2">
              <Spinner class="w-5 h-5 animate-spin" />
              <span class="text-sm">{{ t('watchlist.progress.loading') }}</span>
            </div>

            <div v-else-if="loadError" class="text-center py-12 px-4">
              <p class="text-sm text-slate-500 dark:text-slate-400">
                {{ t('watchlist.progress.noData') }}
              </p>
            </div>

            <div v-else class="flex flex-col gap-1">
              <div
                v-for="s in seasons"
                :key="s.seasonNumber"
                class="flex items-center gap-3 px-2 py-2 rounded-xl hover:bg-black/5 dark:hover:bg-white/5 transition-colors"
              >
                <button
                  @click="toggleSeason(s)"
                  :title="seasonState(s) === 'full' ? t('watchlist.progress.markUnwatched') : t('watchlist.progress.markWatched')"
                  :class="[
                    'cursor-pointer shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center transition-all duration-150 hover:scale-110',
                    seasonState(s) === 'full'
                      ? 'bg-green-500 border-green-500'
                      : seasonState(s) === 'partial'
                        ? 'border-indigo-500 bg-indigo-500/20'
                        : 'border-slate-300 dark:border-slate-600 hover:border-indigo-400',
                  ]"
                >
                  <Icon name="checkBold" v-if="seasonState(s) === 'full'" class="w-3.5 h-3.5 text-white" :sw="3" />
                  <span v-else-if="seasonState(s) === 'partial'" class="w-2 h-2 rounded-full bg-indigo-500" />
                </button>

                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-slate-800 dark:text-slate-100 truncate">{{ s.name }}</p>
                  <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.progress.episodeCount', { watched: s.watched, total: s.episodeCount }) }}</p>
                </div>

                <div class="shrink-0 flex items-center gap-1 bg-black/5 dark:bg-white/8 rounded-lg p-0.5">
                  <button
                    @click="step(s, -1)"
                    :disabled="s.watched <= 0"
                    class="cursor-pointer w-7 h-7 flex items-center justify-center rounded-md text-slate-600 dark:text-slate-300 hover:bg-white dark:hover:bg-white/10 transition-colors disabled:opacity-30 disabled:cursor-default"
                    :aria-label="t('watchlist.progress.oneFewer')"
                  >
                    <Icon name="minus" class="w-3.5 h-3.5" :sw="2.5" />
                  </button>
                  <span class="w-6 text-center text-sm tabular-nums font-medium text-slate-700 dark:text-slate-200">{{ s.watched }}</span>
                  <button
                    @click="step(s, 1)"
                    :disabled="s.watched >= s.episodeCount"
                    class="cursor-pointer w-7 h-7 flex items-center justify-center rounded-md text-slate-600 dark:text-slate-300 hover:bg-white dark:hover:bg-white/10 transition-colors disabled:opacity-30 disabled:cursor-default"
                    :aria-label="t('watchlist.progress.oneMore')"
                  >
                    <Icon name="plus" class="w-3.5 h-3.5" :sw="2.5" />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div v-if="!loading && !loadError" class="px-5 py-4 border-t border-white/30 dark:border-white/8 shrink-0 flex items-center gap-2">
            <button
              @click="allWatched ? resetAll() : markAll()"
              class="cursor-pointer text-xs font-medium text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
            >
              {{ allWatched ? t('watchlist.progress.resetAll') : t('watchlist.progress.markAll') }}
            </button>
            <button
              @click="save"
              :disabled="saving"
              class="cursor-pointer ml-auto px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-lg transition-colors disabled:opacity-60 disabled:cursor-wait"
            >
              {{ saving ? t('watchlist.progress.saving') : t('watchlist.progress.save') }}
            </button>
          </div>
    </div>
  </TemplateModal>
</template>
