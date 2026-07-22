<script setup>
import { ref, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import CollectionSelect from '@/components/CollectionSelect.vue'
import { useI18n } from '@core/useI18n.js'
import { useCollections } from '@/composables/useCollections.js'
import { updateItem } from '@/api/watchlist.js'

// Assign a single item to any number of collections. Membership is a plain field
// on the item, so saving is just updateItem(id, { collectionIds }) — no bespoke
// endpoint. New collections can be created inline via CollectionSelect.
const { t } = useI18n()
const { applyMembership } = useCollections()

const props = defineProps({
  show: { type: Boolean, default: false },
  item: { type: Object, default: null },
})
const emit = defineEmits(['close', 'updated'])

const selected = ref([])
const saving = ref(false)

watch(
  () => props.show,
  (val) => {
    if (!val) return
    selected.value = [...(props.item?.collectionIds || []).map(String)]
    saving.value = false
  },
  { immediate: true }
)

async function save() {
  if (!props.item || saving.value) return
  saving.value = true
  try {
    const prev = props.item.collectionIds || []
    const updated = await updateItem(props.item._id, { collectionIds: selected.value })
    applyMembership(prev, updated.collectionIds || selected.value)
    emit('updated', updated)
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
    fixed-height="h-[70vh]"
    :title="t('watchlist.collections.manageTitle')"
    :description="item?.title || ''"
    :confirm-label="t('watchlist.collections.save')"
    :busy="saving"
    body-class="px-5 sm:px-6 py-3"
    @cancel="$emit('close')"
    @confirm="save"
  >
    <CollectionSelect v-model="selected" list-class="max-h-[50vh] overflow-y-auto" />
  </TemplateModal>
</template>
