<script setup>
import { ref, computed, onMounted } from 'vue'
import { Spinner } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import PageShell from '@/layouts/PageShell.vue'
import ChoiceModal from '@/components/ChoiceModal.vue'
import { haptic } from '@/native.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { PLUGIN_SOURCES } from '@/api/sources.js'
import { fetchCatalogue, install, uninstall, hasUpdate, useNativePlugins } from '@/plugins/runtime.js'

// The in-app Nucleus Marketplace: plugins this app can download and run.
const { t } = useI18n()
const { installed, problems } = useNativePlugins()
const { searchSources, setSearchSources } = useOpenSettings()

const catalogue = ref([])
const loading = ref(true)
const loadError = ref('')
const busy = ref({}) // id → 'install' | 'update' | 'remove'
const notice = ref(null) // { text, error }
let noticeTimer

async function load() {
  loading.value = true
  loadError.value = ''
  try {
    catalogue.value = await fetchCatalogue()
  } catch (err) {
    loadError.value = err instanceof TypeError ? t('watchlist.plugins.offline') : err.message
  } finally {
    loading.value = false
  }
}
onMounted(load)

const isInstalled = (id) => installed.value.some((p) => p.id === id)
const listingOf = (id) => catalogue.value.find((p) => p.id === id)
const available = computed(() => catalogue.value.filter((p) => !isInstalled(p.id)))

function flash(text, error = false) {
  notice.value = { text, error }
  clearTimeout(noticeTimer)
  noticeTimer = setTimeout(() => { notice.value = null }, 4000)
}

async function run(id, kind, fn) {
  busy.value = { ...busy.value, [id]: kind }
  try {
    await fn()
  } finally {
    const { [id]: _, ...rest } = busy.value
    busy.value = rest
  }
}

function get(listing, kind = 'install') {
  haptic('Light')
  return run(listing.id, kind, async () => {
    try {
      const sourceIds = await install(listing)
      // A new search source is only useful switched on.
      if (sourceIds.length) setSearchSources([...searchSources.value, ...sourceIds])
      flash(t(kind === 'update' ? 'watchlist.plugins.updated' : 'watchlist.plugins.installed', { name: listing.name }))
    } catch (err) {
      flash(t('watchlist.plugins.installFailed', { name: listing.name, reason: err.message }), true)
    }
  })
}

const removing = ref(null)
async function confirmRemove(choice) {
  const plugin = removing.value
  removing.value = null
  if (choice !== 'remove' || !plugin) return
  const sourceIds = PLUGIN_SOURCES.filter((s) => s.pluginId === plugin.id).map((s) => s.id)
  await run(plugin.id, 'remove', async () => {
    await uninstall(plugin.id)
    if (sourceIds.length) setSearchSources(searchSources.value.filter((id) => !sourceIds.includes(id)))
  })
  flash(t('watchlist.plugins.removed', { name: plugin.name }))
}
const removeOptions = computed(() => [
  { key: 'remove', icon: 'trash', tone: 'red', label: t('watchlist.plugins.remove'), desc: t('watchlist.plugins.removeDesc') },
])

// Plugin icons are line icons drawn in currentColor: used as a mask, they
// take the tile's white and can't carry anything that runs.
const maskOf = (svg) => (svg ? `url("data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}")` : null)
function tileStyle(plugin) {
  let h = 0
  for (const c of plugin.id) h = (h * 31 + c.charCodeAt(0)) % 360
  return { background: `linear-gradient(145deg, hsl(${h} 85% 64%), hsl(${(h + 40) % 360} 80% 52%))` }
}
</script>

