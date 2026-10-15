<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { getItems } from '@/api/watchlist.js'
import { pageOf, headerButtons } from '@/utils/pluginSurfaces.js'
import { useWatchlistHost } from '@/composables/useWatchlistHost.js'
import HomeShell from '@/ui/HomeShell.vue'
import PageShell from '@/ui/PageShell.vue'
import EmptyState from '@/ui/EmptyState.vue'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const route = useRoute()

const items = ref([])
const loading = ref(true)

const page = computed(() => pageOf(route.params.plugin, route.params.page))
const available = computed(() => !!page.value && isPluginEnabled(page.value.pluginId))
// A page behind a header button (News) is one of Home's tabs; other pages (a person) are pushed.
const asTab = computed(() => !route.params.arg && headerButtons.some((b) => b.pluginId === route.params.plugin && b.page === route.params.page))

async function load() {
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
</script>

<template>
  <component :is="asTab ? HomeShell : PageShell" v-bind="asTab ? { items } : {}">
    <div :class="asTab ? 'max-w-[680px] mx-auto' : ''">
      <div v-if="loading" class="text-center py-16 text-[var(--wl-text-2)]">{{ t('watchlist.state.loading') }}</div>
      <EmptyState v-else-if="!available" icon="puzzle" :message="t('watchlist.surface.unavailable')">
        <RouterLink to="/" class="wl-btn wl-btn-secondary mt-2">{{ t('watchlist.header.backToList') }}</RouterLink>
      </EmptyState>
      <component
        :is="page.component"
        v-else
        :key="`${route.params.page}/${route.params.arg}`"
        :page="route.params.page"
        :arg="route.params.arg || ''"
        :host="host"
        :as-tab="asTab"
      />
    </div>
  </component>
</template>
