<script setup>
import { watch } from 'vue'
import LoadingBar from '@/components/LoadingBar.vue'
import WelcomeModal from '@/components/WelcomeModal.vue'
import NavStack from '@/components/NavStack.vue'
import ReportProblemSheet from '@/components/ReportProblemSheet.vue'
import { useReportSheet } from '@/composables/useReportSheet.js'
import { useTmdbKey, reloadTmdbKey } from '@/composables/useTmdbKey.js'
import { reloadOpenSettings } from '@/composables/useOpenSettings.js'
import { reloadCollections } from '@/composables/useCollections.js'
import { revision } from '@/storage/localDb.js'

useTmdbKey()
const { open: reportOpen, listenForShake } = useReportSheet()
listenForShake()
// A sync or an import replaced the data under the views: the pages remount
// (NavStack keys them by revision) so they fetch again; refresh the shared
// state that outlives pages.
watch(revision, () => {
  reloadCollections()
  reloadOpenSettings()
  reloadTmdbKey()
})
</script>

<template>
  <LoadingBar />
  <NavStack />
  <WelcomeModal />
  <ReportProblemSheet :show="reportOpen" @close="reportOpen = false" />
</template>