<template>
  <PageShell :title="t('watchlist.plugins.title')" fallback="/settings">
    <p class="pl-intro">{{ t('watchlist.plugins.intro') }}</p>

    <Transition name="pl-fade">
      <p v-if="notice" :class="['pl-notice', notice.error ? 'is-error' : '']">{{ notice.text }}</p>
    </Transition>

    <template v-if="installed.length">
      <h2 class="pl-heading">{{ t('watchlist.plugins.installedHeading') }}</h2>
      <section class="lg-glass pl-group">
        <div v-for="p in installed" :key="p.id" class="pl-row">
          <span class="pl-tile" :style="tileStyle(p)">
            <span v-if="p.iconSvg" class="pl-glyph" :style="{ maskImage: maskOf(p.iconSvg), WebkitMaskImage: maskOf(p.iconSvg) }" />
            <span v-else class="pl-letter">{{ p.name.charAt(0) }}</span>
          </span>
          <span class="pl-text">
            <span class="pl-name">{{ p.name }}</span>
            <span class="pl-meta">v{{ p.version }}<template v-if="p.author?.name"> · {{ p.author.name }}</template></span>
            <span v-if="problems[p.id]" class="pl-problem">{{ t('watchlist.plugins.loadFailed', { reason: problems[p.id] }) }}</span>
          </span>
          <Spinner v-if="busy[p.id]" class="w-5 h-5 animate-spin text-slate-400" />
          <button
            v-else-if="listingOf(p.id) && hasUpdate(listingOf(p.id))"
            type="button"
            class="pl-pill"
            @click="get(listingOf(p.id), 'update')"
          >{{ t('watchlist.plugins.update') }}</button>
          <button v-else type="button" class="pl-pill pl-pill--quiet" @click="removing = p">{{ t('watchlist.plugins.removeShort') }}</button>
        </div>
      </section>
    </template>

    <h2 class="pl-heading">{{ t('watchlist.plugins.marketplaceHeading') }}</h2>
    <section class="lg-glass pl-group">
      <template v-if="loading">
        <div v-for="n in 2" :key="n" class="pl-row" aria-hidden="true">
          <span class="pl-tile pl-skeleton" />
          <span class="pl-text">
            <span class="pl-skeleton-line w-2/5" />
            <span class="pl-skeleton-line w-4/5 mt-2" />
          </span>
        </div>
      </template>

      <div v-else-if="loadError" class="pl-empty">
        <p>{{ loadError }}</p>
        <button type="button" class="pl-pill mt-3" @click="load">{{ t('watchlist.plugins.retry') }}</button>
      </div>

      <p v-else-if="!available.length" class="pl-empty">
        {{ catalogue.length ? t('watchlist.plugins.allInstalled') : t('watchlist.plugins.none') }}
      </p>

      <template v-else>
      <div v-for="p in available" :key="p.id" class="pl-row pl-row--listing">
        <span class="pl-tile" :style="tileStyle(p)">
          <span v-if="p.iconSvg" class="pl-glyph" :style="{ maskImage: maskOf(p.iconSvg), WebkitMaskImage: maskOf(p.iconSvg) }" />
          <span v-else class="pl-letter">{{ p.name.charAt(0) }}</span>
        </span>
        <span class="pl-text">
          <span class="pl-name">
            {{ p.name }}
            <span v-if="p.official" class="pl-badge">{{ t('watchlist.plugins.official') }}</span>
          </span>
          <span class="pl-desc">{{ p.description || p.tagline }}</span>
        </span>
        <Spinner v-if="busy[p.id]" class="pl-spin w-5 h-5 animate-spin text-slate-400 shrink-0" />
        <button v-else type="button" class="pl-pill" @click="get(p)">{{ t('watchlist.plugins.get') }}</button>
      </div>
      </template>
    </section>
    <p class="pl-foot">{{ t('watchlist.plugins.foot') }}</p>

    <ChoiceModal
      :show="!!removing"
      :title="t('watchlist.plugins.removeTitle', { name: removing?.name || '' })"
      :message="t('watchlist.plugins.removeMessage')"
      :options="removeOptions"
      @choose="confirmRemove"
      @close="removing = null"
    />
  </PageShell>
</template>

<style scoped>
.pl-intro {
  margin: -12px 4px 24px;
  font-size: 15px;
  line-height: 1.45;
  color: rgb(100 116 139);
}
.dark .pl-intro { color: rgba(255, 255, 255, 0.55); }

.pl-heading {
  margin: 0 0 8px;
  padding: 0 16px;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: rgb(100 116 139);
}
.dark .pl-heading { color: rgba(255, 255, 255, 0.45); }

.pl-group { border-radius: 26px; overflow: hidden; margin-bottom: 28px; }

