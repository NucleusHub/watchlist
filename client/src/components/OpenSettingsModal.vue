<script setup>
import { reactive, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { OPEN_OPTIONS, TITLE_FORMATS, buildOpenUrl } from '@/utils/openTarget.js'

const { t } = useI18n()
const props = defineProps({ show: { type: Boolean, default: false } })
const emit = defineEmits(['close'])

const { defaults, setDefault } = useOpenSettings()

const KINDS = [
  { key: 'movie', label: 'watchlist.open.movies' },
  { key: 'show', label: 'watchlist.open.shows' },
]

// Icons keep the two sections distinct and the destination chips scannable.
const KIND_ICON = {
  movie: 'M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h1.5C5.496 19.5 6 18.996 6 18.375m-3.75.125-.375-12a1.125 1.125 0 011.125-1.125h15.75A1.125 1.125 0 0120.625 6.5l-.375 12M6 18.375V7.875C6 7.254 6.504 6.75 7.125 6.75h9.75C17.496 6.75 18 7.254 18 7.875v10.5m0 0c0 .621-.504 1.125-1.125 1.125H7.125',
  show: 'M6 20.25h12m-7.5-3v3m3-3v3M3.75 6.75h16.5a1.5 1.5 0 011.5 1.5v7.5a1.5 1.5 0 01-1.5 1.5H3.75a1.5 1.5 0 01-1.5-1.5v-7.5a1.5 1.5 0 011.5-1.5z',
}
const DEST_ICON = {
  tmdb: 'M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75',
  csfd: 'M11.48 3.499a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.563.563 0 00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.562.562 0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z',
  google: 'M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z',
  custom: 'M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244',
}

// Edit a local draft so a Cancel/close leaves the saved defaults untouched.
const blank = () => ({ type: 'tmdb', customUrl: '', titleFormat: 'raw' })
const draft = reactive({ movie: blank(), show: blank() })

watch(
  () => props.show,
  (v) => {
    if (!v) return
    for (const { key } of KINDS) {
      draft[key] = { type: defaults[key].type, customUrl: defaults[key].customUrl || '', titleFormat: defaults[key].titleFormat || 'raw' }
    }
  },
  { immediate: true }
)

// Live preview of what a click will open, using a familiar sample title.
const SAMPLE = { title: 'The Matrix', year: 1999 }
const previewUrl = (kind) => buildOpenUrl(draft[kind], SAMPLE)

function save() {
  for (const { key } of KINDS) setDefault(key, draft[key])
  emit('close')
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    :title="t('watchlist.open.settingsTitle')"
    :confirm-label="t('watchlist.open.save')"
    :cancel-label="t('watchlist.open.cancel')"
    size="lg"
    body-class="px-5 pb-5 pt-5"
    @confirm="save"
    @cancel="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.open.settingsDesc') }}</p>

      <div
        v-for="kind in KINDS"
        :key="kind.key"
        class="flex flex-col gap-3 rounded-xl border border-black/5 dark:border-white/10 bg-white/40 dark:bg-white/[0.03] p-4"
      >
        <!-- Section header -->
        <div class="flex items-center gap-2.5">
          <span class="grid place-items-center w-8 h-8 rounded-lg bg-indigo-600/10 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-400 shrink-0">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" :d="KIND_ICON[kind.key]" />
            </svg>
          </span>
          <span class="text-sm font-semibold text-slate-900 dark:text-white">{{ t(kind.label) }}</span>
        </div>

        <!-- Destination chips -->
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="opt in OPEN_OPTIONS"
            :key="opt.type"
            type="button"
            @click="draft[kind.key].type = opt.type"
            :class="[
              'cursor-pointer inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-all border',
              draft[kind.key].type === opt.type
                ? 'bg-indigo-600 text-white border-transparent shadow-sm shadow-indigo-600/30'
                : 'bg-white/60 dark:bg-white/8 text-slate-600 dark:text-slate-300 border-black/5 dark:border-white/10 hover:bg-white dark:hover:bg-white/15 hover:text-slate-900 dark:hover:text-white',
            ]"
          >
            <svg class="w-3.5 h-3.5 shrink-0" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" :d="DEST_ICON[opt.type]" />
            </svg>
            {{ t(opt.i18n) }}
          </button>
        </div>

        <!-- Custom URL config — nested panel so it reads as part of the section -->
        <div
          v-if="draft[kind.key].type === 'custom'"
          class="flex flex-col gap-2.5 rounded-lg bg-black/[0.03] dark:bg-black/20 border border-black/5 dark:border-white/10 p-3"
        >
          <input
            v-model="draft[kind.key].customUrl"
            type="url"
            :placeholder="t('watchlist.open.customPlaceholder')"
            class="bg-white dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
          <div class="flex items-center gap-2">
            <label class="text-xs text-slate-500 dark:text-slate-400 shrink-0">{{ t('watchlist.open.titleFormat') }}</label>
            <select v-model="draft[kind.key].titleFormat" class="cursor-pointer flex-1 bg-white dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500">
              <option v-for="fmt in TITLE_FORMATS" :key="fmt.value" :value="fmt.value">{{ t(fmt.i18n) }} — {{ fmt.example }}</option>
            </select>
          </div>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.open.customHint') }}</p>
          <p v-if="previewUrl(kind.key)" class="text-xs text-slate-500 dark:text-slate-400 truncate">
            <span class="text-slate-400 dark:text-slate-500">{{ t('watchlist.open.preview') }}</span>
            <span class="font-mono text-indigo-600 dark:text-indigo-400">{{ previewUrl(kind.key) }}</span>
          </p>
        </div>
      </div>
    </div>
  </TemplateModal>
</template>
