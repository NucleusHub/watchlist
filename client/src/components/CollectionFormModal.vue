<script setup>
import { ref, watch, nextTick, computed } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import ItemPicker from '@/components/ItemPicker.vue'
import CollectionCover from '@/components/CollectionCover.vue'
import ArchiveBoxIcon from '@/assets/icons/archive-box.svg?component'
import { Icon, Spinner } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { uploadImage, getItems } from '@/api/watchlist.js'

const { t } = useI18n()

const props = defineProps({
  show: { type: Boolean, default: false },
  initial: { type: Object, default: null },
})
const emit = defineEmits(['close', 'submit'])

const name = ref('')
const description = ref('')
const itemIds = ref([])
const busy = ref(false)
const nameInput = ref(null)

const coverMode = ref('auto')
const coverUrl = ref('')
const coverItemIds = ref([])
const coverCount = ref(4)
const uploading = ref(false)
const fileInput = ref(null)

const memberItems = ref([])

const canSave = computed(() => name.value.trim().length > 0)

const COVER_TABS = computed(() => [
  { key: 'auto', label: t('watchlist.collections.coverAuto') },
  { key: 'image', label: t('watchlist.collections.coverUpload') },
  { key: 'titles', label: t('watchlist.collections.coverTitles') },
])

const memberPosters = computed(() => new Map(memberItems.value.map((i) => [String(i._id), i.posterUrl])))
const coverSelected = (id) => coverItemIds.value.map(String).includes(String(id))
function toggleCover(id) {
  const key = String(id)
  coverItemIds.value = coverSelected(key) ? coverItemIds.value.filter((x) => String(x) !== key) : [...coverItemIds.value, key]
}

const previewPosters = computed(() => {
  if (coverMode.value === 'titles') return coverItemIds.value.map((id) => memberPosters.value.get(String(id))).filter(Boolean)
  if (coverMode.value === 'auto') return memberItems.value.map((i) => i.posterUrl).filter(Boolean).slice(0, coverCount.value)
  return []
})

watch(
  () => props.show,
  async (val) => {
    if (!val) return
    name.value = props.initial?.name || ''
    description.value = props.initial?.description || ''
    itemIds.value = []
    coverUrl.value = props.initial?.coverUrl || ''
    coverItemIds.value = (props.initial?.coverItemIds || []).map(String)
    coverCount.value = props.initial?.coverCount || 4
    coverMode.value = props.initial?.coverUrl ? 'image' : props.initial?.coverItemIds?.length ? 'titles' : 'auto'
    memberItems.value = []
    busy.value = false
    uploading.value = false
    nextTick(() => nameInput.value?.focus())
    if (props.initial?._id) {
      try {
        memberItems.value = await getItems({ collection: props.initial._id })
      } catch {
        memberItems.value = []
      }
    }
  },
  { immediate: true }
)

async function handleUpload(e) {
  const file = e.target.files?.[0]
  if (!file) return
  uploading.value = true
  try {
    coverUrl.value = await uploadImage(file)
  } catch {
  } finally {
    uploading.value = false
    e.target.value = ''
  }
}

