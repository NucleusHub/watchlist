<script setup>
// A titled glass group of rows (NucleusSection). `padded` for free content instead of rows.
defineProps({
  title: { type: String, default: '' },
  footer: { type: String, default: '' },
  padded: { type: Boolean, default: false },
})
</script>

<template>
  <section class="flex flex-col mb-7">
    <h2 v-if="title || $slots.title" class="wl-heading flex items-center justify-between gap-3">
      <slot name="title">{{ title }}</slot>
    </h2>
    <div v-glass class="wl-group" :class="padded ? 'p-4' : ''">
      <slot />
    </div>
    <p v-if="footer || $slots.footer" class="wl-foot"><slot name="footer">{{ footer }}</slot></p>
  </section>
</template>
