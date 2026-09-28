<script setup>
import { computed } from 'vue'
import ChoiceModal from '@/components/ChoiceModal.vue'
import { useI18n } from '@core/useI18n.js'

const props = defineProps({
  backup: { type: Object, default: null }, // from storage/backup.js readBackup()
})
const emit = defineEmits(['apply', 'close'])
const { t, locale } = useI18n()

const message = computed(() => {
  const b = props.backup
  if (!b) return ''
  const summary = t('watchlist.data.importSummary', { items: b.items, collections: b.collections })
  if (!b.exportedAt) return summary
  const date = new Date(b.exportedAt).toLocaleDateString(locale.value || undefined, { dateStyle: 'medium' })
  return `${summary} ${t('watchlist.data.importExportedAt', { date })}`
})

const options = computed(() => [
  { key: 'merge', icon: 'merge', tone: 'indigo', recommended: true, label: t('watchlist.data.importMerge'), desc: t('watchlist.data.importMergeDesc') },
  { key: 'replace', icon: 'replace', tone: 'red', label: t('watchlist.data.importReplace'), desc: t('watchlist.data.importReplaceDesc') },
])
</script>

<template>
  <ChoiceModal
    :show="!!backup"
    :title="t('watchlist.data.importTitle')"
    :message="message"
    :options="options"
    @choose="emit('apply', $event)"
    @close="emit('close')"
  />
</template>
