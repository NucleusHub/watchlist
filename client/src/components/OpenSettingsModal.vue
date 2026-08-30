<script setup>
import { reactive, ref, computed, watch, onMounted } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { usePlugins } from '@core/usePlugins.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { BUILTIN_SOURCES, PLUGIN_SOURCES } from '@/api/sources.js'
import { watchlistSurfaces } from '@/utils/pluginSurfaces.js'
import { OPEN_OPTIONS, TITLE_FORMATS, buildOpenUrl } from '@/utils/openTarget.js'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const props = defineProps({ show: { type: Boolean, default: false } })
const emit = defineEmits(['close'])

const { defaults, setDefault, searchSources, setSearchSources, placementOf, setPlacement } = useOpenSettings()

// Plugin display names for the "Added by …" badge on plugin-contributed sources.
const { plugins: installedPlugins, load: loadInstalledPlugins } = usePlugins()
onMounted(loadInstalledPlugins)
const pluginName = (id) => installedPlugins.value.find((p) => p.id === id)?.name || id

// Built-in TMDb plus enabled plugin sources — the toggleable search sources.
const availableSources = computed(() => [
  ...BUILTIN_SOURCES,
  ...PLUGIN_SOURCES.filter((s) => isPluginEnabled(s.pluginId)),
])
// Puzzle-piece glyph marking a plugin-contributed source (Heroicons).
const PLUGIN_ICON = 'M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 0 1-.657.643 48.4 48.4 0 0 1-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 0 1-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 0 0-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 0 1-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 0 0 .657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 0 1-.349-1.003c0-1.036 1.007-1.875 2.25-1.875s2.25.84 2.25 1.875c0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 0 0 5.427-.63 48.05 48.05 0 0 0 .582-4.717.532.532 0 0 0-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 0 0 .658-.663 48.422 48.422 0 0 0-.37-5.36c-1.676.32-3.4.475-5.157.475a.64.64 0 0 1-.657-.643Z'
// Draft set of enabled source ids, so Cancel/close leaves saved settings
// untouched. TMDb (the built-in) is always on and can't be turned off.
const draftSources = ref(['tmdb'])
const isSourceOn = (id) => id === 'tmdb' || draftSources.value.includes(id)
function toggleSource(id) {
  if (id === 'tmdb') return
  const set = new Set(draftSources.value)
  set.has(id) ? set.delete(id) : set.add(id)
  draftSources.value = [...set]
}

// Tabs via the shared TemplateModal tab bar (same look as the rest of the app).
// "Open in" is first, so it's the tab shown on open. The search-sources tab
// appears only when there's a plugin source to toggle (TMDb alone needs none) —
// with just TMDb the modal shows the open-in section with no tab bar.
const showSourcesTab = computed(() => availableSources.value.length > 1)

// ── Plugin surfaces ──────────────────────────────────────────────────────────
// Sections a plugin contributes to the app, each of which the user places as a
// tab, as a panel on the watchlist, or turns off. The tab only exists when a
// plugin actually ships one.
const availableSurfaces = computed(() => watchlistSurfaces.filter((s) => isPluginEnabled(s.pluginId)))
const showSurfacesTab = computed(() => availableSurfaces.value.length > 0)

// Drafted like the other tabs, so closing the modal without saving changes
// nothing: pluginId → 'tab' | 'panel' | 'hidden'.
const draftPlacements = ref({})
// 'hidden' is offered for every surface; a plugin only declares which of the
// two *visible* placements its component can handle.
const placementOptions = (surface) => [...surface.placements, 'hidden']
// Same tab icons as Shelf's settings modal (externalLink / search).
const OPEN_TAB_ICON = 'M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5M15 3h6m0 0v6m0-6L10.5 13.5'
const SOURCES_TAB_ICON = 'm21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607z'
// Squares-2x2 — "where sections of the app sit".
const EXTRAS_TAB_ICON = 'M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25Z'
const tabs = computed(() => {
  // With nothing but "Open in" there's no tab bar at all — that section just
  // renders on its own (see the v-show below).
  if (!showSourcesTab.value && !showSurfacesTab.value) return []
  const list = [{ key: 'open', label: t('watchlist.settings.tabOpen'), icon: OPEN_TAB_ICON }]
  if (showSourcesTab.value) list.push({ key: 'sources', label: t('watchlist.settings.tabSources'), icon: SOURCES_TAB_ICON })
  if (showSurfacesTab.value) list.push({ key: 'surfaces', label: t('watchlist.settings.tabExtras'), icon: EXTRAS_TAB_ICON })
  return list
})

