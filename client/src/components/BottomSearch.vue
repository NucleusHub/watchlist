<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import TemplateModal from '@core/TemplateModal.vue'
import TrashIcon from '@core/TrashIcon.vue'
import { getItems, updateItem, deleteItem } from '@/api/watchlist.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { emitItemChange } from '@/composables/useItemEvents.js'
import { resolveTarget, buildOpenUrl } from '@/utils/openTarget.js'
import { haptic } from '@/native.js'
import { useCollections } from '@/composables/useCollections.js'
import { runHeaderAction } from '@/composables/useTabsHeader.js'
import { useSlidingPill } from '@/composables/useSlidingPill.js'
import SegmentPill from '@/components/SegmentPill.vue'

const MAX_RESULTS = 60

const props = defineProps({
  filter: { type: Boolean, default: false },
  modelValue: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue', 'add'])

const { t } = useI18n()
const router = useRouter()
const { collections, applyMembership } = useCollections()
const { defaults } = useOpenSettings()

const input = ref(null)
const open = ref(false)
const ownQuery = ref('')
const query = computed({
  get: () => (props.filter ? props.modelValue : ownQuery.value),
  set: (v) => (props.filter ? emit('update:modelValue', v) : (ownQuery.value = v)),
})
const focused = ref(false)
const status = ref('all')
const type = ref('all')
const items = ref([])
const loading = ref(false)

const STATUS = computed(() => ['all', 'planned', 'watching', 'completed'].map((key) => ({ key, label: t(`watchlist.status.${key}`) })))
const TYPE = computed(() => [
  { key: 'all', label: t('watchlist.type.all') },
  { key: 'movie', label: t('watchlist.type.movies') },
  { key: 'show', label: t('watchlist.type.shows') },
])

const statusPill = useSlidingPill(status)
const typePill = useSlidingPill(type)
const statusBar = statusPill.container
const typeBar = typePill.container

const q = computed(() => query.value.trim().toLowerCase())
const filtering = computed(() => !!q.value || status.value !== 'all' || type.value !== 'all')

const titleResults = computed(() =>
  items.value
    .filter((i) =>
      (status.value === 'all' || i.status === status.value) &&
      (type.value === 'all' || i.type === type.value) &&
      (!q.value || i.title?.toLowerCase().includes(q.value) || i.notes?.toLowerCase().includes(q.value))
    )
    .slice(0, MAX_RESULTS)
)
const collectionResults = computed(() =>
  q.value && status.value === 'all' && type.value === 'all'
    ? collections.value.filter((c) => c.name?.toLowerCase().includes(q.value))
    : []
)
const empty = computed(() => filtering.value && !loading.value && !titleResults.value.length && !collectionResults.value.length)

const meta = (i) => [i.year, t(`watchlist.type.${i.type}`), t(`watchlist.status.${i.status}`)].filter(Boolean).join(' · ')
const dot = { planned: 'bg-[#eb6834] dark:bg-[#d95926]', watching: 'bg-[#2a78d6] dark:bg-[#3987e5]', completed: 'bg-[#1baf7a] dark:bg-[#199e70]' }

async function onFocus() {
  focused.value = true
  if (props.filter || open.value) return
  open.value = true
  loading.value = true
  try {
    items.value = await getItems()
  } catch {
  } finally {
    loading.value = false
  }
}

function add() {
  if (props.filter) emit('add')
  else runHeaderAction('add', router)
}

function close() {
  open.value = false
  if (!props.filter) query.value = ''
  status.value = 'all'
  type.value = 'all'
  input.value?.blur()
}

function clear() {
  query.value = ''
  input.value?.focus()
}

function editItem(item) {
  close()
  runHeaderAction('edit', router, item)
}

function openItem(item) {
  const url = buildOpenUrl(resolveTarget(item, defaults), item)
  if (url) window.open(url, '_blank', 'noopener,noreferrer')
  else editItem(item)
}

function replaceItem(updated) {
  items.value = items.value.map((i) => (i._id === updated._id ? updated : i))
  emitItemChange({ type: 'updated', item: updated })
}

const busy = ref(null)
async function completeItem(item) {
  if (busy.value) return
  haptic('Light')
  busy.value = item._id
  try {
    const patch = { status: 'completed' }
    if (item.type === 'show' && item.seasonProgress?.length) {
      patch.seasonProgress = item.seasonProgress.map((s) => ({ ...s, watched: s.episodeCount }))
    }
    replaceItem(await updateItem(item._id, patch))
  } finally {
    busy.value = null
  }
}

const deleting = ref(null)
const deletingBusy = ref(false)
async function confirmDelete() {
  const item = deleting.value
  if (!item) return
  deletingBusy.value = true
  try {
    await deleteItem(item._id)
    applyMembership(item.collectionIds || [], [])
    items.value = items.value.filter((i) => i._id !== item._id)
    emitItemChange({ type: 'deleted', id: item._id })
    deleting.value = null
  } finally {
    deletingBusy.value = false
  }
}

function pickCollection(col) {
  close()
  router.push(`/collections/${col._id}`)
}

watch(open, (v) => {
  document.documentElement.style.overflow = v ? 'hidden' : ''
})

function onKey(e) {
  if (e.key === 'Escape' && open.value && !deleting.value) close()
}

onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKey)
  document.documentElement.style.overflow = ''
})
</script>

