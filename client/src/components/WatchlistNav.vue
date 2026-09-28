<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useWatchlistTabs } from '@/composables/useWatchlistTabs.js'
import { useSlidingPill } from '@/composables/useSlidingPill.js'
import SegmentPill from '@/components/SegmentPill.vue'

const route = useRoute()
const { tabs: TABS, isActive: isActiveFor } = useWatchlistTabs()
const isActive = (tab) => isActiveFor(tab, route)

const activeTo = computed(() => TABS.value.find(isActive)?.to)
const { container, setItem, pillStyle, animate } = useSlidingPill(activeTo)
</script>

<template>
  <nav ref="container" class="relative inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1">
    <SegmentPill :style="pillStyle" :animate="animate" />
    <RouterLink
      v-for="tab in TABS"
      :key="tab.to"
      :ref="(c) => setItem(tab.to, c)"
      :to="tab.to"
      :class="[
        'relative cursor-pointer whitespace-nowrap px-3.5 py-1.5 rounded-lg text-sm font-medium transition-colors duration-300 no-underline',
        isActive(tab)
          ? 'text-slate-900 dark:text-white'
          : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
      ]"
    >
      {{ tab.label }}
    </RouterLink>
  </nav>
</template>
