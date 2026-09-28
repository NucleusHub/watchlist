<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import AppHeader from '@core/AppHeader.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import WatchlistNav from '@/components/WatchlistNav.vue'
import SettingsButton from '@/components/SettingsButton.vue'
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
  <div class="relative min-h-screen bg-slate-100 dark:bg-[#0d0d1a] text-slate-900 dark:text-white overflow-x-hidden">
    <BackgroundBlobs />
    <div class="relative z-10">
      <AppHeader>
        <template #right>
          <SettingsButton />
        </template>
      </AppHeader>

      <main class="max-w-4xl mx-auto px-4 py-6 flex flex-col gap-6">
        <div class="flex justify-center">
          <WatchlistNav />
        </div>

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
      </main>
    </div>
  </div>
</template>
