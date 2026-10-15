<script setup>
// Home's frame (iOS HomeView): round buttons with search between them, the tab pills and the title count.
// Every tab page sits inside it.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import AppSidebar from '@core/AppSidebar.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { getItems } from '@/api/watchlist.js'
import { useCollections } from '@/composables/useCollections.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { watchlistSurfaces, headerButtons } from '@/utils/pluginSurfaces.js'
import { searchAll } from '@/utils/globalSearch.js'
import { itemRoute } from '@/utils/routes.js'
import { itemsVersion } from '@/composables/useItemSheet.js'
import { useScrolled } from '@/composables/useScrolled.js'
import GlassCircleButton from '@/ui/GlassCircleButton.vue'
import SegmentPills from '@/ui/SegmentPills.vue'
import Glyph from '@/ui/Glyph.vue'

const props = defineProps({
  // The library when the page already has it; otherwise the shell loads it for the count and search.
  items: { type: Array, default: null },
  addable: { type: Boolean, default: false },
  searchPrompt: { type: String, default: '' },
})
const emit = defineEmits(['add'])

const { t } = useI18n()
const route = useRoute()
const { isPluginEnabled } = useRegistry()
const { placementOf } = useOpenSettings()
const { collections } = useCollections()

const own = ref([])
const library = computed(() => props.items ?? own.value)
const loadOwn = async () => { if (!props.items) own.value = await getItems().catch(() => []) }
onMounted(loadOwn)
watch(itemsVersion, loadOwn)

// The app's own tabs first, then what plugins add: their tabs, then their pages (News).
const tabs = computed(() => [
  { key: 'watchlist', label: t('watchlist.nav.watchlist'), to: '/' },
  { key: 'collections', label: t('watchlist.nav.collections'), to: '/collections' },
  ...watchlistSurfaces
    .filter((s) => isPluginEnabled(s.pluginId) && placementOf(s) === 'tab')
    .map((s) => ({ key: `x/${s.path}`, label: t(s.label), to: `/x/${s.path}` })),
  ...headerButtons
    .filter((b) => isPluginEnabled(b.pluginId))
    .map((b) => ({ key: `p/${b.pluginId}/${b.page}`, label: t(b.title), to: `/p/${b.pluginId}/${b.page}` })),
])
const activeTab = computed(() => {
  if (route.name === 'watchlist') return 'watchlist'
  if (route.name === 'collections') return 'collections'
  if (route.name === 'plugin-surface') return `x/${route.params.surface}`
  if (route.name === 'plugin-page') return `p/${route.params.plugin}/${route.params.page}`
  return ''
})

const stats = computed(() => ({
  total: library.value.length,
  watching: library.value.filter((i) => i.status === 'watching').length,
  completed: library.value.filter((i) => i.status === 'completed').length,
}))

const sidebarOpen = ref(false)

const router = useRouter()
const query = ref('')
const input = ref(null)
const focused = ref(false)
const active = ref(0)
const prompt = computed(() => props.searchPrompt || t('watchlist.search.prompt'))
const hits = computed(() => searchAll(activeTab.value === 'collections' ? [] : library.value, collections.value, query.value, 20))
const open = computed(() => focused.value && !!query.value.trim())

// Typeahead: collections then titles, one list for the arrow keys.
const options = computed(() => [
  ...hits.value.collections.slice(0, 4).map((c) => ({
    key: `c${c._id}`, kind: 'collection', title: c.name, image: c.coverUrl || c.previewPosters?.[0],
    sub: t('watchlist.collections.itemCount', { count: c.itemCount || 0 }), to: { name: 'collection', params: { id: String(c._id) } },
  })),
  ...hits.value.items.map((i) => ({
    key: `i${i._id}`, kind: i.type === 'show' ? 'tv' : 'film', title: i.title, image: i.posterUrl,
    sub: [i.year, t('watchlist.status.' + i.status)].filter(Boolean).join(' · '), to: itemRoute(i._id),
  })),
])
const firstTitle = computed(() => options.value.findIndex((o) => o.kind !== 'collection'))
watch(query, () => { active.value = 0 })

function cancelSearch() {
  query.value = ''
  input.value?.blur()
}

function go(option) {
  if (!option) return
  router.push(option.to)
  cancelSearch()
}