<template>
  <div data-no-swipe class="ss-root">
    <Transition name="ss-fade">
      <div v-if="open" class="ss-backdrop" @click="close" />
    </Transition>

    <Transition name="ss-sheet">
      <div v-if="open" class="ss-sheet lg-glass">
        <div class="ss-results">
          <div v-if="!filtering" class="flex flex-col items-center gap-3 py-10 text-center text-slate-500 dark:text-white/55">
            <Icon name="search" class="w-7 h-7 opacity-70" :sw="1.75" />
            <p class="text-sm">{{ t('watchlist.search.hint') }}</p>
          </div>

          <p v-else-if="loading && !items.length" class="py-10 text-center text-sm text-slate-500 dark:text-white/55">
            {{ t('watchlist.state.loading') }}
          </p>

          <p v-else-if="empty" class="py-10 text-center text-sm text-slate-500 dark:text-white/55">
            {{ t('watchlist.search.empty') }}
          </p>

          <template v-else>
            <section v-if="collectionResults.length" class="mb-2">
              <h3 class="ss-heading">{{ t('watchlist.nav.collections') }}</h3>
              <button v-for="c in collectionResults" :key="c._id" type="button" class="ss-row" @click="pickCollection(c)">
                <span class="w-10 h-10 shrink-0 rounded-lg bg-indigo-500/15 text-indigo-600 dark:text-indigo-300 flex items-center justify-center">
                  <Icon name="folder" class="w-5 h-5" :sw="1.75" />
                </span>
                <span class="min-w-0 flex-1 truncate text-left font-medium">{{ c.name }}</span>
              </button>
            </section>

            <section v-if="titleResults.length">
              <h3 class="ss-heading">{{ t('watchlist.search.titles') }}</h3>
              <div v-for="i in titleResults" :key="i._id" role="button" tabindex="0" class="ss-row" @click="openItem(i)" @keydown.enter="openItem(i)">
                <span class="w-10 h-14 shrink-0 rounded-md overflow-hidden bg-slate-500/15">
                  <img v-if="i.posterUrl" :src="i.posterUrl" alt="" loading="lazy" class="w-full h-full object-cover" />
                </span>
                <span class="min-w-0 flex-1 text-left">
                  <span class="block truncate font-medium">{{ i.title }}</span>
                  <span class="mt-0.5 flex items-center gap-1.5 text-xs text-slate-500 dark:text-white/55">
                    <span :class="['w-1.5 h-1.5 rounded-full shrink-0', dot[i.status] || 'bg-slate-400']" />
                    <span class="truncate">{{ meta(i) }}</span>
                  </span>
                </span>
                <span class="flex items-center gap-1 shrink-0">
                  <button
                    v-if="i.status !== 'completed'"
                    type="button"
                    :title="t('watchlist.card.markWatched')"
                    :disabled="busy === i._id"
                    class="ss-act nuc-press"
                    @click.stop="completeItem(i)"
                  >
                    <Icon name="check" class="w-4 h-4" :sw="2.5" />
                  </button>
                  <button type="button" :title="t('watchlist.card.edit')" class="ss-act nuc-press" @click.stop="editItem(i)">
                    <Icon name="edit" class="w-4 h-4" />
                  </button>
                  <button type="button" :title="t('watchlist.card.delete')" class="ss-act ss-act-danger nuc-trash nuc-press" @click.stop="deleting = i">
                    <TrashIcon class="w-4 h-4" stroke-width="2" />
                  </button>
                </span>
              </div>
            </section>
          </template>
        </div>

        <div class="ss-filters">
          <div ref="statusBar" class="relative inline-flex items-center gap-0.5 bg-black/[0.05] dark:bg-white/[0.07] rounded-xl p-1">
            <SegmentPill :style="statusPill.pillStyle.value" :animate="statusPill.animate.value" />
            <button
              v-for="o in STATUS"
              :key="o.key"
              :ref="(el) => statusPill.setItem(o.key, el)"
              type="button"
              :class="['relative cursor-pointer whitespace-nowrap px-3 py-1.5 rounded-lg text-sm font-medium transition-colors duration-300', status === o.key ? 'text-slate-900 dark:text-white' : 'text-slate-500 dark:text-white/55']"
              @pointerdown.prevent
              @click="status = o.key"
            >
              {{ o.label }}
            </button>
          </div>
          <div ref="typeBar" class="relative inline-flex items-center gap-0.5 bg-black/[0.05] dark:bg-white/[0.07] rounded-xl p-1">
            <SegmentPill :style="typePill.pillStyle.value" :animate="typePill.animate.value" />
            <button
              v-for="o in TYPE"
              :key="o.key"
              :ref="(el) => typePill.setItem(o.key, el)"
              type="button"
              :class="['relative cursor-pointer whitespace-nowrap px-3 py-1.5 rounded-lg text-sm font-medium transition-colors duration-300', type === o.key ? 'text-slate-900 dark:text-white' : 'text-slate-500 dark:text-white/55']"
              @pointerdown.prevent
              @click="type = o.key"
            >
              {{ o.label }}
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <TemplateModal
      :show="!!deleting"
      :title="t('watchlist.card.removeTitle')"
      :message="t('watchlist.card.removeMessage', { title: deleting?.title })"
      :confirm-label="t('watchlist.card.remove')"
      :busy="deletingBusy"
      @confirm="confirmDelete"
      @cancel="deleting = null"
    />

    <div class="ss-bar">
      <form
        role="search"
        :class="['lg-pill lg-glass', { 'is-open': open || (filter && focused) }]"
        @submit.prevent="input?.blur()"
        @click="input?.focus()"
      >
        <Icon name="search" class="relative w-[18px] h-[18px] shrink-0 text-slate-500 dark:text-white/60" :sw="2" />
        <input
          ref="input"
          v-model="query"
          type="search"
          enterkeyhint="search"
          autocomplete="off"
          autocorrect="off"
          spellcheck="false"
          :placeholder="t('watchlist.header.search')"
          class="relative min-w-0 flex-1 bg-transparent text-base text-slate-900 dark:text-white placeholder:text-slate-500 dark:placeholder:text-white/45 outline-none"
          @focus="onFocus"
          @blur="focused = false"
        />
        <Transition name="ss-pop">
          <button
            v-if="query"
            type="button"
            :aria-label="t('watchlist.form.remove')"
            class="relative shrink-0 w-6 h-6 -mr-1 rounded-full flex items-center justify-center bg-slate-900/10 dark:bg-white/15 text-slate-600 dark:text-white/80 cursor-pointer"
            @pointerdown.prevent
            @click.stop="clear"
          >
            <Icon name="close" class="w-3 h-3" :sw="3" />
          </button>
        </Transition>
      </form>

      <Transition name="ss-cancel">
        <button v-if="open" key="cancel" type="button" class="ss-cancel lg-glass" @click="close">
          {{ t('watchlist.search.cancel') }}
        </button>
        <button
          v-else
          key="add"
          type="button"
          :aria-label="t('watchlist.header.add')"
          class="ss-add lg-glass nuc-press"
          @click="add"
        >
          <Icon name="plus" class="relative w-5 h-5" :sw="2.5" />
        </button>
      </Transition>
    </div>
  </div>
