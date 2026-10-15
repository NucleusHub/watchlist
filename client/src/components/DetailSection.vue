<script setup>
import WlSection from '@/ui/WlSection.vue'

defineProps({
  title: { type: String, default: '' },
  // Rows that draw their own padding sit flush against the card edge.
  flush: { type: Boolean, default: false },
})
</script>

<template>
  <WlSection :title="title" :padded="!flush"><slot /></WlSection>
</template>
