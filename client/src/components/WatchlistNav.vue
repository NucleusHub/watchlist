<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from '@core/useI18n.js'

// In-app nav between the full watchlist and the Collections section. Lives in the
// AppHeader center slot on both top-level views. A segmented pill matches the
// status/type controls already used across the app rather than inventing a new
// look. Active state follows the route name (the collection detail route counts
// as "collections") so prefix matching can't light up both tabs.
const { t } = useI18n()
const route = useRoute()

const TABS = computed(() => [
  { to: '/', label: t('watchlist.nav.watchlist'), match: ['watchlist'] },
  { to: '/collections', label: t('watchlist.nav.collections'), match: ['collections', 'collection'] },
])
const isActive = (tab) => tab.match.includes(route.name)
</script>

<template>
  <nav class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1">
    <RouterLink
      v-for="tab in TABS"
      :key="tab.to"
      :to="tab.to"
      :class="[
        'cursor-pointer whitespace-nowrap px-3.5 py-1.5 rounded-lg text-sm font-medium transition-all no-underline',
        isActive(tab)
          ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm'
          : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
      ]"
    >
      {{ tab.label }}
    </RouterLink>
  </nav>
</template>