</template>

<style scoped>
.ss-root {
  --lift: max(0px, calc(var(--kb, 0px) + 8px - max(16px, env(safe-area-inset-bottom))));
}

.ss-bar {
  translate: 0 calc(-1 * var(--lift));
  transition: translate 0.32s cubic-bezier(0.2, 0.8, 0.2, 1);
  position: fixed;
  left: 0;
  right: 0;
  bottom: max(16px, env(safe-area-inset-bottom));
  z-index: 60;
  display: flex;
  justify-content: center;
  gap: 8px;
  padding: 0 16px;
  pointer-events: none;
}

.lg-pill {
  pointer-events: auto;
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 1 1 auto;
  min-width: 0;
  max-width: 520px;
  height: 50px;
  padding: 0 18px;
  border-radius: 9999px;
  cursor: text;
  transition: box-shadow 0.35s cubic-bezier(0.22, 1, 0.36, 1);
}
.lg-pill.is-open {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.95),
    inset 0 -1px 1px rgba(255, 255, 255, 0.4),
    0 18px 40px -12px rgba(15, 23, 42, 0.34),
    0 0 0 4px rgba(99, 102, 241, 0.14);
}
.dark .lg-pill.is-open {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.34),
    inset 0 -1px 1px rgba(255, 255, 255, 0.1),
    0 20px 44px -12px rgba(0, 0, 0, 0.8),
    0 0 0 4px rgba(139, 92, 246, 0.22);
}

