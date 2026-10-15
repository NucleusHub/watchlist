<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { getItems } from '@/api/watchlist.js'
import WatchlistStats from '@/components/WatchlistStats.vue'
import PageShell from '@/ui/PageShell.vue'

const { t } = useI18n()
const items = ref(null)
onMounted(async () => { items.value = await getItems().catch(() => []) })
</script>

<template>
  <PageShell :title="t('watchlist.header.statistics')">
    <WatchlistStats v-if="items" :items="items" />
  </PageShell>
</template>
