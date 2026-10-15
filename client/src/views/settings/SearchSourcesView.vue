<script setup>
// Which sources Add searches besides TMDb (iOS SearchSourcesView).
import { computed } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { BUILTIN_SOURCES, PLUGIN_SOURCES } from '@/api/sources.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { watchlistPlugins } from '@/utils/pluginSurfaces.js'
import PageShell from '@/ui/PageShell.vue'
import WlSection from '@/ui/WlSection.vue'
import WlRow from '@/ui/WlRow.vue'
import WlToggle from '@/ui/WlToggle.vue'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { searchSources, setSearchSources } = useOpenSettings()

const sources = computed(() => [...BUILTIN_SOURCES, ...PLUGIN_SOURCES.filter((s) => isPluginEnabled(s.pluginId))])
const isOn = (id) => id === 'tmdb' || searchSources.value.includes(id)
const pluginName = (id) => watchlistPlugins.find((p) => p.id === id)?.name || id

function toggle(id, on) {
  const set = new Set(searchSources.value)
  on ? set.add(id) : set.delete(id)
  setSearchSources([...set])
}
</script>

<template>
  <PageShell :title="t('watchlist.settings.tabSources')" back="/settings">
    <WlSection :footer="t('watchlist.settings.searchSourceDesc')">
      <WlRow
        v-for="s in sources"
        :key="s.id"
        :icon="s.pluginId ? 'puzzle' : 'film'"
        :tint="s.pluginId ? 'violet' : 'teal'"
        :title="s.label"
        :subtitle="s.id === 'tmdb' ? t('watchlist.settings.alwaysOn') : s.pluginId ? t('watchlist.settings.addedByPlugin', { name: pluginName(s.pluginId) }) : ''"
      >
        <template #trailing>
          <WlToggle :model-value="isOn(s.id)" :disabled="s.id === 'tmdb'" :label="s.label" @update:model-value="toggle(s.id, $event)" />
        </template>
      </WlRow>
    </WlSection>
  </PageShell>
</template>
