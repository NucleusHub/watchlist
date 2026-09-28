<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { usePlugins } from '@core/usePlugins.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { useTmdbKey } from '@/composables/useTmdbKey.js'
import { useSlidingPill } from '@/composables/useSlidingPill.js'
import SegmentPill from '@/components/SegmentPill.vue'
import PageShell from '@/layouts/PageShell.vue'
import { BUILTIN_SOURCES, PLUGIN_SOURCES } from '@/api/sources.js'
import { watchlistSurfaces } from '@/utils/pluginSurfaces.js'
import { OPEN_OPTIONS, TITLE_FORMATS, buildOpenUrl } from '@/utils/openTarget.js'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { defaults, setDefault, searchSources, setSearchSources, placementOf, setPlacement } = useOpenSettings()
const { plugins: installedPlugins, load: loadInstalledPlugins } = usePlugins()
onMounted(loadInstalledPlugins)
const pluginName = (id) => installedPlugins.value.find((p) => p.id === id)?.name || id

const KINDS = [
  { key: 'movie', label: 'watchlist.open.movies' },
  { key: 'show', label: 'watchlist.open.shows' },
]
const kind = ref('movie')
const kindPill = useSlidingPill(kind)
const kindBar = kindPill.container

const DEST_ICON = {
  tmdb: 'M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75',
  csfd: 'M11.48 3.499a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.563.563 0 00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.562.562 0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z',
  google: 'M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z',
  custom: 'M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244',
}

const current = computed(() => defaults[kind.value])
function update(patch) {
  setDefault(kind.value, { ...defaults[kind.value], ...patch })
}
const SAMPLE = { title: 'The Matrix', year: 1999 }
const preview = computed(() => buildOpenUrl(current.value, SAMPLE))

const availableSources = computed(() => [...BUILTIN_SOURCES, ...PLUGIN_SOURCES.filter((s) => isPluginEnabled(s.pluginId))])
const isSourceOn = (id) => id === 'tmdb' || searchSources.value.includes(id)
function toggleSource(id) {
  if (id === 'tmdb') return
  const set = new Set(searchSources.value)
  set.has(id) ? set.delete(id) : set.add(id)
  setSearchSources([...set])
}

const { apiKey: tmdbKey } = useTmdbKey()
const tmdbKeyDraft = ref(tmdbKey.value)
const tmdbKeySaved = ref(false)
let savedTimer
function saveTmdbKey() {
  const next = tmdbKeyDraft.value.trim()
  if (next === tmdbKey.value) return
  tmdbKey.value = next
  tmdbKeySaved.value = true
  clearTimeout(savedTimer)
  savedTimer = setTimeout(() => { tmdbKeySaved.value = false }, 2000)
}
watch(tmdbKey, (v) => { tmdbKeyDraft.value = v })

const availableSurfaces = computed(() => watchlistSurfaces.filter((s) => isPluginEnabled(s.pluginId)))
const placementOptions = (surface) => [...surface.placements, 'hidden']
</script>

