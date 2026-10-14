<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AppHeader from '@core/AppHeader.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import { Icon } from '@core/icons'
import SettingsButton from '@/components/SettingsButton.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { getItems } from '@/api/watchlist.js'
import { pageOf } from '@/utils/pluginSurfaces.js'
import { useWatchlistHost } from '@/composables/useWatchlistHost.js'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const route = useRoute()
const router = useRouter()

const items = ref([])
const loading = ref(true)

const page = computed(() => pageOf(route.params.plugin, route.params.page))
const available = computed(() => !!page.value && isPluginEnabled(page.value.pluginId))

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

function goBack() {
  if (window.history.state?.back) router.back()
  else router.push('/')
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
            @click="goBack"
            :title="t('watchlist.header.backToList')"
            class="cursor-pointer p-2 rounded-lg text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
          >
            <Icon name="arrowLeft" class="w-5 h-5" />
          </button>
        </template>
        <template #right>
          <SettingsButton />
        </template>
      </AppHeader>

      <main class="max-w-2xl mx-auto px-4 py-6 flex flex-col gap-5">
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
          :is="page.component"
          :key="`${route.params.page}/${route.params.arg}`"
          :page="route.params.page"
          :arg="route.params.arg || ''"
          :host="host"
        />
      </main>
    </div>
  </div>
</template>
