<script setup>
import { useRouter } from 'vue-router'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import { useI18n } from '@core/useI18n.js'

const props = defineProps({
  title: { type: String, default: '' },
  wide: { type: Boolean, default: false },
  fallback: { type: String, default: '/' },
})

const { t } = useI18n()
const router = useRouter()

function back() {
  if (window.history.state?.back) router.back()
  else router.push(props.fallback)
}
</script>

<template>
  <div
    class="relative min-h-screen bg-slate-100 dark:bg-[#0d0d1a] text-slate-900 dark:text-white overflow-x-hidden"
  >
    <BackgroundBlobs />
    <div :class="['relative z-10 mx-auto px-4', wide ? 'max-w-4xl' : 'max-w-2xl']" class="pt-[max(12px,env(safe-area-inset-top))] pb-[max(24px,env(safe-area-inset-bottom))]">
      <div class="flex items-center justify-between gap-2 h-10">
        <button
          type="button"
          :aria-label="t('watchlist.header.backToList')"
          class="lg-glass nuc-press cursor-pointer w-10 h-10 rounded-full flex items-center justify-center text-slate-700 dark:text-white/80"
          @click="back"
        >
          <svg class="relative w-5 h-5" fill="none" stroke="currentColor" stroke-width="2.25" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
        </button>
        <div class="flex items-center gap-2">
          <slot name="actions" />
        </div>
      </div>

      <h1 v-if="title" class="mt-4 mb-6 px-1 text-[34px] leading-tight font-bold tracking-tight break-words">{{ title }}</h1>

      <slot />
    </div>
  </div>
</template>
