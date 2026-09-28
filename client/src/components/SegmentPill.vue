<script setup>
defineProps({ animate: { type: Boolean, default: false } })
</script>

<template>
  <span
    aria-hidden="true"
    :class="[
      'absolute left-0 top-1 bottom-1 rounded-lg bg-white dark:bg-white/15 shadow-sm pointer-events-none',
      animate && 'transition-[transform,width] duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none',
    ]"
  />
</template>
