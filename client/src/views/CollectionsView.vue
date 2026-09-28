<script setup>
import { ref } from 'vue'
import AppHeader from '@core/AppHeader.vue'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import TemplateModal from '@core/TemplateModal.vue'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { addItemsToCollection } from '@/api/watchlist.js'
import WatchlistNav from '@/components/WatchlistNav.vue'
import CollectionCard from '@/components/CollectionCard.vue'
import CollectionFormModal from '@/components/CollectionFormModal.vue'
import SettingsButton from '@/components/SettingsButton.vue'

const { t } = useI18n()
const { collections, loading, create, update, remove, reload } = useCollections()

const showForm = ref(false)
const editing = ref(null)

const deleting = ref(null)
const deletingBusy = ref(false)

function openCreate() {
  editing.value = null
  showForm.value = true
}
function openRename(col) {
  editing.value = col
  showForm.value = true
}
async function submitForm(data, itemIds = []) {
  if (editing.value) {
    await update(editing.value._id, data)
  } else {
    const col = await create(data)
    if (itemIds.length) {
      await addItemsToCollection(col._id, itemIds)
      await reload()
    }
  }
  showForm.value = false
}
async function confirmDelete() {
  if (!deleting.value) return
  deletingBusy.value = true
  try {
    await remove(deleting.value._id)
    deleting.value = null
  } finally {
    deletingBusy.value = false
  }
}
</script>

<template>
  <div class="relative min-h-screen bg-slate-100 dark:bg-[#0d0d1a] text-slate-900 dark:text-white overflow-x-hidden">
    <BackgroundBlobs />
    <div class="relative z-10">
      <AppHeader>
        <template #right>
          <SettingsButton />
          <button
            @click="openCreate"
            class="group nuc-press cursor-pointer flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-3 sm:px-4 py-2 rounded-lg transition-colors"
          >
            <Icon name="plus" class="w-4 h-4 nuc-pop" :sw="2.5" />
            <span class="hidden sm:inline">{{ t('watchlist.collections.new') }}</span>
          </button>
        </template>
      </AppHeader>

      <main class="max-w-4xl mx-auto px-4 py-6 flex flex-col gap-6">
        <div class="flex justify-center">
          <WatchlistNav />
        </div>

        <div v-if="loading && !collections.length" class="text-center py-16 text-slate-400 dark:text-slate-500">
          {{ t('watchlist.state.loading') }}
        </div>

        <div v-else-if="!collections.length" class="text-center py-16 flex flex-col items-center gap-4">
          <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-indigo-500/20 to-purple-500/10 dark:from-indigo-500/25 dark:to-purple-500/10 text-indigo-600 dark:text-indigo-300 flex items-center justify-center ring-1 ring-inset ring-white/50 dark:ring-white/10">
            <Icon name="folder" class="w-8 h-8" :sw="1.5" />
          </div>
          <div>
            <p class="text-sm font-medium text-slate-700 dark:text-slate-200">{{ t('watchlist.collections.emptyTitle') }}</p>
            <p class="mt-1 text-sm text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.emptyHint') }}</p>
          </div>
          <button
            @click="openCreate"
            class="nuc-press cursor-pointer inline-flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors"
          >
            <Icon name="plus" class="w-4 h-4" :sw="2.5" />
            {{ t('watchlist.collections.new') }}
          </button>
        </div>

        <template v-else>
          <div class="flex items-end justify-between gap-3">
            <div>
              <h1 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-white">{{ t('watchlist.nav.collections') }}</h1>
              <p class="mt-0.5 text-sm text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.countLabel', { count: collections.length }) }}</p>
            </div>
          </div>

          <div class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 nuc-stagger" style="--nuc-step: 32ms">
          <CollectionCard
            v-for="col in collections"
            :key="col._id"
            :collection="col"
            @rename="openRename"
            @delete="deleting = $event"
          />
          <button
            @click="openCreate"
            class="group cursor-pointer min-h-[180px] rounded-2xl border-2 border-dashed border-slate-300/80 dark:border-white/10 hover:border-indigo-500 hover:bg-indigo-500/[0.03] dark:hover:bg-indigo-500/10 text-slate-400 dark:text-slate-500 hover:text-indigo-500 dark:hover:text-indigo-300 transition-all flex flex-col items-center justify-center gap-2"
          >
            <span class="w-11 h-11 rounded-xl bg-black/[0.04] dark:bg-white/5 group-hover:bg-indigo-500/15 flex items-center justify-center transition-colors">
              <Icon name="plus" class="w-6 h-6" :sw="1.75" />
            </span>
            <span class="text-sm font-medium">{{ t('watchlist.collections.new') }}</span>
          </button>
          </div>
        </template>
      </main>

      <CollectionFormModal
        :show="showForm"
        :initial="editing"
        @close="showForm = false"
        @submit="submitForm"
      />

      <TemplateModal
        :show="!!deleting"
        :title="t('watchlist.collections.deleteTitle')"
        :message="t('watchlist.collections.deleteMessage', { name: deleting?.name })"
        :confirm-label="t('watchlist.collections.delete')"
        :busy="deletingBusy"
        @confirm="confirmDelete"
        @cancel="deleting = null"
      />
    </div>
  </div>
</template>
