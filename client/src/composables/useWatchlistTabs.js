import { computed } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { watchlistSurfaces } from '@/utils/pluginSurfaces.js'

export function useWatchlistTabs() {
  const { t } = useI18n()
  const { isPluginEnabled } = useRegistry()
  const { placementOf } = useOpenSettings()

  const pluginTabs = computed(() =>
    watchlistSurfaces
      .filter((s) => isPluginEnabled(s.pluginId) && placementOf(s) === 'tab')
      .map((s) => ({ to: `/x/${s.path}`, label: t(s.label), match: ['plugin-surface'], surface: s.path }))
  )

  const tabs = computed(() => [
    { to: '/', label: t('watchlist.nav.watchlist'), match: ['watchlist'] },
    { to: '/collections', label: t('watchlist.nav.collections'), match: ['collections', 'collection'] },
    ...pluginTabs.value,
  ])

  const isActive = (tab, route) =>
    tab.match.includes(route.name) && (!tab.surface || route.params.surface === tab.surface)

  const indexOf = (route) => tabs.value.findIndex((tab) => isActive(tab, route))

  return { tabs, isActive, indexOf }
}
