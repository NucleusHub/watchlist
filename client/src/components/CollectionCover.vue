<script setup>
import { computed } from 'vue'
import { Icon } from '@core/icons'

// A collection's cover art. Priority: an uploaded/URL image, else the chosen
// (or auto) posters rendered as a diagonal "slash" collage, else a gradient
// placeholder. Fills its (relatively-positioned) parent.
const props = defineProps({
  image: { type: String, default: null },
  posters: { type: Array, default: () => [] },
})

const shown = computed(() => (props.posters || []).filter(Boolean).slice(0, 8))

// Diagonal slices: each poster gets a skewed vertical band, with a small gap
// along the seam so the "slash" reads as a clean cut.
const SKEW = 9
const GAP = 0.9
function clip(i, n) {
  if (n <= 1) return undefined
  const b = (k) => (k / n) * 100
  const tl = i > 0 ? b(i) + SKEW + GAP : 0
  const bl = i > 0 ? b(i) - SKEW + GAP : 0
  const tr = i + 1 < n ? b(i + 1) + SKEW - GAP : 100
  const br = i + 1 < n ? b(i + 1) - SKEW - GAP : 100
  return `polygon(${tl}% 0, ${tr}% 0, ${br}% 100%, ${bl}% 100%)`
}

// Position each poster's box over its own band so object-cover centers the
// poster on that band (not on the whole cover). The box is widened by SKEW on
// each side to cover the diagonal corners; its centre stays at the band centre.
function band(i, n) {
  if (n <= 1) return { left: '0%', width: '100%' }
  const left = (i / n) * 100 - SKEW
  const width = 100 / n + 2 * SKEW
  return { left: `${left}%`, width: `${width}%` }
}
</script>

<template>
  <div class="absolute inset-0 bg-slate-300/60 dark:bg-slate-900/60">
    <img v-if="image" :src="image" alt="" class="absolute inset-0 w-full h-full object-cover" />

    <template v-else-if="shown.length">
      <!-- Each poster lives in a clip-path band; its box is positioned over that
           band so object-cover centres the poster on its own slice. -->
      <div
        v-for="(p, i) in shown"
        :key="i"
        class="absolute inset-0"
        :style="{ clipPath: clip(i, shown.length), WebkitClipPath: clip(i, shown.length) }"
      >
        <img :src="p" alt="" class="absolute inset-y-0 h-full object-cover" :style="band(i, shown.length)" />
      </div>
    </template>

    <div
      v-else
      class="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-indigo-500/20 via-purple-500/10 to-transparent dark:from-indigo-500/25 dark:via-purple-500/10"
    >
      <Icon name="folder" class="w-10 h-10 text-indigo-400/70 dark:text-indigo-300/60" :sw="1.5" />
    </div>
  </div>
</template>
