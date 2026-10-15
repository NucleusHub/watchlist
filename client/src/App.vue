<script setup>
import { onMounted } from 'vue'
import { useRoute } from 'vue-router'
import ItemSheet from '@/components/ItemSheet.vue'
import AuthGuard from '@core/auth/AuthGuard.vue'
import TrailerModal from '@/components/TrailerModal.vue'
import TourModal from '@/components/TourModal.vue'
import { playing } from '@/composables/useTrailerPlayer.js'
import { loadAccent } from '@/utils/accent.js'
import { applyAccent } from '@/utils/applyAccent.js'

const route = useRoute()
onMounted(() => applyAccent(loadAccent()))
</script>

<template>
  <AuthGuard>
    <RouterView />
    <ItemSheet v-if="route.query.item" :id="String(route.query.item)" :key="String(route.query.item)" />
    <TrailerModal :video="playing" @close="playing = null" />
    <TourModal />
  </AuthGuard>
</template>
