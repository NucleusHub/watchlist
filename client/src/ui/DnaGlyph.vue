<script setup>
// MovieDNA's double helix, drawn like the iOS DNAGlyph; colour it with `color`.
const point = (t, phase) => [12 + 5.5 * Math.sin(t * 2 * Math.PI + phase), 1 + 22 * t]
const strand = (phase) =>
  Array.from({ length: 41 }, (_, i) => point(i / 40, phase))
    .map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(2)} ${y.toFixed(2)}`)
    .join(' ')
const rungs = [0.12, 0.25, 0.38, 0.62, 0.75, 0.88]
  .map((t) => `M${point(t, 0).join(' ')} L${point(t, Math.PI).join(' ')}`)
  .join(' ')
const STRANDS = `${strand(0)} ${strand(Math.PI)}`
</script>

<template>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <g transform="rotate(40 12 12)">
      <path :d="rungs" stroke-width="1.6" />
      <path :d="STRANDS" stroke-width="2" />
    </g>
  </svg>
</template>