async function submit() {
  if (!canSave.value || busy.value) return
  busy.value = true
  try {
    const memberIdSet = new Set(memberItems.value.map((i) => String(i._id)))
    const data = {
      name: name.value.trim(),
      description: description.value.trim(),
      coverUrl: coverMode.value === 'image' ? coverUrl.value || null : null,
      coverItemIds: coverMode.value === 'titles' ? coverItemIds.value.filter((id) => memberIdSet.has(String(id))) : [],
      coverCount: coverCount.value,
    }
    await emit('submit', data, itemIds.value)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="lg"
    fixed-height="h-[600px]"
    :title="initial ? t('watchlist.collections.editTitle') : t('watchlist.collections.newTitle')"
    :confirm-label="initial ? t('watchlist.collections.save') : t('watchlist.collections.create')"
    :confirm-disabled="!canSave"
    :busy="busy"
    @cancel="$emit('close')"
    @confirm="submit"
  >
    <form class="flex flex-col gap-4 pt-1" @submit.prevent="submit">
      <div class="flex flex-col gap-1.5">
        <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.collections.name') }}</label>
        <input
          ref="nameInput"
          v-model="name"
          type="text"
          maxlength="80"
          :placeholder="t('watchlist.collections.namePlaceholder')"
          class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.collections.description') }}</label>
        <textarea
          v-model="description"
          rows="2"
          maxlength="280"
          :placeholder="t('watchlist.collections.descriptionPlaceholder')"
          class="bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 resize-none"
        />
      </div>

      <div v-if="!initial" class="flex flex-col gap-1.5">
        <div class="flex items-center justify-between">
          <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.collections.addItemsOptional') }}</label>
          <span v-if="itemIds.length" class="text-xs text-indigo-600 dark:text-indigo-400">{{ t('watchlist.collections.selectedCount', { count: itemIds.length }) }}</span>
        </div>
        <ItemPicker v-model="itemIds" @update:selected-items="memberItems = $event" list-class="max-h-52 overflow-y-auto" />
      </div>

      <div class="flex flex-col gap-2.5">
        <label class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.collections.cover') }}</label>
        <div class="flex items-start gap-4">
          <div class="w-32 shrink-0 relative aspect-[16/10] rounded-xl overflow-hidden ring-1 ring-inset ring-black/10 dark:ring-white/10">
            <CollectionCover :image="coverMode === 'image' ? coverUrl : null" :posters="previewPosters" />
          </div>

          <div class="flex-1 min-w-0 flex flex-col gap-2.5">
            <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1 self-start">
              <button
                v-for="tab in COVER_TABS"
                :key="tab.key"
                type="button"
                @click="coverMode = tab.key"
                :class="[
                  'cursor-pointer px-3 py-1.5 rounded-lg text-xs font-medium transition-all',
                  coverMode === tab.key ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                ]"
              >
                {{ tab.label }}
              </button>
            </div>

            <template v-if="coverMode === 'auto'">
              <div class="flex items-center gap-2">
                <label class="text-xs text-slate-500 dark:text-slate-400">{{ t('watchlist.collections.coverCountLabel') }}</label>
                <input
                  v-model.number="coverCount"
                  type="number"
                  min="1"
                  max="8"
                  @change="coverCount = Math.min(8, Math.max(1, Math.round(coverCount || 1)))"
                  class="w-16 bg-slate-100 dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-2.5 py-1.5 text-sm tabular-nums focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>
              <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.coverAutoHint') }}</p>
            </template>

            <template v-else-if="coverMode === 'image'">
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  @click="fileInput?.click()"
                  :disabled="uploading"
                  class="cursor-pointer inline-flex items-center gap-2 px-3 py-1.5 text-xs font-medium text-slate-600 dark:text-slate-300 bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg transition-colors disabled:opacity-50"
                >
                  <Spinner v-if="uploading" class="w-3.5 h-3.5 animate-spin" />
                  <Icon v-else name="upload" class="w-3.5 h-3.5" />
                  {{ t('watchlist.collections.coverUploadCta') }}
                </button>
                <button
                  v-if="coverUrl"
                  type="button"
                  @click="coverUrl = ''"
                  class="cursor-pointer text-xs text-slate-400 hover:text-red-500 dark:hover:text-red-400 transition-colors"
                >
                  {{ t('watchlist.form.remove') }}
                </button>
              </div>
              <input ref="fileInput" type="file" accept="image/*" class="hidden" @change="handleUpload" />
            </template>

            <template v-else>
              <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.coverTitlesHint') }}</p>
              <div v-if="memberItems.length" class="grid grid-cols-5 sm:grid-cols-6 gap-1.5 max-h-44 overflow-y-auto pr-0.5">
                <button
                  v-for="m in memberItems"
                  :key="m._id"
                  type="button"
                  @click="toggleCover(m._id)"
                  :title="m.title"
                  :class="[
                    'relative aspect-[2/3] rounded-md overflow-hidden ring-2 transition',
                    coverSelected(m._id) ? 'ring-indigo-500' : 'ring-transparent hover:ring-indigo-400/50',
                  ]"
                >
                  <img v-if="m.posterUrl" :src="m.posterUrl" :alt="m.title" class="w-full h-full object-cover" />
                  <div v-else class="w-full h-full bg-slate-200 dark:bg-slate-700 flex items-center justify-center">
                    <ArchiveBoxIcon class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                  </div>
                  <div v-if="coverSelected(m._id)" class="absolute inset-0 bg-indigo-600/35 flex items-center justify-center">
                    <span class="w-5 h-5 rounded-full bg-indigo-600 text-white flex items-center justify-center">
                      <Icon name="checkBold" class="w-3 h-3" :sw="3" />
                    </span>
                  </div>
                </button>
              </div>
              <p v-else class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.collections.coverNoMembers') }}</p>
            </template>
          </div>
        </div>
      </div>
    </form>
  </TemplateModal>
</template>
