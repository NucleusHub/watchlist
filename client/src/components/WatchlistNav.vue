<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { pageRoute } from '@/utils/routes.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { Icon } from '@core/icons'
import { watchlistSurfaces, headerButtons } from '@/utils/pluginSurfaces.js'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { placementOf } = useOpenSettings()
const route = useRoute()

const pluginTabs = computed(() =>
  watchlistSurfaces
    .filter((s) => isPluginEnabled(s.pluginId) && placementOf(s) === 'tab')
    .map((s) => ({ to: `/x/${s.path}`, label: t(s.label), match: ['plugin-surface'], surface: s.path }))
)

const buttons = computed(() => headerButtons.filter((b) => isPluginEnabled(b.pluginId)))

const TABS = computed(() => [
  { to: '/', label: t('watchlist.nav.watchlist'), match: ['watchlist'] },
  { to: '/collections', label: t('watchlist.nav.collections'), match: ['collections', 'collection'] },
  ...pluginTabs.value,
])
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
    <RouterLink
      v-for="b in buttons"
      :key="`${b.pluginId}/${b.page}`"
      :to="pageRoute(b.pluginId, b.page)"
      :title="b.title"
      :aria-label="b.title"
      class="cursor-pointer px-2.5 py-1.5 rounded-lg text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
    >
      <Icon :name="b.icon" class="w-4 h-4" />
    </RouterLink>
  </nav>
</template>
