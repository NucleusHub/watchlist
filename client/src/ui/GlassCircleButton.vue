<script setup>
// The round glass header button (GlassCircleButton): a link with `to`, else a button.
import { RouterLink } from 'vue-router'
import Glyph from '@/ui/Glyph.vue'

defineProps({
  icon: { type: String, default: '' },
  to: { type: [String, Object], default: null },
  title: { type: String, default: '' },
  size: { type: Number, default: 40 },
  active: { type: Boolean, default: false },
})
</script>

<template>
  <component
    :is="to ? RouterLink : 'button'"
    v-glass.dome
    :to="to || undefined"
    :type="to ? undefined : 'button'"
    :title="title || undefined"
    :aria-label="title || undefined"
    :class="['wl-circle nuc-press cursor-pointer shrink-0 inline-grid place-items-center rounded-full no-underline transition-colors', active ? 'text-[var(--wl-accent)]' : 'text-[var(--wl-glyph)] hover:text-[var(--wl-text)]']"
    :style="{ width: `${size}px`, height: `${size}px` }"
  >
    <slot><Glyph :name="icon" :sw="2" :style="{ width: `${Math.round(size * 0.45)}px`, height: `${Math.round(size * 0.45)}px` }" /></slot>
  </component>
</template>