function onSearchKey(e) {
  const n = options.value.length
  if (e.key === 'ArrowDown' && n) { e.preventDefault(); active.value = (active.value + 1) % n }
  else if (e.key === 'ArrowUp' && n) { e.preventDefault(); active.value = (active.value - 1 + n) % n }
  else if (e.key === 'Enter') { e.preventDefault(); go(options.value[active.value]) }
  else if (e.key === 'Escape') cancelSearch()
}

// "/" or ⌘K jumps to search, as on the other Nucleus web apps' bottom search.
function onKey(e) {
  const typing = /^(input|textarea|select)$/i.test(e.target?.tagName) || e.target?.isContentEditable
  if ((e.key === '/' && !typing) || (e.key === 'k' && (e.metaKey || e.ctrlKey))) {
    e.preventDefault()
    input.value?.focus()
  }
}
onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
const { scrolled, sentinel } = useScrolled()
</script>

<template>
  <div class="relative min-h-screen bg-[var(--wl-base)] text-[var(--wl-text)] overflow-x-clip">
    <div ref="sentinel" class="absolute top-0 h-px w-px" aria-hidden="true" />
    <BackgroundBlobs />

    <header class="sticky top-0 z-30 px-4 pt-3 pb-2">
      <div :class="['wl-scroll-edge', { on: scrolled }]" aria-hidden="true" />
      <div class="max-w-5xl mx-auto flex flex-col items-center gap-2.5">
        <div class="w-full grid grid-cols-[auto_minmax(0,1fr)_auto] md:grid-cols-[1fr_minmax(0,460px)_1fr] items-center gap-2">
          <div :class="['flex items-center gap-2', focused ? 'max-sm:hidden' : '']">
            <GlassCircleButton icon="menu" :title="t('watchlist.header.menu')" @click="sidebarOpen = !sidebarOpen" />
            <GlassCircleButton v-if="stats.total" icon="stats" to="/stats" :title="t('watchlist.header.statistics')" class="max-sm:!hidden" />
          </div>
          <!-- On phones the field takes the whole row while it's in use. -->
          <div :class="['relative', focused ? 'max-sm:col-span-3' : '']">
          <label v-glass="'live'" :class="['relative z-[41] h-10 rounded-full flex items-center gap-2 pl-3.5 pr-2 cursor-text', open ? 'wl-search-open' : '']">
            <Glyph name="magnifier" :sw="2.25" class="w-4 h-4 text-[var(--wl-text-2)] shrink-0" />
            <input
              ref="input"
              v-model="query"
              type="search"
              autocomplete="off"
              :placeholder="prompt"
              :aria-label="prompt"
              role="combobox"
              aria-autocomplete="list"
              aria-controls="wl-search-list"
              :aria-expanded="open"
              :aria-activedescendant="open && options[active] ? `wl-opt-${options[active].key}` : undefined"
              class="flex-1 min-w-0 bg-transparent outline-none text-[15px] text-[var(--wl-text)] placeholder:text-[var(--wl-text-2)] [&::-webkit-search-cancel-button]:hidden"
              @focus="focused = true"
              @blur="focused = false"
              @keydown="onSearchKey"
            />
            <button
              v-if="query"
              type="button"
              :aria-label="t('watchlist.search.clear')"
              class="cursor-pointer w-[22px] h-[22px] shrink-0 rounded-full grid place-items-center bg-[var(--wl-well)] text-[var(--wl-glyph)]"
              @mousedown.prevent
              @click="query = ''"
            >
              <Glyph name="close" :sw="3" class="w-2.5 h-2.5" />
            </button>
            <kbd v-else class="max-md:hidden shrink-0 px-1.5 min-w-[22px] h-[22px] rounded-[7px] grid place-items-center text-[11px] font-medium text-[var(--wl-text-2)] bg-[var(--wl-well)]">/</kbd>
          </label>

          <Transition name="typeahead">
            <div
              v-if="open"
              id="wl-search-list"
              role="listbox"
              class="wl-typeahead glass absolute top-0 left-0 right-0 z-40 rounded-[20px] px-1.5 pb-1.5 pt-10 max-h-[min(80vh,680px)] overflow-y-auto no-scrollbar shadow-[0_24px_60px_-16px_rgb(0_0_0/0.55)]"
              @mousedown.prevent
            >
              <div class="mx-2 mb-1 h-px bg-[var(--wl-sep)]" />
              <template v-for="(o, n) in options" :key="o.key">
                <p v-if="n === 0 && o.kind === 'collection'" class="px-3 pt-1.5 pb-1 text-[11px] font-semibold uppercase tracking-[0.04em] text-[var(--wl-text-2)]">{{ t('watchlist.search.collections') }}</p>
                <p v-if="n === firstTitle" class="px-3 pt-2 pb-1 text-[11px] font-semibold uppercase tracking-[0.04em] text-[var(--wl-text-2)]">{{ t('watchlist.search.titles') }}</p>
                <RouterLink
                  :id="`wl-opt-${o.key}`"
                  :to="o.to"
                  role="option"
                  :aria-selected="n === active"
                  :class="['flex items-center gap-3 px-2.5 py-1.5 rounded-[14px] no-underline text-[var(--wl-text)] transition-colors', n === active ? 'bg-[var(--wl-well)]' : '']"
                  @mouseenter="active = n"
                  @click.prevent="go(o)"
                >
                  <span :class="['shrink-0 overflow-hidden bg-[var(--wl-well)] grid place-items-center', o.kind === 'collection' ? 'w-10 h-10 rounded-[10px]' : 'w-8 h-12 rounded-[6px]']">
                    <img v-if="o.image" :src="o.image" alt="" class="w-full h-full object-cover" />
                    <Glyph v-else :name="o.kind === 'collection' ? 'folder' : o.kind" class="w-4 h-4 text-[var(--wl-text-2)]" />
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block truncate text-[15px] font-medium">{{ o.title }}</span>
                    <span class="block truncate text-xs text-[var(--wl-text-2)]">{{ o.sub }}</span>
                  </span>
                  <Glyph v-if="n === active" name="chevronRight" :sw="2.5" class="w-3.5 h-3.5 text-[var(--wl-text-2)]" />
                </RouterLink>
              </template>
              <div v-if="!options.length" class="px-3 py-5 text-center">
                <p class="text-sm font-medium">{{ t('watchlist.search.noMatches') }}</p>
                <p class="text-xs text-[var(--wl-text-2)] mt-0.5">{{ t('watchlist.search.noMatchesHint', { query: query.trim() }) }}</p>
              </div>
            </div>
          </Transition>
          </div>
          <div :class="['flex items-center justify-end gap-2', focused ? 'max-sm:hidden' : '']">
            <slot name="actions" />
            <GlassCircleButton v-if="addable" :title="t('watchlist.header.add')" class="!text-[var(--wl-accent)]" @click="emit('add')">
              <Glyph name="plus" :sw="2.75" class="w-[18px] h-[18px]" />
            </GlassCircleButton>
            <GlassCircleButton icon="cog" to="/settings" :title="t('watchlist.header.settings')" />
          </div>
        </div>
        <div class="max-w-full overflow-x-auto no-scrollbar p-1 -m-1">
          <SegmentPills :items="tabs" :model-value="activeTab" glass memory="home" />
        </div>
        <p v-if="stats.total" class="text-xs text-[var(--wl-text-2)] tabular-nums">{{ t('watchlist.header.stats', stats) }}</p>
      </div>
    </header>

    <main class="relative z-10 max-w-5xl mx-auto px-4 pt-3 pb-16">
      <slot />
    </main>

    <AppSidebar :open="sidebarOpen" @close="sidebarOpen = false" />
  </div>
</template>

<style scoped>
/* While the list is open the field draws nothing: the list's panel runs behind it as one shape. */
.wl-search-open { background: transparent !important; border-color: transparent !important; box-shadow: none !important; backdrop-filter: none !important; }
.wl-search-open > :deep(.lg-inner) { display: none; }
/* A list over posters needs more frost than the glass controls to stay readable. */
.wl-typeahead { background: color-mix(in oklab, var(--wl-base) 78%, transparent); backdrop-filter: blur(36px) saturate(180%); }
.typeahead-leave-active { transition: opacity 0.1s ease; }
.typeahead-enter-from { opacity: 0; clip-path: inset(0 0 85% 0 round 20px); }
.typeahead-enter-active { transition: opacity 0.16s ease, clip-path 0.28s var(--nuc-ease); }
.typeahead-leave-to { opacity: 0; }
</style>
