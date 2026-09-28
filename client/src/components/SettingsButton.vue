<script setup>
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useSettingsModal } from '@core/useSettingsModal.js'
import OpenSettingsModal from '@/components/OpenSettingsModal.vue'

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
