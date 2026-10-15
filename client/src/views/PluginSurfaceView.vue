<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { itemsVersion } from '@/composables/useItemSheet.js'
import { useRoute } from 'vue-router'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { getItems } from '@/api/watchlist.js'
import { surfaceByPath } from '@/utils/pluginSurfaces.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { useWatchlistHost } from '@/composables/useWatchlistHost.js'
import HomeShell from '@/ui/HomeShell.vue'
import EmptyState from '@/ui/EmptyState.vue'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { placementOf } = useOpenSettings()
const route = useRoute()

const items = ref([])
const loading = ref(true)

const surface = computed(() => surfaceByPath(route.params.surface))
const available = computed(
  () => !!surface.value && isPluginEnabled(surface.value.pluginId) && placementOf(surface.value) === 'tab'
)

async function load() {
  // A reload after the plugin changed something mustn't unmount it.
  loading.value = !items.value.length
  try {
    items.value = await getItems()
  } catch {
    items.value = []
  } finally {
    loading.value = false
  }
}

const host = useWatchlistHost({ items: () => items.value, changed: load })

onMounted(load)
watch(itemsVersion, load)
</script>

<template>
  <HomeShell :items="items">
    <div class="max-w-4xl mx-auto">
      <div v-if="loading" class="text-center py-16 text-[var(--wl-text-2)]">{{ t('watchlist.state.loading') }}</div>
      <EmptyState v-else-if="!available" icon="puzzle" :message="t('watchlist.surface.unavailable')">
        <RouterLink to="/" class="wl-btn wl-btn-secondary mt-2">{{ t('watchlist.header.backToList') }}</RouterLink>
      </EmptyState>
      <component :is="surface.component" v-else :items="items" :host="host" placement="tab" @changed="load" />
    </div>
  </HomeShell>
</template>
