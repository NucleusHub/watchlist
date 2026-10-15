<script setup>
// Glyph in a glass circle with a title and message (NucleusEmptyState).
import Glyph from '@/ui/Glyph.vue'

defineProps({
  icon: { type: String, default: 'info' },
  title: { type: String, default: '' },
  message: { type: String, default: '' },
})
</script>

<template>
  <div class="flex flex-col items-center gap-3 py-12 text-center nuc-in">
    <span v-glass.dome class="w-[68px] h-[68px] rounded-full inline-grid place-items-center text-[var(--wl-accent)]">
      <slot name="icon"><Glyph :name="icon" :sw="1.5" class="w-8 h-8" /></slot>
    </span>
    <p v-if="title" class="text-lg font-semibold text-[var(--wl-text)]">{{ title }}</p>
    <p v-if="message" class="max-w-[300px] text-sm text-[var(--wl-text-2)]">{{ message }}</p>
    <slot />
  </div>
</template>