.pl-row {
  position: relative;
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 16px;
}
.pl-row--listing { align-items: flex-start; }
.pl-row--listing .pl-pill, .pl-row--listing .pl-spin { margin-top: 10px; }
.pl-row + .pl-row::before {
  content: '';
  position: absolute;
  top: 0;
  left: 76px;
  right: 0;
  height: 1px;
  background: rgba(15, 23, 42, 0.08);
}
.dark .pl-row + .pl-row::before { background: rgba(255, 255, 255, 0.08); }

.pl-tile {
  position: relative;
  display: grid;
  place-items: center;
  width: 48px;
  height: 48px;
  border-radius: 14px;
  flex-shrink: 0;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), 0 4px 12px rgba(15, 23, 42, 0.12);
}
.pl-glyph {
  width: 26px;
  height: 26px;
  background: #fff;
  mask-size: contain;
  mask-repeat: no-repeat;
  mask-position: center;
  -webkit-mask-size: contain;
  -webkit-mask-repeat: no-repeat;
  -webkit-mask-position: center;
}
.pl-letter { font-size: 20px; font-weight: 700; color: #fff; }

.pl-text { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.pl-name {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  font-size: 16px;
  font-weight: 600;
}
.pl-meta, .pl-desc {
  margin-top: 2px;
  font-size: 13px;
  line-height: 1.4;
  color: rgb(100 116 139);
}
.dark .pl-meta, .dark .pl-desc { color: rgba(255, 255, 255, 0.5); }
.pl-desc {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.pl-problem { margin-top: 4px; font-size: 12px; color: #dc2626; }
.dark .pl-problem { color: #f87171; }

.pl-badge {
  padding: 1px 7px;
  border-radius: 9999px;
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #4f46e5;
  background: rgba(99, 102, 241, 0.12);
}
.dark .pl-badge { color: #c7d2fe; background: rgba(129, 140, 248, 0.18); }

.pl-pill {
  flex-shrink: 0;
  min-width: 72px;
  padding: 6px 16px;
  border-radius: 9999px;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  cursor: pointer;
  color: #4f46e5;
  background: rgba(99, 102, 241, 0.12);
  transition: transform 0.15s ease, background-color 0.15s ease;
}
.pl-pill:active { transform: scale(0.94); background: rgba(99, 102, 241, 0.2); }
.dark .pl-pill { color: #c7d2fe; background: rgba(129, 140, 248, 0.18); }
.pl-pill--quiet {
  text-transform: none;
  font-weight: 600;
  letter-spacing: 0;
  color: rgb(100 116 139);
  background: rgba(15, 23, 42, 0.06);
}
.dark .pl-pill--quiet { color: rgba(255, 255, 255, 0.6); background: rgba(255, 255, 255, 0.08); }

.pl-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 28px 20px;
  text-align: center;
  font-size: 14px;
  color: rgb(100 116 139);
}
.dark .pl-empty { color: rgba(255, 255, 255, 0.5); }

.pl-skeleton, .pl-skeleton-line {
  background: rgba(15, 23, 42, 0.08);
  box-shadow: none;
  animation: pl-pulse 1.4s ease-in-out infinite;
}
.pl-skeleton-line { display: block; height: 10px; border-radius: 9999px; }
.dark .pl-skeleton, .dark .pl-skeleton-line { background: rgba(255, 255, 255, 0.08); }

.pl-foot {
  margin: -20px 0 28px;
  padding: 0 16px;
  font-size: 13px;
  line-height: 1.4;
  color: rgb(100 116 139);
}
.dark .pl-foot { color: rgba(255, 255, 255, 0.45); }

.pl-notice {
  margin: 0 0 16px;
  padding: 10px 14px;
  border-radius: 14px;
  font-size: 14px;
  color: #065f46;
  background: rgba(16, 185, 129, 0.12);
}
.pl-notice.is-error { color: #991b1b; background: rgba(239, 68, 68, 0.12); }
.dark .pl-notice { color: #a7f3d0; }
.dark .pl-notice.is-error { color: #fecaca; }

.pl-fade-enter-active, .pl-fade-leave-active { transition: opacity 0.2s ease; }
.pl-fade-enter-from, .pl-fade-leave-to { opacity: 0; }

@keyframes pl-pulse { 50% { opacity: 0.5; } }
@media (prefers-reduced-motion: reduce) {
  .pl-skeleton, .pl-skeleton-line { animation: none; }
}
</style>