<template>
  <PageShell :title="t('watchlist.open.settingsTitle')">
      <h2 class="set-heading">{{ t('watchlist.settings.tabOpen') }}</h2>
      <section class="lg-glass set-group">
        <div class="p-3 pb-2">
          <div ref="kindBar" class="relative flex items-center gap-0.5 bg-black/[0.05] dark:bg-white/[0.07] rounded-xl p-1">
            <SegmentPill :style="kindPill.pillStyle.value" :animate="kindPill.animate.value" />
            <button
              v-for="k in KINDS"
              :key="k.key"
              :ref="(el) => kindPill.setItem(k.key, el)"
              type="button"
              :class="['relative flex-1 cursor-pointer py-1.5 rounded-lg text-sm font-medium transition-colors duration-300', kind === k.key ? 'text-slate-900 dark:text-white' : 'text-slate-500 dark:text-white/55']"
              @click="kind = k.key"
            >
              {{ t(k.label) }}
            </button>
          </div>
        </div>

        <button
          v-for="opt in OPEN_OPTIONS"
          :key="opt.type"
          type="button"
          class="set-row"
          @click="update({ type: opt.type })"
        >
          <span class="set-icon">
            <svg class="w-[18px] h-[18px]" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" :d="DEST_ICON[opt.type]" />
            </svg>
          </span>
          <span class="flex-1 text-left">{{ t(opt.i18n) }}</span>
          <Icon v-if="current.type === opt.type" name="check" class="w-5 h-5 text-indigo-600 dark:text-violet-300" :sw="2.5" />
        </button>

        <div v-if="current.type === 'custom'" class="set-row-static set-stack">
          <input
            :value="current.customUrl"
            type="url"
            inputmode="url"
            autocapitalize="off"
            :placeholder="t('watchlist.open.customPlaceholder')"
            class="set-input"
            @input="update({ customUrl: $event.target.value })"
          />
          <label class="flex items-center justify-between gap-3 text-sm">
            <span class="text-slate-600 dark:text-white/70">{{ t('watchlist.open.titleFormat') }}</span>
            <select :value="current.titleFormat" class="set-select" @change="update({ titleFormat: $event.target.value })">
              <option v-for="fmt in TITLE_FORMATS" :key="fmt.value" :value="fmt.value">{{ t(fmt.i18n) }} — {{ fmt.example }}</option>
            </select>
          </label>
          <p class="text-xs text-slate-500 dark:text-white/45">{{ t('watchlist.open.customHint') }}</p>
          <p v-if="preview" class="text-xs truncate">
            <span class="text-slate-500 dark:text-white/45">{{ t('watchlist.open.preview') }}</span>
            <span class="font-mono text-indigo-600 dark:text-violet-300">{{ preview }}</span>
          </p>
        </div>
      </section>
      <p class="set-foot">{{ t('watchlist.open.settingsDesc') }}</p>

      <h2 class="set-heading">{{ t('watchlist.settings.tabSources') }}</h2>
      <section class="lg-glass set-group">
        <div class="set-row-static set-stack">
          <div class="flex items-center justify-between gap-3">
            <span class="font-medium">{{ t('watchlist.settings.tmdbKeyLabel') }}</span>
            <a
              href="https://www.themoviedb.org/settings/api"
              target="_blank"
              rel="noopener"
              class="shrink-0 text-sm font-medium text-indigo-600 dark:text-violet-300"
            >{{ t('watchlist.settings.tmdbKeyGuide') }}</a>
          </div>
          <input
            v-model="tmdbKeyDraft"
            type="text"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            enterkeyhint="done"
            :placeholder="t('watchlist.settings.tmdbKeyPlaceholder')"
            class="set-input"
            @blur="saveTmdbKey"
            @keydown.enter.prevent="$event.target.blur()"
          />
          <p class="text-xs text-slate-500 dark:text-white/45">
            <Transition name="set-fade" mode="out-in">
              <span v-if="tmdbKeySaved" key="saved" class="text-emerald-600 dark:text-emerald-400">{{ t('watchlist.settings.tmdbKeySavedMsg') }}</span>
              <span v-else key="hint">{{ t('watchlist.settings.tmdbKeyHint') }}</span>
            </Transition>
          </p>
        </div>

        <div v-for="s in availableSources" :key="s.id" class="set-row-static">
          <span class="flex-1 min-w-0 flex items-center gap-2">
            <span class="truncate">{{ s.label }}</span>
            <span v-if="s.pluginId" class="shrink-0 text-xs text-slate-500 dark:text-white/45">{{ pluginName(s.pluginId) }}</span>
            <span v-if="s.id === 'tmdb'" class="shrink-0 text-xs text-slate-500 dark:text-white/45">{{ t('watchlist.settings.alwaysOn') }}</span>
          </span>
          <button
            type="button"
            role="switch"
            :aria-checked="isSourceOn(s.id)"
            :aria-label="s.label"
            :disabled="s.id === 'tmdb'"
            :class="['set-switch', { 'is-on': isSourceOn(s.id) }]"
            @click="toggleSource(s.id)"
          >
            <span class="set-knob" />
          </button>
        </div>
      </section>
      <p class="set-foot">{{ t('watchlist.settings.searchSourceDesc') }}</p>

      <template v-if="availableSurfaces.length">
        <h2 class="set-heading">{{ t('watchlist.settings.tabExtras') }}</h2>
        <section class="lg-glass set-group">
          <div v-for="s in availableSurfaces" :key="s.pluginId" class="set-row-static flex-wrap">
            <span class="flex-1 min-w-0">
              <span class="block truncate">{{ t(s.label) }}</span>
              <span class="block text-xs text-slate-500 dark:text-white/45">{{ t('watchlist.settings.addedByPlugin', { name: pluginName(s.pluginId) }) }}</span>
            </span>
            <div class="inline-flex items-center gap-0.5 bg-black/[0.05] dark:bg-white/[0.07] rounded-xl p-1 shrink-0">
              <button
                v-for="where in placementOptions(s)"
                :key="where"
                type="button"
                :class="[
                  'cursor-pointer whitespace-nowrap px-3 py-1 rounded-lg text-xs font-medium transition-all',
                  placementOf(s) === where ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-white/55',
                ]"
                @click="setPlacement(s.pluginId, where)"
              >
                {{ t('watchlist.settings.placement.' + where) }}
              </button>
            </div>
          </div>
        </section>
        <p class="set-foot">{{ t('watchlist.settings.surfaceDesc') }}</p>
      </template>
  </PageShell>
