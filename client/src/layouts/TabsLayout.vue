<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import WatchlistNav from '@/components/WatchlistNav.vue'
import SettingsButton from '@/components/SettingsButton.vue'
import BottomSearch from '@/components/BottomSearch.vue'
import { getItems } from '@/api/watchlist.js'
import { useSwipeTabs } from '@/composables/useSwipeTabs.js'
import { useTabsHeader, runHeaderAction } from '@/composables/useTabsHeader.js'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const root = ref(null)
const { direction } = useSwipeTabs(root)
const { refreshing, counts } = useTabsHeader()

const total = computed(() => counts.value?.total ?? 0)
const run = (action) => runHeaderAction(action, router)

onMounted(async () => {
  if (counts.value || route.name === 'watchlist') return
  try {
    const items = await getItems()
    if (counts.value) return
    counts.value = {
      total: items.length,
      completed: items.filter((i) => i.status === 'completed').length,
      watching: items.filter((i) => i.status === 'watching').length,
    }
  } catch {}
})
</script>

<template>
  <div ref="root" class="relative min-h-screen bg-slate-100 dark:bg-[#0d0d1a] text-slate-900 dark:text-white overflow-x-hidden">
    <BackgroundBlobs />
    <div class="relative z-10">
      <div class="max-w-4xl mx-auto px-4 pt-[max(12px,env(safe-area-inset-top))] flex flex-col gap-3">
        <div class="grid grid-cols-[1fr_auto_1fr] items-center gap-2">
          <div class="flex items-center gap-2 justify-self-start">
            <button
              v-if="total > 0"
              @click="router.push('/stats')"
              :title="t('watchlist.header.statistics')"
              class="lg-glass nuc-press cursor-pointer w-10 h-10 rounded-full flex items-center justify-center text-slate-600 dark:text-white/75"
            >
              <Icon name="stats" class="relative w-[18px] h-[18px]" />
            </button>
            <button
              v-if="total > 0"
              @click="run('refresh')"
              :disabled="refreshing"
              :title="t('watchlist.header.refresh')"
              class="hidden sm:flex lg-glass nuc-press cursor-pointer w-10 h-10 rounded-full items-center justify-center text-slate-600 dark:text-white/75 disabled:opacity-40 disabled:cursor-default"
            >
              <Icon name="refresh" class="relative w-[18px] h-[18px]" />
            </button>
          </div>
          <WatchlistNav />
          <div class="justify-self-end">
            <SettingsButton glass />
          </div>
        </div>
        <p class="text-xs text-center text-slate-500 dark:text-slate-400">
          {{ counts ? t('watchlist.header.stats', counts) : '\u00a0' }}
        </p>
      </div>

      <RouterView v-slot="{ Component, route: r }">
        <Transition :name="`tab-slide-${direction}`" mode="out-in">
          <component :is="Component" :key="r.path" />
        </Transition>
      </RouterView>
      <div class="h-[calc(max(16px,env(safe-area-inset-bottom))+66px)]" aria-hidden="true" />
    </div>
    <BottomSearch />
  </div>
</template>

<style>
.tab-slide-left-enter-active,
.tab-slide-left-leave-active,
.tab-slide-right-enter-active,
.tab-slide-right-leave-active {
  transition: transform 0.16s ease-out, opacity 0.16s ease-out;
}
.tab-slide-left-leave-to,
.tab-slide-right-enter-from {
  transform: translateX(-24px);
  opacity: 0;
}
.tab-slide-left-enter-from,
.tab-slide-right-leave-to {
  transform: translateX(24px);
  opacity: 0;
}
@media (prefers-reduced-motion: reduce) {
  .tab-slide-left-enter-active,
  .tab-slide-left-leave-active,
  .tab-slide-right-enter-active,
  .tab-slide-right-leave-active {
    transition: opacity 0.12s linear;
  }
  .tab-slide-left-leave-to,
  .tab-slide-right-enter-from,
  .tab-slide-left-enter-from,
  .tab-slide-right-leave-to {
    transform: none;
  }
}
</style>
