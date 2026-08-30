<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { watchlistSurfaces } from '@/utils/pluginSurfaces.js'

// In-app nav between the full watchlist and the Collections section. Lives in the
// AppHeader center slot on both top-level views. A segmented pill matches the
// status/type controls already used across the app rather than inventing a new
// look. Active state follows the route name (the collection detail route counts
// as "collections") so prefix matching can't light up both tabs.
//
// Plugins can add tabs of their own: an enabled plugin whose watchlist surface
// the user has placed as a tab appends one here, after the built-in two.
const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { placementOf } = useOpenSettings()
const route = useRoute()

// A surface's manifest label may be an i18n key or a literal — t() returns the
// key unchanged when there's no catalog entry, so both work.
const pluginTabs = computed(() =>
  watchlistSurfaces
    .filter((s) => isPluginEnabled(s.pluginId) && placementOf(s) === 'tab')
    .map((s) => ({ to: `/x/${s.path}`, label: t(s.label), match: ['plugin-surface'], surface: s.path }))
)

const TABS = computed(() => [
  { to: '/', label: t('watchlist.nav.watchlist'), match: ['watchlist'] },
  { to: '/collections', label: t('watchlist.nav.collections'), match: ['collections', 'collection'] },
  ...pluginTabs.value,
])
// Plugin tabs share one route name, so they additionally match on the segment —
// otherwise two plugin tabs would both light up.
const isActive = (tab) =>
  tab.match.includes(route.name) && (!tab.surface || route.params.surface === tab.surface)
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
