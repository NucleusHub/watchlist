<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { tourOpen, closeTour, showTourOnce } from '@/composables/useTour.js'
import IconTile from '@/ui/IconTile.vue'

const { t } = useI18n()
onMounted(showTourOnce)

const STEPS = [
  { key: 'add', tint: 'indigo', icon: 'M12 9v6m3-3H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z' },
  { key: 'pages', tint: 'violet', icon: 'M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z' },
  { key: 'mark', tint: 'emerald', icon: 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z' },
  { key: 'progress', tint: 'sky', icon: 'M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z' },
  { key: 'collections', tint: 'amber', icon: 'M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z' },
  { key: 'discover', tint: 'rose', icon: 'M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456z' },
  { key: 'stats', tint: 'orange', icon: 'M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z' },
  { key: 'sync', tint: 'teal', icon: 'M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99' },
]

const page = ref(0)
watch(tourOpen, (open) => { if (open) page.value = 0 })
const step = computed(() => STEPS[page.value])
const last = computed(() => page.value === STEPS.length - 1)
const next = () => (last.value ? closeTour() : page.value++)
</script>

<template>
  <TemplateModal :show="tourOpen" footer size="sm" z="z-[220]" body-class="px-6 pt-8 pb-6" @cancel="closeTour">
    <div class="flex flex-col items-center gap-5 text-center">
      <IconTile :key="step.key" :tint="step.tint" :size="80" class="nuc-in-scale">
        <template #default="{ size }">
          <svg :style="{ width: size, height: size }" fill="none" stroke="currentColor" stroke-width="1.6" viewBox="0 0 24 24" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" :d="step.icon" />
          </svg>
        </template>
      </IconTile>
      <div class="flex flex-col gap-2">
        <h2 class="text-[22px] font-bold tracking-tight text-[var(--wl-text)]">{{ t(`watchlist.tour.${step.key}.title`) }}</h2>
        <p class="text-[15px] leading-relaxed text-[var(--wl-text-2)]">{{ t(`watchlist.tour.${step.key}.message`) }}</p>
      </div>
    </div>
    <template #footer>
      <div class="flex items-center w-full gap-3">
        <button
          type="button"
          :class="['cursor-pointer px-2 py-2 text-[15px] font-medium text-[var(--wl-text-2)] hover:text-[var(--wl-text)] transition-colors', last && 'invisible']"
          @click="closeTour"
        >{{ t('watchlist.tour.skip') }}</button>
        <div class="flex flex-1 justify-center gap-1.5" aria-hidden="true">
          <span
            v-for="(s, i) in STEPS"
            :key="s.key"
            :class="['h-1.5 rounded-full transition-all', i === page ? 'w-5 bg-[var(--wl-accent)]' : 'w-1.5 bg-[var(--wl-sep)]']"
          />
        </div>
        <button
          type="button"
          class="wl-btn wl-btn-primary"
          @click="next"
        >{{ last ? t('watchlist.tour.done') : t('watchlist.tour.next') }}</button>
      </div>
    </template>
  </TemplateModal>
</template>
