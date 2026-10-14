<script setup>
import { onMounted } from 'vue'
import AuthGuard from '@core/auth/AuthGuard.vue'
import TrailerModal from '@/components/TrailerModal.vue'
import TourModal from '@/components/TourModal.vue'
import { playing } from '@/composables/useTrailerPlayer.js'
import { applyAccent, loadAccent } from '@/utils/accent.js'

onMounted(() => applyAccent(loadAccent()))
</script>

<template>
  <AuthGuard>
    <RouterView />
    <TrailerModal :video="playing" @close="playing = null" />
    <TourModal />
  </AuthGuard>
</template>
