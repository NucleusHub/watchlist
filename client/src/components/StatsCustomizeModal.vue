<script setup>
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { moveEntry } from '@/utils/statsLayout.js'

const { t } = useI18n()
defineProps({ show: { type: Boolean, default: false }, entries: { type: Array, required: true } })
const emit = defineEmits(['update', 'reset', 'close'])

const patch = (entries, i, change) => entries.map((e, n) => (n === i ? { ...e, ...change } : e))
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="md"
    z="z-[210]"
    :title="t('watchlist.stats.customize')"
    :confirm-label="t('watchlist.stats.doneAction')"
    hide-cancel
    body-class="px-5 pb-5 pt-5"
    @confirm="emit('close')"
    @cancel="emit('close')"
  >
    <p class="text-sm text-slate-500 dark:text-slate-400 mb-3">{{ t('watchlist.stats.customizeHint') }}</p>
    <ul class="flex flex-col gap-1.5">
      <li
        v-for="(entry, i) in entries"
        :key="entry.card"
        class="flex items-center gap-2 rounded-lg bg-white/60 dark:bg-white/[0.04] border border-black/5 dark:border-white/10 px-2.5 py-2"
      >
        <button
          type="button"
          :title="entry.visible ? t('watchlist.stats.hideCard') : t('watchlist.stats.showCard')"
          :aria-pressed="entry.visible"
          class="cursor-pointer p-1.5 rounded-md text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
          :class="entry.visible && 'text-indigo-600 dark:text-indigo-400'"
          @click="emit('update', patch(entries, i, { visible: !entry.visible }))"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
            <template v-if="entry.visible"><path stroke-linecap="round" stroke-linejoin="round" d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z" /><path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></template>
            <path v-else stroke-linecap="round" stroke-linejoin="round" d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88" />
          </svg>
        </button>
        <span :class="['flex-1 min-w-0 truncate text-sm', entry.visible ? 'text-slate-800 dark:text-slate-100' : 'text-slate-400 dark:text-slate-500']">
          {{ t(`watchlist.stats.card.${entry.card}`) }}
        </span>
        <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-lg p-0.5">
          <button
            v-for="size in ['small', 'large']"
            :key="size"
            type="button"
            :disabled="!entry.visible"
            :title="t(`watchlist.stats.size.${size}`)"
            :class="[
              'cursor-pointer px-2 py-0.5 rounded-md text-xs font-medium transition-all disabled:opacity-40 disabled:cursor-default',
              entry.size === size ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-slate-400',
            ]"
            @click="emit('update', patch(entries, i, { size }))"
          >{{ size === 'small' ? 'S' : 'L' }}</button>
        </div>
        <div class="flex">
          <button
            type="button"
            :disabled="i === 0"
            :title="t('watchlist.stats.moveUp')"
            class="cursor-pointer p-1.5 rounded-md text-slate-400 hover:text-slate-900 dark:hover:text-white disabled:opacity-30 disabled:cursor-default"
            @click="emit('update', moveEntry(entries, i, i - 1))"
          ><svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 15.75l7.5-7.5 7.5 7.5" /></svg></button>
          <button
            type="button"
            :disabled="i === entries.length - 1"
            :title="t('watchlist.stats.moveDown')"
            class="cursor-pointer p-1.5 rounded-md text-slate-400 hover:text-slate-900 dark:hover:text-white disabled:opacity-30 disabled:cursor-default"
            @click="emit('update', moveEntry(entries, i, i + 1))"
          ><svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" /></svg></button>
        </div>
      </li>
    </ul>
    <template #footer-start>
      <button type="button" class="cursor-pointer text-sm font-medium text-indigo-600 dark:text-indigo-400 hover:underline" @click="emit('reset')">{{ t('watchlist.stats.reset') }}</button>
    </template>
  </TemplateModal>
</template>
