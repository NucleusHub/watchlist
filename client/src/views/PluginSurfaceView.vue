<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import AppHeader from '@core/AppHeader.vue'
import AppSidebar from '@core/AppSidebar.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import WatchlistNav from '@/components/WatchlistNav.vue'
import SettingsButton from '@/components/SettingsButton.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { getItems } from '@/api/watchlist.js'
import { surfaceByPath } from '@/utils/pluginSurfaces.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'

// Host chrome for a plugin-contributed watchlist surface shown as its own tab
// (see utils/pluginSurfaces.js). The plugin ships plain content — this view
// owns the header, sidebar, nav and item loading, so a surface component is the
// same component whether the user placed it in a tab or as a panel on the main
// list.
//
// Routed as /x/:surface; the route stays registered for every discovered
// surface, so the disabled / hidden / uninstalled cases are handled here rather
// than by rebuilding the router.
const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { placementOf } = useOpenSettings()
const route = useRoute()

const sidebarOpen = ref(false)
const items = ref([])
const loading = ref(true)

const surface = computed(() => surfaceByPath(route.params.surface))
// The tab is reachable only when the plugin is installed, enabled, and the user
// hasn't moved the surface elsewhere — but a bookmarked URL can outlive any of
// those, so check rather than mounting a component that shouldn't render.
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
        <template #left>
          <button
            @click="sidebarOpen = !sidebarOpen"
            class="cursor-pointer flex flex-col justify-center gap-[5px] p-2 rounded-lg text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            :title="t('watchlist.header.menu')"
          >
            <span class="block w-5 h-0.5 rounded-full bg-current transition-all duration-200" :class="sidebarOpen ? 'rotate-45 translate-y-[7px]' : ''" />
            <span class="block w-5 h-0.5 rounded-full bg-current transition-all duration-200" :class="sidebarOpen ? 'opacity-0 scale-x-0' : ''" />
            <span class="block w-5 h-0.5 rounded-full bg-current transition-all duration-200" :class="sidebarOpen ? '-rotate-45 -translate-y-[7px]' : ''" />
          </button>
        </template>

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

    <AppSidebar :open="sidebarOpen" @close="sidebarOpen = false" />
  </div>
</template>
