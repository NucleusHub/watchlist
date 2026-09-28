<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { getItems } from '@/api/watchlist.js'
import PageShell from '@/layouts/PageShell.vue'
import WatchlistStats from '@/components/WatchlistStats.vue'

const { t } = useI18n()
const items = ref([])
const loading = ref(true)

onMounted(async () => {
  try {
    items.value = await getItems()
  } catch {
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <PageShell :title="t('watchlist.header.statistics')">
    <p v-if="loading" class="py-16 text-center text-sm text-slate-500 dark:text-white/55">{{ t('watchlist.state.loading') }}</p>
    <WatchlistStats v-else :items="items" />
  </PageShell>
</template>