const KINDS = [
  { key: 'movie', label: 'watchlist.open.movies' },
  { key: 'show', label: 'watchlist.open.shows' },
]

// Icons keep the two sections distinct and the destination chips scannable.
const KIND_ICON = {
  movie: 'M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h1.5C5.496 19.5 6 18.996 6 18.375m-3.75.125-.375-12a1.125 1.125 0 011.125-1.125h15.75A1.125 1.125 0 0120.625 6.5l-.375 12M6 18.375V7.875C6 7.254 6.504 6.75 7.125 6.75h9.75C17.496 6.75 18 7.254 18 7.875v10.5m0 0c0 .621-.504 1.125-1.125 1.125H7.125',
  show: 'M6 20.25h12m-7.5-3v3m3-3v3M3.75 6.75h16.5a1.5 1.5 0 011.5 1.5v7.5a1.5 1.5 0 01-1.5 1.5H3.75a1.5 1.5 0 01-1.5-1.5v-7.5a1.5 1.5 0 011.5-1.5z',
}
const DEST_ICON = {
  tmdb: 'M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75',
  csfd: 'M11.48 3.499a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.563.563 0 00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.562.562 0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z',
  google: 'M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z',
  custom: 'M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244',
}

// Edit a local draft so a Cancel/close leaves the saved defaults untouched.
const blank = () => ({ type: 'tmdb', customUrl: '', titleFormat: 'raw' })
const draft = reactive({ movie: blank(), show: blank() })

watch(
  () => props.show,
  (v) => {
    if (!v) return
    for (const { key } of KINDS) {
      draft[key] = { type: defaults[key].type, customUrl: defaults[key].customUrl || '', titleFormat: defaults[key].titleFormat || 'raw' }
    }
    draftSources.value = [...searchSources.value]
    draftPlacements.value = Object.fromEntries(
      availableSurfaces.value.map((s) => [s.pluginId, placementOf(s)])
    )
  },
  { immediate: true }
)

// Live preview of what a click will open, using a familiar sample title.
const SAMPLE = { title: 'The Matrix', year: 1999 }
const previewUrl = (kind) => buildOpenUrl(draft[kind], SAMPLE)

