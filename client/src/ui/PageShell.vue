<script setup>
// A pushed page (NucleusPage): wallpaper, round back button with actions beside it, a large title.
import { useRouter } from 'vue-router'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import { useI18n } from '@core/useI18n.js'
import GlassCircleButton from '@/ui/GlassCircleButton.vue'
import { useScrolled } from '@/composables/useScrolled.js'

defineProps({
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  wide: { type: Boolean, default: false },
  back: { type: [String, Object], default: '/' },
})

const { t } = useI18n()
const router = useRouter()
const goBack = (fallback) => (window.history.state?.back ? router.back() : router.push(fallback))
const { scrolled, sentinel } = useScrolled()
</script>

<template>
  <div class="relative min-h-screen bg-[var(--wl-base)] text-[var(--wl-text)] overflow-x-clip">
    <div ref="sentinel" class="absolute top-0 h-px w-px" aria-hidden="true" />
    <BackgroundBlobs />
    <div :class="['relative z-10 mx-auto px-4 pt-3 pb-16', wide ? 'max-w-4xl' : 'max-w-[680px]']">
      <header class="sticky top-3 z-30 flex items-center gap-2 h-10">
        <div :class="['wl-scroll-edge !-top-3', { on: scrolled }]" aria-hidden="true" />
        <GlassCircleButton icon="chevronLeft" :title="t('watchlist.header.back')" @click="goBack(back)" />
        <div class="flex-1" />
        <slot name="actions" />
      </header>
      <div v-if="title" class="px-1 pt-4 pb-6 nuc-in">
        <h1 class="text-[34px] leading-tight font-bold tracking-[-0.02em]">{{ title }}</h1>
        <p v-if="subtitle" class="mt-1 text-[15px] text-[var(--wl-text-2)]">{{ subtitle }}</p>
      </div>
      <div v-else class="h-4" />
      <slot />
    </div>
  </div>
</template>
