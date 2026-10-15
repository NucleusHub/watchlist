<script setup>
// Settings as a page of glass sections, laid out like the iOS SettingsView.
import { ref, computed, onMounted } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { useTheme } from '@core/useTheme.js'
import { getItems } from '@/api/watchlist.js'
import { BUILTIN_SOURCES, PLUGIN_SOURCES } from '@/api/sources.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { useCollections } from '@/composables/useCollections.js'
import { useMovieDNA } from '@/composables/useMovieDNA.js'
import { useMetadataRefresh } from '@/composables/useMetadataRefresh.js'
import { exportBackup, importBackup } from '@/composables/useBackup.js'
import { parseBackup } from '@/utils/backup.js'
import { movieDNAUses, watchlistSurfaces } from '@/utils/pluginSurfaces.js'
import { PRESETS, HEX } from '@/utils/accent.js'
import { APP_VERSION, PRIVACY_URL, TMDB_KEY_URL } from '@/utils/about.js'
import { openTour } from '@/composables/useTour.js'
import ReportModal from '@/components/ReportModal.vue'
import PageShell from '@/ui/PageShell.vue'
import WlSection from '@/ui/WlSection.vue'
import WlRow from '@/ui/WlRow.vue'
import IconTile from '@/ui/IconTile.vue'
import DnaGlyph from '@/ui/DnaGlyph.vue'
import SegmentPills from '@/ui/SegmentPills.vue'

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const { theme, setTheme } = useTheme()
const { defaults, searchSources, tmdbApiKey, accent, setAccent } = useOpenSettings()
const { collections } = useCollections()
const dna = useMovieDNA()
const refresh = useMetadataRefresh()

const items = ref([])
onMounted(async () => {
  items.value = await getItems().catch(() => [])
})

const openLabel = (kind) => (defaults[kind].type === 'custom' ? t('watchlist.open.custom') : t(`watchlist.open.${defaults[kind].type}`))
const sources = computed(() => [...BUILTIN_SOURCES, ...PLUGIN_SOURCES.filter((s) => isPluginEnabled(s.pluginId))])
const sourcesSummary = computed(() => sources.value.filter((s) => s.id === 'tmdb' || searchSources.value.includes(s.id)).map((s) => s.label).join(' · '))
const watchlistPlugins = computed(() => watchlistSurfaces.filter((s) => isPluginEnabled(s.pluginId)).length)
const keySummary = computed(() => (tmdbApiKey.value ? `•••• ${tmdbApiKey.value.slice(-4)}` : t('watchlist.settings.keyNotSet')))
const dnaSummary = computed(() => {
  if (!dna.settings.value.enabled) return t('watchlist.settings.off')
  return movieDNAUses.some((u) => isPluginEnabled(u.pluginId)) ? t('watchlist.settings.on') : t('watchlist.settings.dnaUnused')
})

const THEMES = computed(() => ['system', 'light', 'dark'].map((key) => ({ key, label: t(`watchlist.settings.theme.${key}`) })))

const customHex = ref(accent.value?.id === 'custom' && HEX.test(accent.value.custom) ? accent.value.custom : '#A855F7')
const isPicked = (id) => (accent.value?.id ?? 'nucleus') === id
const pickCustom = (e) => {
  customHex.value = e.target.value.toUpperCase()
  setAccent({ id: 'custom', custom: customHex.value })
}

// Backup
const flash = ref('')
const failed = ref(false)
const busy = ref(false)
const pending = ref(null)
const confirmingReplace = ref(false)
const fileInput = ref(null)
const say = (message, bad = false) => { flash.value = message; failed.value = bad }

async function doExport() {
  busy.value = true
  try {
    const n = await exportBackup()
    say(t('watchlist.backup.exported', { items: n.items, collections: n.collections }))
  } catch {
    say(t('watchlist.backup.exportFailed'), true)
  } finally {
    busy.value = false
  }
}
async function pickFile(e) {
  const file = e.target.files[0]
  e.target.value = ''
  if (!file) return
  try {
    pending.value = parseBackup(await file.text())
    confirmingReplace.value = false
  } catch {
    say(t('watchlist.backup.notABackup'), true)
  }
}
async function applyImport(replace) {
  const file = pending.value
  busy.value = true
  try {
    const done = await importBackup(file, replace)
    pending.value = null
    say(t('watchlist.backup.imported', { count: done.items }) + (done.skipped ? ' ' + t('watchlist.backup.skipped', { count: done.skipped }) : ''))
    setTimeout(() => location.reload(), done.skipped ? 4000 : 1200)
  } catch {
    pending.value = null
    say(t('watchlist.backup.importFailed'), true)
  } finally {
    busy.value = false
  }
}
const exportedAt = computed(() => (pending.value?.exportedAt ? new Date(pending.value.exportedAt).toLocaleString() : ''))

