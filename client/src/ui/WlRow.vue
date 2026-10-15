<script setup>
// One row of a section (NucleusRow): tile, title/subtitle, trailing slot, optional chevron or ↗.
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import IconTile from '@/ui/IconTile.vue'
import Glyph from '@/ui/Glyph.vue'

const props = defineProps({
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  icon: { type: String, default: '' },
  tint: { type: String, default: 'indigo' },
  to: { type: [String, Object], default: null },
  href: { type: String, default: '' },
  button: { type: Boolean, default: false },
  chevron: { type: Boolean, default: false },
  danger: { type: Boolean, default: false },
  accent: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
})

const tag = computed(() => (props.to ? RouterLink : props.href ? 'a' : props.button ? 'button' : 'div'))
const external = computed(() => !!props.href && /^https?:/i.test(props.href))
</script>

<template>
  <component
    :is="tag"
    :to="to || undefined"
    :href="href || undefined"
    :target="external ? '_blank' : undefined"
    :rel="external ? 'noopener noreferrer' : undefined"
    :type="button ? 'button' : undefined"
    :disabled="button ? disabled : undefined"
    class="wl-row"
  >
    <slot name="icon"><IconTile v-if="icon" :icon="icon" :tint="tint" /></slot>
    <span class="min-w-0 flex-1 flex flex-col gap-0.5">
      <span :class="['truncate', danger ? 'text-[var(--wl-danger)]' : accent ? 'text-[var(--wl-accent)] font-medium' : '']"><slot>{{ title }}</slot></span>
      <span v-if="subtitle || $slots.subtitle" class="wl-sub"><slot name="subtitle">{{ subtitle }}</slot></span>
    </span>
    <slot name="trailing" />
    <Glyph v-if="chevron" name="chevronRight" :sw="2.5" class="w-3.5 h-3.5 shrink-0 text-slate-400" />
    <Glyph v-else-if="external" name="externalLink" :sw="2" class="w-3.5 h-3.5 shrink-0 text-[var(--wl-text-2)]" />
  </component>
</template>
