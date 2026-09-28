<script setup>
import { useRouter } from 'vue-router'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'

defineProps({ glass: { type: Boolean, default: false } })

const { t } = useI18n()
const router = useRouter()
</script>

<template>
  <button
    @click="router.push('/settings')"
    :title="t('watchlist.header.settings')"
    :class="glass
      ? 'group lg-glass nuc-press cursor-pointer w-10 h-10 rounded-full flex items-center justify-center text-slate-600 dark:text-white/75'
      : 'group cursor-pointer p-2 text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors'"
  >
    <Icon name="cog" :class="['nuc-cog', glass ? 'relative w-[18px] h-[18px]' : 'w-4 h-4']" />
  </button>
</template>
