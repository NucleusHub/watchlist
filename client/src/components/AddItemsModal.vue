<script setup>
import { ref, watch, computed } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import ItemPicker from '@/components/ItemPicker.vue'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { addItemsToCollection } from '@/api/watchlist.js'

// Add existing watchlist items to a collection. The picker excludes current
// members; adding is one bulk request ($addToSet server-side).
const { t } = useI18n()
const { bumpCount } = useCollections()

const props = defineProps({
  show: { type: Boolean, default: false },
  collectionId: { type: String, required: true },
  // Ids already in the collection, hidden from the picker.
  memberIds: { type: Array, default: () => [] },
})
const emit = defineEmits(['close', 'added'])

const selected = ref([])
const saving = ref(false)

const exclude = computed(() => props.memberIds)

watch(
  () => props.show,
  (val) => {
    if (!val) return
    selected.value = []
    saving.value = false
  },
  { immediate: true }
)

async function save() {
  if (saving.value || !selected.value.length) return
  saving.value = true
  try {
    const { items, modified } = await addItemsToCollection(props.collectionId, selected.value)
    if (modified) bumpCount(props.collectionId, modified)
    emit('added', items)
    emit('close')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="md"
    fixed-height="h-[75vh]"
    :title="t('watchlist.collections.addItemsTitle')"
    :confirm-label="selected.length ? t('watchlist.collections.addSelected', { count: selected.length }) : t('watchlist.collections.addItems')"
    :confirm-disabled="!selected.length"
    :busy="saving"
    body-class="px-4 sm:px-5 py-3"
    @cancel="$emit('close')"
    @confirm="save"
  >
    <ItemPicker
      v-if="show"
      v-model="selected"
      :exclude="exclude"
      list-class="max-h-[55vh] overflow-y-auto"
    />
  </TemplateModal>
</template>