</template>

<style scoped>
.set-heading {
  margin: 0 0 8px;
  padding: 0 16px;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: rgb(100 116 139);
}
.dark .set-heading { color: rgba(255, 255, 255, 0.45); }

.set-group {
  border-radius: 26px;
  overflow: hidden;
}

.set-foot {
  margin: 8px 0 28px;
  padding: 0 16px;
  font-size: 13px;
  line-height: 1.4;
  color: rgb(100 116 139);
}
.dark .set-foot { color: rgba(255, 255, 255, 0.45); }

.set-row,
.set-row-static {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  min-height: 52px;
  padding: 10px 16px;
  font-size: 16px;
}
.set-stack {
  flex-direction: column;
  align-items: stretch;
  gap: 10px;
  padding-top: 14px;
  padding-bottom: 14px;
}
.set-row { cursor: pointer; transition: background-color 0.15s ease; }
.set-row:active { background: rgba(15, 23, 42, 0.06); }
.dark .set-row:active { background: rgba(255, 255, 255, 0.07); }

.set-row + .set-row::before,
.set-row + .set-row-static::before,
.set-row-static + .set-row::before,
.set-row-static + .set-row-static::before {
  content: '';
  position: absolute;
  top: 0;
  left: 16px;
  right: 0;
  height: 1px;
  background: rgba(15, 23, 42, 0.08);
}
.dark .set-row + .set-row::before,
.dark .set-row + .set-row-static::before,
.dark .set-row-static + .set-row::before,
.dark .set-row-static + .set-row-static::before { background: rgba(255, 255, 255, 0.08); }

.set-icon {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 9px;
  flex-shrink: 0;
  color: #fff;
  background: linear-gradient(180deg, #818cf8, #6366f1);
}

.set-input,
.set-select {
  min-width: 0;
  border-radius: 12px;
  padding: 10px 12px;
  font-size: 16px;
  color: inherit;
  background: rgba(15, 23, 42, 0.05);
  border: 1px solid transparent;
  outline: none;
  transition: border-color 0.2s ease, background-color 0.2s ease;
}
.set-select { padding: 6px 10px; font-size: 14px; cursor: pointer; }
.dark .set-input,
.dark .set-select { background: rgba(255, 255, 255, 0.07); }
.set-input:focus { border-color: rgba(99, 102, 241, 0.6); }
.set-input::placeholder { color: rgb(148 163 184); }
.dark .set-input::placeholder { color: rgba(255, 255, 255, 0.35); }

.set-switch {
  position: relative;
  flex-shrink: 0;
  width: 51px;
  height: 31px;
  border-radius: 9999px;
  background: rgba(120, 120, 128, 0.32);
  cursor: pointer;
  transition: background-color 0.25s ease;
}
.set-switch.is-on { background: #34c759; }
.set-switch:disabled { opacity: 0.55; cursor: not-allowed; }
.set-knob {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 27px;
  height: 27px;
  border-radius: 9999px;
  background: #fff;
  box-shadow: 0 3px 8px rgba(0, 0, 0, 0.15), 0 1px 1px rgba(0, 0, 0, 0.16);
  transition: transform 0.3s cubic-bezier(0.22, 1, 0.36, 1);
}
.set-switch.is-on .set-knob { transform: translateX(20px); }

.set-fade-enter-active,
.set-fade-leave-active { transition: opacity 0.2s ease; }
.set-fade-enter-from,
.set-fade-leave-to { opacity: 0; }
</style>
