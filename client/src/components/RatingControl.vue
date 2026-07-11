<script setup>
// Star rating on a 0.5..max scale (watchlist ratings run 0.5..10). Supports half
// stars: each star has two hit zones — the left half sets n-0.5, the right half
// sets n. Interactive by default (hover preview, click to set, click the current
// value again to clear); pass :readonly for a static display. Keyboard-operable:
// each half is a focusable button (Enter/Space). Self-contained — inlines the
// star glyph so it needs no shared Icon util. Mirrors shelf's RatingControl.
import { ref, computed } from 'vue'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const STAR = 'M11.48 3.5a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5z'

const props = defineProps({
  modelValue: { type: Number, default: null },
  max: { type: Number, default: 10 },
  readonly: { type: Boolean, default: false },
  size: { type: String, default: 'md' }, // sm | md | lg
  showValue: { type: Boolean, default: true },
})
const emit = defineEmits(['update:modelValue'])

const hover = ref(0)
const clearLabel = computed(() => t('watchlist.form.clearRating'))
const shown = computed(() => hover.value || props.modelValue || 0)
const sizeClass = computed(() => ({ sm: 'w-3.5 h-3.5', md: 'w-5 h-5', lg: 'w-7 h-7' }[props.size]))

// Percentage of star n (1..max) to fill given the shown value: full, half, empty.
function fill(n) {
  const v = shown.value
  if (v >= n) return 100
  if (v >= n - 0.5) return 50
  return 0
}

function set(v) {
  if (props.readonly) return
  emit('update:modelValue', props.modelValue === v ? null : v)
}
</script>

<template>
  <div class="inline-flex items-center gap-2">
    <div class="flex items-center" :class="readonly ? '' : 'gap-0.5'" @mouseleave="hover = 0">
      <div
        v-for="n in max"
        :key="n"
        class="relative inline-flex"
        :class="[sizeClass, readonly ? '' : 'transition-transform hover:scale-110']"
      >
        <!-- Empty base -->
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
          :class="[sizeClass, 'text-slate-300 dark:text-slate-600']"
        >
          <path :d="STAR" />
        </svg>
        <!-- Filled overlay, clipped to the fill fraction -->
        <div class="absolute inset-0 overflow-hidden pointer-events-none" :style="{ width: fill(n) + '%' }">
          <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" :class="[sizeClass, 'max-w-none text-amber-400']">
            <path :d="STAR" />
          </svg>
        </div>
        <!-- Half-star hit zones (interactive only) -->
        <template v-if="!readonly">
          <button
            type="button"
            class="absolute inset-y-0 left-0 w-1/2 cursor-pointer"
            :aria-label="`${n - 0.5} / ${max}`"
            @click="set(n - 0.5)"
            @mouseenter="hover = n - 0.5"
          />
          <button
            type="button"
            class="absolute inset-y-0 right-0 w-1/2 cursor-pointer"
            :aria-label="`${n} / ${max}`"
            @click="set(n)"
            @mouseenter="hover = n"
          />
        </template>
      </div>
    </div>
    <span v-if="showValue && modelValue" class="text-sm font-medium text-slate-500 dark:text-slate-400 tabular-nums">
      {{ modelValue }}<span class="text-slate-400 dark:text-slate-600">/{{ max }}</span>
    </span>
    <button
      v-if="!readonly && modelValue"
      type="button"
      class="nuc-press cursor-pointer text-slate-400 hover:text-rose-500 dark:text-slate-500 dark:hover:text-rose-400 transition-colors"
      :aria-label="clearLabel"
      :title="clearLabel"
      @click="emit('update:modelValue', null)"
    >
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M6 18 18 6M6 6l12 12" />
      </svg>
    </button>
  </div>
</template>
