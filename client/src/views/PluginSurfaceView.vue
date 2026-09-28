<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { getItems } from '@/api/watchlist.js'
import { surfaceByPath } from '@/utils/pluginSurfaces.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'

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
  loading.value = true
  try {
    items.value = await getItems()
  } catch {
    items.value = []
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 pt-6 pb-6 flex flex-col gap-6">
    <div v-if="loading" class="text-center py-16 text-slate-400 dark:text-slate-500">
      {{ t('watchlist.state.loading') }}
    </div>

    <div v-else-if="!available" class="text-center py-16 flex flex-col items-center gap-3">
      <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.surface.unavailable') }}</p>
      <RouterLink to="/" class="text-sm text-indigo-600 dark:text-indigo-400 hover:underline">
        {{ t('watchlist.header.backToList') }}
      </RouterLink>
    </div>

    <component
      v-else
      :is="surface.component"
      :items="items"
      placement="tab"
      @changed="load"
    />
  </div>
</template>