// Refresh from TMDb
const askingRefresh = ref(false)
const refreshSeconds = computed(() => Math.max(1, Math.round(items.value.length * 0.8)))
function startRefresh() {
  askingRefresh.value = false
  refresh.run(items.value)
}

const showReport = ref(false)
</script>

<template>
  <PageShell :title="t('watchlist.header.settings')">
    <WlSection :title="t('watchlist.settings.data')" :footer="flash || t('watchlist.settings.dataFoot', { items: items.length, collections: collections.length })">
      <WlRow to="/settings/moviedna" :title="t('watchlist.dna.title')" :subtitle="dnaSummary" chevron>
        <template #icon>
          <IconTile tint="rose"><template #default="{ size }"><DnaGlyph :style="{ width: size, height: size }" /></template></IconTile>
        </template>
      </WlRow>
      <WlRow button :disabled="busy" icon="exportUp" tint="sky" :title="t('watchlist.backup.export')" chevron @click="doExport" />
      <WlRow button :disabled="busy" icon="importDown" tint="teal" :title="t('watchlist.backup.import')" chevron @click="fileInput.click()" />
      <WlRow
        button
        :disabled="!tmdbApiKey || !items.length || refresh.state.running"
        icon="sparkles"
        tint="amber"
        :title="t('watchlist.settings.refreshTitle')"
        chevron
        @click="askingRefresh = true"
      />
    </WlSection>
    <input ref="fileInput" type="file" accept="application/json,.json" class="sr-only" @change="pickFile" />

    <WlSection :title="t('watchlist.settings.titles')" :footer="t('watchlist.settings.titlesFoot')">
      <WlRow to="/settings/open" icon="openExternal" tint="violet" :title="t('watchlist.settings.openOnClick')" :subtitle="`${openLabel('movie')} · ${openLabel('show')}`" chevron />
      <WlRow v-if="sources.length > 1" to="/settings/sources" icon="magnifier" tint="blue" :title="t('watchlist.settings.tabSources')" :subtitle="sourcesSummary" chevron />
      <WlRow to="/settings/plugins" icon="puzzle" tint="indigo" :title="t('watchlist.settings.plugins')" :subtitle="t('watchlist.settings.pluginsCount', { count: watchlistPlugins })" chevron />
      <WlRow to="/settings/tmdb" icon="key" tint="amber" :title="t('watchlist.settings.tmdbKey')" :subtitle="keySummary" chevron />
      <WlRow :href="TMDB_KEY_URL" icon="globe" tint="blue" :title="t('watchlist.settings.keyGet')" />
    </WlSection>

    <WlSection :title="t('watchlist.settings.tabAppearance')" :footer="t('watchlist.settings.accentDesc')">
      <div class="p-3">
        <SegmentPills :model-value="theme" :items="THEMES" fill @update:model-value="setTheme" />
      </div>
      <div class="flex flex-wrap items-center gap-3 px-4 py-4">
        <button
          v-for="p in PRESETS"
          :key="p.id"
          type="button"
          :title="t('watchlist.settings.accent.' + p.id)"
          :aria-pressed="isPicked(p.id)"
          :class="['nuc-press cursor-pointer w-9 h-9 rounded-full transition-transform', isPicked(p.id) ? 'ring-2 ring-offset-2 ring-[var(--wl-text)] ring-offset-[var(--wl-base)]' : 'hover:scale-110']"
          :style="{ background: p.hex }"
          @click="setAccent({ id: p.id })"
        />
        <label
          :title="t('watchlist.settings.accent.custom')"
          :class="['nuc-press cursor-pointer relative w-9 h-9 rounded-full overflow-hidden transition-transform', isPicked('custom') ? 'ring-2 ring-offset-2 ring-[var(--wl-text)] ring-offset-[var(--wl-base)]' : 'hover:scale-110']"
          :style="{ background: isPicked('custom') ? customHex : 'conic-gradient(#f43f5e, #f59e0b, #10b981, #3b82f6, #a855f7, #f43f5e)' }"
        >
          <input type="color" :value="customHex" class="absolute inset-0 opacity-0 cursor-pointer" @change="pickCustom" />
        </label>
      </div>
    </WlSection>

    <WlSection :title="t('watchlist.settings.tabHelp')">
      <WlRow button icon="map" tint="violet" :title="t('watchlist.settings.takeTour')" chevron @click="openTour" />
      <WlRow button icon="flag" tint="rose" :title="t('watchlist.settings.reportProblem')" chevron @click="showReport = true" />
    </WlSection>

    <WlSection :title="t('watchlist.about.title')">
      <WlRow :title="t('watchlist.about.version')">
        <template #trailing><span class="text-[var(--wl-text-2)] font-mono text-sm">{{ APP_VERSION || '—' }}</span></template>
      </WlRow>
      <WlRow :href="PRIVACY_URL" :title="t('watchlist.about.privacy')" />
      <div class="px-4 py-4 flex flex-col gap-2">
        <a href="https://www.themoviedb.org" target="_blank" rel="noopener" class="self-start text-[13px] font-extrabold tracking-wide bg-gradient-to-r from-[#90cea1] to-[#01b4e4] bg-clip-text text-transparent no-underline">TMDB</a>
        <p class="text-xs text-[var(--wl-text-2)]">{{ t('watchlist.about.tmdb') }}</p>
      </div>
    </WlSection>
  </PageShell>

  <TemplateModal
    :show="!!pending"
    :title="t('watchlist.backup.import')"
    header
    size="xs"
    body-class="px-5 sm:px-6 pb-5 pt-3"
    @cancel="pending = null"
  >
    <div class="flex flex-col gap-2">
      <p class="text-sm text-[var(--wl-text-2)]">{{ t('watchlist.backup.contents', { items: pending?.items.length ?? 0, collections: pending?.collections.length ?? 0 }) }} {{ exportedAt && t('watchlist.backup.exportedAt', { date: exportedAt }) }}</p>
      <p v-if="confirmingReplace" class="text-sm text-[var(--wl-danger)]">{{ t('watchlist.backup.replaceWarning') }}</p>
      <template v-if="!confirmingReplace">
        <button type="button" :disabled="busy" class="wl-btn wl-btn-primary" @click="applyImport(false)">{{ t('watchlist.backup.merge') }}</button>
        <button type="button" :disabled="busy" class="wl-btn wl-btn-secondary !text-[var(--wl-danger)]" @click="confirmingReplace = true">{{ t('watchlist.backup.replace') }}</button>
      </template>
      <button v-else type="button" :disabled="busy" class="wl-btn wl-btn-danger" @click="applyImport(true)">{{ t('watchlist.backup.replaceConfirm') }}</button>
    </div>
  </TemplateModal>

  <TemplateModal
    :show="askingRefresh"
    :title="t('watchlist.refresh.warningTitle')"
    :message="t('watchlist.settings.refreshBody', { count: items.length, seconds: refreshSeconds })"
    :confirm-label="t('watchlist.refresh.confirm')"
    confirm-variant="primary"
    @confirm="startRefresh"
    @cancel="askingRefresh = false"
  />

  <TemplateModal
    :show="refresh.state.running || refresh.state.finished"
    header
    :closeable="false"
    size="xs"
    :title="refresh.state.finished ? (refresh.state.cancelled ? t('watchlist.refresh.cancelled') : t('watchlist.refresh.done')) : t('watchlist.refresh.running')"
    body-class="px-6 pt-4 pb-6"
  >
    <div class="flex flex-col gap-4">
      <div class="h-1.5 rounded-full bg-[var(--wl-well)] overflow-hidden">
        <div class="h-full rounded-full bg-[var(--wl-accent)] transition-all duration-300" :style="{ width: `${refresh.state.total ? (refresh.state.done / refresh.state.total) * 100 : 0}%` }" />
      </div>
      <p class="text-sm text-center tabular-nums text-[var(--wl-text-2)]">
        <template v-if="refresh.state.finished">{{ t('watchlist.refresh.updated', { done: refresh.state.done - refresh.state.failed, total: refresh.state.total }) }}{{ refresh.state.failed ? t('watchlist.refresh.notFound', { count: refresh.state.failed }) : '' }}</template>
        <template v-else>{{ t('watchlist.refresh.progress', { current: refresh.state.done, total: refresh.state.total }) }}</template>
      </p>
      <button type="button" class="wl-btn wl-btn-secondary" @click="refresh.state.running ? refresh.cancel() : refresh.close()">
        {{ refresh.state.running ? t('watchlist.refresh.cancel') : t('watchlist.refresh.close') }}
      </button>
    </div>
  </TemplateModal>

  <ReportModal :show="showReport" @close="showReport = false" />
</template>
