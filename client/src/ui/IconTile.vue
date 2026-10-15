<script setup>
// A rounded gradient tile with a white glyph (IconTile); tints are tokens.json's.
import { computed } from 'vue'
import Glyph from '@/ui/Glyph.vue'

const TINTS = {
  indigo: ['#818CF8', '#6366F1'],
  violet: ['#A78BFA', '#8B5CF6'],
  blue: ['#60A5FA', '#3B82F6'],
  sky: ['#38BDF8', '#0EA5E9'],
  teal: ['#2DD4BF', '#14B8A6'],
  emerald: ['#34D399', '#10B981'],
  amber: ['#FBBF24', '#F59E0B'],
  orange: ['#FB923C', '#F97316'],
  rose: ['#FB7185', '#F43F5E'],
  pink: ['#F472B6', '#EC4899'],
  slate: ['#94A3B8', '#64748B'],
}

const props = defineProps({
  icon: { type: String, default: '' },
  tint: { type: String, default: 'indigo' },
  size: { type: Number, default: 30 },
})

const style = computed(() => {
  const [top, bottom] = TINTS[props.tint] ?? TINTS.indigo
  return {
    width: `${props.size}px`,
    height: `${props.size}px`,
    borderRadius: `${Math.round(props.size * 0.3)}px`,
    background: `linear-gradient(180deg, ${top}, ${bottom})`,
    boxShadow: `0 2px 6px -1px ${bottom}66`,
  }
})
const glyph = computed(() => `${Math.round(props.size * 0.56)}px`)
</script>

<template>
  <span class="wl-tile" :style="style" aria-hidden="true">
    <slot :size="glyph"><Glyph :name="icon" :sw="2" :style="{ width: glyph, height: glyph }" /></slot>
  </span>
</template>
