<script setup>
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useSettingsModal } from '@core/useSettingsModal.js'
import OpenSettingsModal from '@/components/OpenSettingsModal.vue'

// The header gear, paired with the modal it opens. They travel together because
// the open state is an app-wide singleton (useSettingsModal) but the modal is a
// component someone has to render — a gear on a view that doesn't also mount
// the modal is a button that does nothing. Bundling both means every top-level
// view gets working settings by dropping one component into its header.
//
// TemplateModal teleports to <body>, so this renders correctly from inside
// AppHeader's #right slot.
const { t } = useI18n()
const { open, openSettings, closeSettings } = useSettingsModal()
</script>

<template>
  <button
    @click="openSettings"
    :title="t('watchlist.header.settings')"
    class="group cursor-pointer p-2 text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
  >
    <Icon name="cog" class="w-4 h-4 nuc-cog" />
  </button>

  <OpenSettingsModal :show="open" @close="closeSettings" />
</template>
