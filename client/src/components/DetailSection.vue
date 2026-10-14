<script setup>
defineProps({
  title: { type: String, default: '' },
  // Rows that draw their own padding sit flush against the card edge.
  flush: { type: Boolean, default: false },
})
</script>

<template>
  <section class="flex flex-col gap-2">
    <h2 v-if="title" class="px-1 text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35">{{ title }}</h2>
    <div :class="['rounded-xl bg-white/60 dark:bg-slate-800/50 border border-white/60 dark:border-white/8 overflow-hidden', flush ? 'divide-y divide-black/[0.06] dark:divide-white/8' : 'p-4']">
      <slot />
    </div>
  </section>
</template>