function save() {
  for (const { key } of KINDS) setDefault(key, draft[key])
  setSearchSources(draftSources.value)
  for (const [pluginId, where] of Object.entries(draftPlacements.value)) setPlacement(pluginId, where)
  emit('close')
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    :title="t('watchlist.open.settingsTitle')"
    :tabs="tabs"
    :confirm-label="t('watchlist.open.save')"
    :cancel-label="t('watchlist.open.cancel')"
    size="lg"
    body-class="px-5 pb-5 pt-5"
    @confirm="save"
    @cancel="emit('close')"
  >
    <template #default="{ activeTab }">
    <div class="flex flex-col gap-4">
      <!-- ── Open in ─────────────────────────────────────────────────────── -->
      <section v-show="activeTab === 'open' || !tabs.length" class="flex flex-col gap-4">
        <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.open.settingsDesc') }}</p>

        <div
          v-for="kind in KINDS"
          :key="kind.key"
          class="flex flex-col gap-3 rounded-xl border border-black/5 dark:border-white/10 bg-white/40 dark:bg-white/[0.03] p-4"
        >
          <!-- Section header -->
          <div class="flex items-center gap-2.5">
            <span class="grid place-items-center w-8 h-8 rounded-lg bg-indigo-600/10 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-400 shrink-0">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="KIND_ICON[kind.key]" />
              </svg>
            </span>
            <span class="text-sm font-semibold text-slate-900 dark:text-white">{{ t(kind.label) }}</span>
          </div>

          <!-- Destination chips -->
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="opt in OPEN_OPTIONS"
              :key="opt.type"
              type="button"
              @click="draft[kind.key].type = opt.type"
              :class="[
                'cursor-pointer inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-all border',
                draft[kind.key].type === opt.type
                  ? 'bg-indigo-600 text-white border-transparent shadow-sm shadow-indigo-600/30'
                  : 'bg-white/60 dark:bg-white/8 text-slate-600 dark:text-slate-300 border-black/5 dark:border-white/10 hover:bg-white dark:hover:bg-white/15 hover:text-slate-900 dark:hover:text-white',
              ]"
            >
              <svg class="w-3.5 h-3.5 shrink-0" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="DEST_ICON[opt.type]" />
              </svg>
              {{ t(opt.i18n) }}
            </button>
          </div>

          <!-- Custom URL config — nested panel so it reads as part of the section -->
          <div
            v-if="draft[kind.key].type === 'custom'"
            class="flex flex-col gap-2.5 rounded-lg bg-black/[0.03] dark:bg-black/20 border border-black/5 dark:border-white/10 p-3"
          >
            <input
              v-model="draft[kind.key].customUrl"
              type="url"
              :placeholder="t('watchlist.open.customPlaceholder')"
              class="bg-white dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
            <div class="flex items-center gap-2">
              <label class="text-xs text-slate-500 dark:text-slate-400 shrink-0">{{ t('watchlist.open.titleFormat') }}</label>
              <select v-model="draft[kind.key].titleFormat" class="cursor-pointer flex-1 bg-white dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500">
                <option v-for="fmt in TITLE_FORMATS" :key="fmt.value" :value="fmt.value">{{ t(fmt.i18n) }} — {{ fmt.example }}</option>
              </select>
            </div>
            <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.open.customHint') }}</p>
            <p v-if="previewUrl(kind.key)" class="text-xs text-slate-500 dark:text-slate-400 truncate">
              <span class="text-slate-400 dark:text-slate-500">{{ t('watchlist.open.preview') }}</span>
              <span class="font-mono text-indigo-600 dark:text-indigo-400">{{ previewUrl(kind.key) }}</span>
            </p>
          </div>
        </div>
      </section>

      <!-- ── Search sources ──────────────────────────────────────────────── -->
      <section v-show="activeTab === 'sources'" class="flex flex-col gap-3">
        <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.settings.searchSourceDesc') }}</p>
        <div class="flex flex-col gap-1.5">
          <div
            v-for="s in availableSources"
            :key="s.id"
            class="flex items-center justify-between gap-3 rounded-lg bg-white/60 dark:bg-white/[0.04] border border-black/5 dark:border-white/10 px-3 py-2.5"
          >
            <span class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 min-w-0">
              <span class="truncate">{{ s.label }}</span>
              <svg
                v-if="s.pluginId"
                class="w-3.5 h-3.5 shrink-0 text-indigo-500 dark:text-indigo-400 opacity-80"
                fill="currentColor"
                viewBox="0 0 24 24"
              >
                <title>{{ t('watchlist.settings.addedByPlugin', { name: pluginName(s.pluginId) }) }}</title>
                <path :d="PLUGIN_ICON" />
              </svg>
              <span v-if="s.id === 'tmdb'" class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.settings.alwaysOn') }}</span>
            </span>
            <button
              type="button"
              role="switch"
              :aria-checked="isSourceOn(s.id)"
              :disabled="s.id === 'tmdb'"
              @click="toggleSource(s.id)"
              :class="[
                'relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors',
                isSourceOn(s.id) ? 'bg-indigo-600' : 'bg-slate-300 dark:bg-slate-600',
                s.id === 'tmdb' ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer',
              ]"
            >
              <span
                :class="[
                  'inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform',
                  isSourceOn(s.id) ? 'translate-x-4' : 'translate-x-0.5',
                ]"
              />
            </button>
          </div>
        </div>
      </section>

      <!-- ── Plugin surfaces (Extras) ────────────────────────────────────── -->
      <section v-show="activeTab === 'surfaces'" class="flex flex-col gap-3">
        <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.settings.surfaceDesc') }}</p>
        <div class="flex flex-col gap-1.5">
          <div
            v-for="s in availableSurfaces"
            :key="s.pluginId"
            class="flex flex-col gap-2.5 rounded-lg bg-white/60 dark:bg-white/[0.04] border border-black/5 dark:border-white/10 px-3 py-2.5 sm:flex-row sm:items-center sm:justify-between"
          >
            <span class="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 min-w-0">
              <span class="truncate">{{ t(s.label) }}</span>
              <svg class="w-3.5 h-3.5 shrink-0 text-indigo-500 dark:text-indigo-400 opacity-80" fill="currentColor" viewBox="0 0 24 24">
                <title>{{ t('watchlist.settings.addedByPlugin', { name: pluginName(s.pluginId) }) }}</title>
                <path :d="PLUGIN_ICON" />
              </svg>
            </span>
            <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1 shrink-0 self-start sm:self-auto">
              <button
                v-for="where in placementOptions(s)"
                :key="where"
                type="button"
                @click="draftPlacements[s.pluginId] = where"
                :class="[
                  'cursor-pointer whitespace-nowrap px-3 py-1 rounded-lg text-xs font-medium transition-all',
                  draftPlacements[s.pluginId] === where
                    ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm'
                    : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
                ]"
              >
                {{ t('watchlist.settings.placement.' + where) }}
              </button>
            </div>
          </div>
        </div>
      </section>
    </div>
    </template>
  </TemplateModal>
</template>