.ss-cancel {
  pointer-events: auto;
  flex: 0 0 auto;
  height: 50px;
  padding: 0 18px;
  border-radius: 9999px;
  font-size: 15px;
  font-weight: 600;
  color: #4f46e5;
  cursor: pointer;
  overflow: hidden;
  white-space: nowrap;
}
.dark .ss-cancel { color: #c4b5fd; }

.ss-add {
  pointer-events: auto;
  flex: 0 0 auto;
  width: 50px;
  height: 50px;
  border-radius: 9999px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #4f46e5;
  cursor: pointer;
}
.dark .ss-add { color: #c4b5fd; }

.ss-backdrop {
  position: fixed;
  inset: 0;
  z-index: 50;
  background: rgba(241, 245, 249, 0.35);
  -webkit-backdrop-filter: blur(14px) saturate(120%);
  backdrop-filter: blur(14px) saturate(120%);
}
.dark .ss-backdrop { background: rgba(4, 2, 10, 0.5); }

.ss-sheet {
  position: fixed;
  z-index: 55;
  left: 16px;
  right: 16px;
  bottom: calc(max(16px, env(safe-area-inset-bottom)) + 62px);
  max-height: calc(100% - max(16px, env(safe-area-inset-bottom)) - 62px - max(16px, env(safe-area-inset-top)) - 8px - var(--lift));
  translate: 0 calc(-1 * var(--lift));
  transition: translate 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), max-height 0.32s cubic-bezier(0.2, 0.8, 0.2, 1);
  margin: 0 auto;
  max-width: 560px;
  display: flex;
  flex-direction: column;
  border-radius: 26px;
  overflow: hidden;
  transform-origin: 50% 100%;
}

.ss-results {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  -webkit-overflow-scrolling: touch;
  padding: 8px;
}

.ss-heading {
  padding: 8px 10px 4px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: rgb(100 116 139);
}
.dark .ss-heading { color: rgba(255, 255, 255, 0.45); }

.ss-row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 6px 10px;
  border-radius: 14px;
  font-size: 15px;
  color: rgb(15 23 42);
  cursor: pointer;
  transition: background-color 0.15s ease;
}
.dark .ss-row { color: #fff; }
.ss-row:active { background: rgba(15, 23, 42, 0.06); }
.dark .ss-row:active { background: rgba(255, 255, 255, 0.08); }
@media (hover: hover) {
  .ss-row:hover { background: rgba(15, 23, 42, 0.05); }
  .dark .ss-row:hover { background: rgba(255, 255, 255, 0.06); }
}

.ss-act {
  width: 32px;
  height: 32px;
  border-radius: 9999px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgb(100 116 139);
  background: rgba(15, 23, 42, 0.06);
  cursor: pointer;
  transition: background-color 0.15s ease, color 0.15s ease;
}
.dark .ss-act {
  color: rgba(255, 255, 255, 0.7);
  background: rgba(255, 255, 255, 0.08);
}
.ss-act:disabled { opacity: 0.5; cursor: wait; }
.ss-act-danger:hover,
.ss-act-danger:active { color: #ef4444; }

.ss-filters {
  flex: 0 0 auto;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 10px;
  border-top: 1px solid rgba(15, 23, 42, 0.06);
}
.dark .ss-filters { border-top-color: rgba(255, 255, 255, 0.07); }

input[type='search']::-webkit-search-cancel-button,
input[type='search']::-webkit-search-decoration {
  -webkit-appearance: none;
  appearance: none;
}

.ss-fade-enter-active,
.ss-fade-leave-active { transition: opacity 0.3s ease; }
.ss-fade-enter-from,
.ss-fade-leave-to { opacity: 0; }

.ss-sheet-enter-active {
  transition: opacity 0.3s ease, transform 0.45s cubic-bezier(0.22, 1, 0.36, 1);
}
.ss-sheet-leave-active {
  transition: opacity 0.2s ease, transform 0.25s ease-in;
}
.ss-sheet-enter-from,
.ss-sheet-leave-to {
  opacity: 0;
  transform: translateY(16px) scale(0.96);
}

.ss-cancel-enter-active,
.ss-cancel-leave-active {
  transition: max-width 0.35s cubic-bezier(0.22, 1, 0.36, 1), padding 0.35s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.25s ease;
  max-width: 140px;
}
.ss-cancel-enter-from,
.ss-cancel-leave-to {
  max-width: 0;
  padding-left: 0;
  padding-right: 0;
  opacity: 0;
}

.ss-pop-enter-active,
.ss-pop-leave-active {
  transition: opacity 0.2s ease, transform 0.25s cubic-bezier(0.22, 1, 0.36, 1);
}
.ss-pop-enter-from,
.ss-pop-leave-to {
  opacity: 0;
  transform: scale(0.6);
}

@media (prefers-reduced-motion: reduce) {
  .ss-sheet-enter-active,
  .ss-sheet-leave-active,
  .ss-cancel-enter-active,
  .ss-cancel-leave-active { transition: opacity 0.15s linear; }
  .ss-sheet-enter-from,
  .ss-sheet-leave-to { transform: none; }
}
</style>
