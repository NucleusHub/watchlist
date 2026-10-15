<script setup>
import { ref } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { addItemsToCollection } from '@/api/watchlist.js'
import CollectionCard from '@/components/CollectionCard.vue'
import CollectionFormModal from '@/components/CollectionFormModal.vue'
import HomeShell from '@/ui/HomeShell.vue'
import EmptyState from '@/ui/EmptyState.vue'
import Glyph from '@/ui/Glyph.vue'

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
  <HomeShell addable :search-prompt="t('watchlist.search.promptCollections')" @add="openCreate">
    <div v-if="loading && !collections.length" class="text-center py-16 text-[var(--wl-text-2)]">{{ t('watchlist.state.loading') }}</div>

    <EmptyState v-else-if="!collections.length" icon="folder" :title="t('watchlist.collections.emptyTitle')" :message="t('watchlist.collections.emptyHint')" class="pt-16">
      <button type="button" class="wl-btn wl-btn-primary mt-3 w-full max-w-[280px]" @click="openCreate">{{ t('watchlist.collections.new') }}</button>
    </EmptyState>

    <div v-else class="grid gap-[18px] grid-cols-1 md:grid-cols-2 lg:grid-cols-3 nuc-stagger" style="--nuc-step: 40ms">
      <CollectionCard v-for="col in collections" :key="col._id" :collection="col" @rename="openRename" @delete="deleting = $event" />
      <button
        type="button"
        class="nuc-press cursor-pointer min-h-16 rounded-[26px] border-[1.5px] border-dashed border-[color-mix(in_oklab,var(--wl-accent)_40%,transparent)] text-[var(--wl-accent)] text-[15px] font-semibold inline-flex items-center justify-center gap-2 hover:bg-[color-mix(in_oklab,var(--wl-accent)_6%,transparent)] transition-colors"
        @click="openCreate"
      >
        <Glyph name="plus" :sw="2.5" class="w-4 h-4" />
        {{ t('watchlist.collections.new') }}
      </button>
    </div>
  </HomeShell>

  <CollectionFormModal :show="showForm" :initial="editing" @close="showForm = false" @submit="submitForm" />
  <TemplateModal
    :show="!!deleting"
    :title="t('watchlist.collections.deleteTitle')"
    :message="t('watchlist.collections.deleteMessage', { name: deleting?.name })"
    :confirm-label="t('watchlist.collections.delete')"
    :busy="deletingBusy"
    @confirm="confirmDelete"
    @cancel="deleting = null"
  />
</template>
