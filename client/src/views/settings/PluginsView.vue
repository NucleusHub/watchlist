<script setup>
// The watchlist's plugins and where the sections they add appear (iOS PluginsView).
import { computed } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { watchlistSurfaces, watchlistPlugins } from '@/utils/pluginSurfaces.js'
import PageShell from '@/ui/PageShell.vue'
import WlSection from '@/ui/WlSection.vue'
import WlRow from '@/ui/WlRow.vue'
import SegmentPills from '@/ui/SegmentPills.vue'
import EmptyState from '@/ui/EmptyState.vue'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { placementOf, setPlacement } = useOpenSettings()

const surfaces = computed(() => watchlistSurfaces.filter((s) => isPluginEnabled(s.pluginId)))
const placements = (s) => [...s.placements, 'hidden'].map((key) => ({ key, label: t('watchlist.settings.placement.' + key) }))
const details = (p) => [p.version && t('watchlist.settings.version', { version: p.version }), p.author].filter(Boolean).join(' · ')
</script>

<template>
  <PageShell :title="t('watchlist.settings.plugins')" back="/settings">
    <EmptyState v-if="!watchlistPlugins.length" icon="puzzle" :title="t('watchlist.settings.noPlugins')" :message="t('watchlist.settings.noPluginsHint')" />

    <WlSection v-if="surfaces.length" :title="t('watchlist.settings.tabExtras')" :footer="t('watchlist.settings.surfaceDesc')">
      <div v-for="s in surfaces" :key="s.pluginId" class="flex flex-col gap-2.5 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
        <span class="text-[16px]">{{ t(s.label) }}</span>
        <SegmentPills :model-value="placementOf(s)" :items="placements(s)" small @update:model-value="setPlacement(s.pluginId, $event)" />
      </div>
    </WlSection>

    <WlSection v-if="watchlistPlugins.length" :title="t('watchlist.settings.installed')" :footer="t('watchlist.settings.pluginsFoot')">
      <WlRow
        v-for="p in watchlistPlugins"
        :key="p.id"
        icon="puzzle"
        :tint="isPluginEnabled(p.id) ? 'violet' : 'slate'"
        :title="p.name"
        :subtitle="details(p)"
      >
        <template #trailing>
          <span :class="['wl-tag shrink-0', isPluginEnabled(p.id) ? '!text-[var(--wl-success)]' : '']">
            {{ isPluginEnabled(p.id) ? t('watchlist.settings.on') : t('watchlist.settings.off') }}
          </span>
        </template>
      </WlRow>
    </WlSection>
  </PageShell>
</template>
