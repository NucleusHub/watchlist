<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { Icon, Spinner } from '@core/icons'
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
import ImportBackupModal from '@/components/ImportBackupModal.vue'
import ChoiceModal from '@/components/ChoiceModal.vue'
import { useReportSheet } from '@/composables/useReportSheet.js'
import { isNative, openExternal } from '@/native.js'
import { useNucleusId, ACCOUNT_DELETE_URL, PRIVACY_URL } from '@/auth/nucleusId.js'
import { useCloudSync } from '@/sync/cloudSync.js'
import { db, revision } from '@/storage/localDb.js'
import { exportBackup, readBackup, applyBackup } from '@/storage/backup.js'
import logo from '@/assets/nucleus-logo-transparent.png'
import tmdbLogo from '@/assets/tmdb-logo.svg'
import { collectDiagnostics } from '@/api/report.js'
import { useNativePlugins } from '@/plugins/runtime.js'

const { t, locale } = useI18n()
const { isPluginEnabled } = useRegistry()
const { defaults, setDefault, searchSources, setSearchSources, placementOf, setPlacement } = useOpenSettings()
const { plugins: installedPlugins, load: loadInstalledPlugins } = usePlugins()
onMounted(loadInstalledPlugins)
// Plugins installed from the marketplace on device aren't known to a home server.
const { installed: nativePlugins, nameOf: nativePluginName } = useNativePlugins()
const pluginName = (id) => installedPlugins.value.find((p) => p.id === id)?.name || nativePluginName(id) || id

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

// Account and data — only the iOS app keeps data on the device; inside
// Nucleus it lives on the home server and the Nucleus profile is the account.
const { account, isSignedIn, signingIn, error: authError, signIn, signOut } = useNucleusId()
const { status: syncStatus, lastError: syncError, lastSyncedAt, syncNow } = useCloudSync()
const confirmSignOut = ref(false)
const confirmSignIn = ref(false)

const accountInitial = computed(() => (account.value?.name || account.value?.handle || '?').trim().charAt(0).toUpperCase())
const authErrorText = computed(() => {
  if (!authError.value) return ''
  if (authError.value === 'expired') return t('watchlist.account.expired')
  if (authError.value === 'offline') return t('watchlist.account.offline')
  return t('watchlist.account.failed', { reason: authError.value })
})

const clock = ref(Date.now())
let clockTimer
onMounted(() => { clockTimer = setInterval(() => { clock.value = Date.now() }, 30000) })
onBeforeUnmount(() => clearInterval(clockTimer))
function relativeTime(iso) {
  const seconds = Math.round((Date.parse(iso) - clock.value) / 1000)
  if (seconds > -60) return t('watchlist.account.justNow')
  const rtf = new Intl.RelativeTimeFormat(locale.value || undefined, { numeric: 'auto' })
  for (const [unit, size] of [['day', 86400], ['hour', 3600], ['minute', 60]]) {
    if (Math.abs(seconds) >= size) return rtf.format(Math.round(seconds / size), unit)
  }
  return rtf.format(seconds, 'second')
}
const syncText = computed(() => {
  if (syncStatus.value === 'syncing') return t('watchlist.account.syncing')
  if (syncStatus.value === 'offline') return t('watchlist.account.syncOffline')
  if (syncStatus.value === 'error') {
    return syncError.value === 'tooLarge' ? t('watchlist.account.syncTooLarge') : t('watchlist.account.syncError', { reason: syncError.value })
  }
  return lastSyncedAt.value ? t('watchlist.account.syncedAt', { when: relativeTime(lastSyncedAt.value) }) : t('watchlist.account.notSynced')
})

// Nothing on the device means nothing to decide: just sign in.
function startSignIn() {
  if (deviceCounts.value.items || deviceCounts.value.collections) confirmSignIn.value = true
  else signIn()
}
function doSignIn(mode) {
  confirmSignIn.value = false
  signIn({ mode })
}
const signInOptions = computed(() => [
  { key: 'keep', icon: 'merge', tone: 'indigo', recommended: true, label: t('watchlist.account.signInKeep'), desc: t('watchlist.account.signInKeepDesc', deviceCounts.value) },
  { key: 'clean', icon: 'sparkle', tone: 'violet', label: t('watchlist.account.signInClean'), desc: t('watchlist.account.signInCleanDesc') },
])

async function doSignOut(mode) {
  confirmSignOut.value = false
  // Get the last changes into the account first — especially before the
  // device copy is thrown away.
  await syncNow()
  await signOut({ clean: mode === 'clean' })
}
const signOutOptions = computed(() => [
  { key: 'keep', icon: 'device', tone: 'indigo', recommended: true, label: t('watchlist.account.signOutKeep'), desc: t('watchlist.account.signOutKeepDesc') },
  { key: 'clean', icon: 'trash', tone: 'red', label: t('watchlist.account.signOutClean'), desc: t('watchlist.account.signOutCleanDesc') },
])

const deviceCounts = computed(() => {
  revision.value
  return { items: db().items.length, collections: db().collections.length }
})

const dataMessage = ref('')
const dataError = ref(false)
let dataTimer
function flash(message, isError = false) {
  dataMessage.value = message
  dataError.value = isError
  clearTimeout(dataTimer)
  dataTimer = setTimeout(() => { dataMessage.value = '' }, 4000)
}

const exporting = ref(false)
async function doExport() {
  exporting.value = true
  try {
    await exportBackup()
  } catch (err) {
    flash(t('watchlist.data.exportFailed', { reason: err.message }), true)
  } finally {
    exporting.value = false
  }
}

const fileInput = ref(null)
const pendingBackup = ref(null)
async function onFilePicked(e) {
  const file = e.target.files?.[0]
  e.target.value = ''
  if (!file) return
  try {
    pendingBackup.value = await readBackup(file)
  } catch {
    flash(t('watchlist.data.importInvalid'), true)
  }
}
function doImport(mode) {
  const { doc, items } = pendingBackup.value
  pendingBackup.value = null
  applyBackup(doc, mode)
  flash(t('watchlist.data.importDone', { items }))
}

const { open: reportOpen, shakeToReport, setShakeToReport } = useReportSheet()

// Deleting the account happens on the Nucleus site; the app only sends you
// there. Once it's gone the next token refresh fails and the app signs out.
const confirmDelete = ref(false)
const deleteOptions = computed(() => [
  { key: 'continue', icon: 'trash', tone: 'red', label: t('watchlist.account.deleteContinue'), desc: t('watchlist.account.deleteContinueDesc') },
])
function doDelete() {
  confirmDelete.value = false
  openExternal(ACCOUNT_DELETE_URL)
}

const version = ref('')
collectDiagnostics().then(({ app }) => {
  version.value = [app.version, app.build && `(${app.build})`].filter(Boolean).join(' ')
}).catch(() => {})
</script>

<template>
  <PageShell :title="t('watchlist.open.settingsTitle')">
      <template v-if="isNative">
        <h2 class="set-heading">{{ t('watchlist.account.heading') }}</h2>
        <section class="lg-glass set-group">
          <template v-if="isSignedIn">
            <div class="set-row-static">
              <span class="set-avatar">{{ accountInitial }}</span>
              <span class="flex-1 min-w-0">
                <span class="block truncate font-medium">{{ account?.name }}</span>
                <span class="block truncate text-sm text-slate-500 dark:text-white/45">@{{ account?.handle }} · Nucleus ID</span>
              </span>
            </div>
            <div class="set-row-static">
              <span :class="['set-icon', syncStatus === 'error' ? 'set-icon-warn' : '']">
                <Spinner v-if="syncStatus === 'syncing'" class="w-4 h-4 animate-spin" />
                <Icon v-else :name="syncStatus === 'error' ? 'warningTriangle' : 'uploadCloud'" class="w-[18px] h-[18px]" :sw="1.75" />
              </span>
              <span class="flex-1 min-w-0 text-sm text-slate-600 dark:text-white/70">{{ syncText }}</span>
              <button
                type="button"
                class="set-link"
                :disabled="syncStatus === 'syncing'"
                @click="syncNow"
              >{{ t('watchlist.account.syncNow') }}</button>
            </div>
            <button type="button" class="set-row text-red-600 dark:text-red-400" @click="confirmSignOut = true">
              <span class="flex-1 text-left">{{ t('watchlist.account.signOut') }}</span>
            </button>
            <button type="button" class="set-row text-red-600 dark:text-red-400" @click="confirmDelete = true">
              <span class="flex-1 text-left">{{ t('watchlist.account.delete') }}</span>
              <Icon name="externalLink" class="w-4 h-4 opacity-60" :sw="2" />
            </button>
          </template>
          <template v-else>
            <div class="set-row-static">
              <img :src="logo" alt="" class="w-[30px] h-[30px] shrink-0" />
              <span class="flex-1 min-w-0">
                <span class="block font-medium">Nucleus ID</span>
                <span class="block text-sm text-slate-500 dark:text-white/45">{{ t('watchlist.account.signedOutHint') }}</span>
              </span>
            </div>
            <button type="button" class="set-row" :disabled="signingIn" @click="startSignIn">
              <span class="flex-1 text-left font-medium text-indigo-600 dark:text-violet-300">{{ t('watchlist.account.signIn') }}</span>
              <Spinner v-if="signingIn" class="w-4 h-4 animate-spin text-slate-400" />
              <Icon v-else name="chevronRight" class="w-4 h-4 text-slate-400" :sw="2.5" />
            </button>
          </template>
        </section>
        <p v-if="authErrorText" class="set-foot text-red-600 dark:text-red-400">{{ authErrorText }}</p>
        <p v-else class="set-foot">{{ isSignedIn ? t('watchlist.account.signedInDesc') : t('watchlist.account.signedOutDesc') }}</p>

        <h2 class="set-heading">{{ t('watchlist.data.heading') }}</h2>
        <section class="lg-glass set-group">
          <button type="button" class="set-row" :disabled="exporting" @click="doExport">
            <span class="set-icon"><Icon name="download" class="w-[18px] h-[18px]" :sw="1.75" /></span>
            <span class="flex-1 text-left">{{ t('watchlist.data.export') }}</span>
            <Spinner v-if="exporting" class="w-4 h-4 animate-spin text-slate-400" />
          </button>
          <button type="button" class="set-row" @click="fileInput?.click()">
            <span class="set-icon"><Icon name="upload" class="w-[18px] h-[18px]" :sw="1.75" /></span>
            <span class="flex-1 text-left">{{ t('watchlist.data.import') }}</span>
          </button>
          <input ref="fileInput" type="file" accept="application/json,.json" class="hidden" @change="onFilePicked" />
        </section>
        <p :class="['set-foot', dataMessage && dataError ? 'text-red-600 dark:text-red-400' : '', dataMessage && !dataError ? 'text-emerald-600 dark:text-emerald-400' : '']">
          {{ dataMessage || t(isSignedIn ? 'watchlist.data.descSignedIn' : 'watchlist.data.desc', deviceCounts) }}
        </p>

        <ChoiceModal
          :show="confirmSignIn"
          :title="t('watchlist.account.signInTitle')"
          :message="t('watchlist.account.signInMessage')"
          :options="signInOptions"
          @choose="doSignIn"
          @close="confirmSignIn = false"
        />
        <ChoiceModal
          :show="confirmDelete"
          :title="t('watchlist.account.deleteTitle')"
          :message="t('watchlist.account.deleteMessage')"
          :options="deleteOptions"
          @choose="doDelete"
          @close="confirmDelete = false"
        />
        <ChoiceModal
          :show="confirmSignOut"
          :title="t('watchlist.account.signOutTitle')"
          :message="t('watchlist.account.signOutMessage')"
          :options="signOutOptions"
          @choose="doSignOut"
          @close="confirmSignOut = false"
        />
        <ImportBackupModal :backup="pendingBackup" @apply="doImport" @close="pendingBackup = null" />

        <h2 class="set-heading">{{ t('watchlist.plugins.title') }}</h2>
        <section class="lg-glass set-group">
          <RouterLink to="/settings/plugins" class="set-row">
            <span class="set-icon set-icon-plug">
              <svg class="w-[18px] h-[18px]" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 01-.657.643 48.39 48.39 0 01-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 01-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 00-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 01-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 00.657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 01-.349-1.003c0-1.035 1.008-1.875 2.25-1.875 1.243 0 2.25.84 2.25 1.875 0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 005.427-.63 48.05 48.05 0 00.582-4.717.532.532 0 00-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 00.658-.663 48.422 48.422 0 00-.37-5.36c-1.886.342-3.81.574-5.766.689a.578.578 0 01-.61-.58v0z" />
              </svg>
            </span>
            <span class="flex-1 text-left">{{ t('watchlist.plugins.settingsRow') }}</span>
            <span class="text-sm text-slate-500 dark:text-white/45">{{ nativePlugins.length ? t('watchlist.plugins.installedCount', { count: nativePlugins.length }) : '' }}</span>
            <Icon name="chevronRight" class="w-4 h-4 text-slate-400" :sw="2.5" />
          </RouterLink>
        </section>
        <p class="set-foot">{{ t('watchlist.plugins.settingsDesc') }}</p>
      </template>

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

      <h2 class="set-heading">{{ t('watchlist.report.heading') }}</h2>
      <section class="lg-glass set-group">
        <button type="button" class="set-row" @click="reportOpen = true">
          <span class="set-icon set-icon-report">
            <svg class="w-[18px] h-[18px]" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 12.75c1.148 0 2.278.08 3.383.237 1.037.146 1.866.966 1.866 2.013 0 3.728-2.35 6.75-5.25 6.75S6.75 18.728 6.75 15c0-1.046.83-1.867 1.866-2.013A24.204 24.204 0 0112 12.75zm0 0c2.883 0 5.647.508 8.207 1.44a23.91 23.91 0 01-1.152 6.06M12 12.75c-2.883 0-5.647.508-8.208 1.44.125 2.104.52 4.136 1.153 6.06M12 12.75a2.25 2.25 0 002.248-2.354M12 12.75a2.25 2.25 0 01-2.248-2.354M12 8.25c.995 0 1.971-.08 2.922-.236.403-.066.74-.358.795-.762a3.778 3.778 0 00-.399-2.25M12 8.25c-.995 0-1.97-.08-2.922-.236-.402-.066-.74-.358-.795-.762a3.734 3.734 0 01.4-2.253M12 8.25a2.25 2.25 0 00-2.248 2.146M12 8.25a2.25 2.25 0 012.248 2.146M8.683 5a6.032 6.032 0 01-1.155-1.002c.07-.63.27-1.222.574-1.747m.581 2.749A3.75 3.75 0 0115.318 5m0 0c.427-.283.815-.62 1.155-.999a4.471 4.471 0 00-.575-1.752M4.921 6a24.048 24.048 0 00-.392 3.314c1.668.546 3.416.914 5.223 1.082M19.08 6c.205 1.08.337 2.187.392 3.314a23.882 23.882 0 01-5.223 1.082" />
            </svg>
          </span>
          <span class="flex-1 text-left">{{ t('watchlist.report.row') }}</span>
          <Icon name="chevronRight" class="w-4 h-4 text-slate-400" :sw="2.5" />
        </button>
        <div v-if="isNative" class="set-row-static">
          <span class="flex-1">{{ t('watchlist.report.shakeToReport') }}</span>
          <button
            type="button"
            role="switch"
            :aria-checked="shakeToReport"
            :aria-label="t('watchlist.report.shakeToReport')"
            :class="['set-switch', { 'is-on': shakeToReport }]"
            @click="setShakeToReport(!shakeToReport)"
          >
            <span class="set-knob" />
          </button>
        </div>
      </section>
      <p class="set-foot">{{ t(isNative && shakeToReport ? 'watchlist.report.rowDescShake' : 'watchlist.report.rowDesc') }}</p>

      <h2 class="set-heading">{{ t('watchlist.about.heading') }}</h2>
      <section class="lg-glass set-group">
        <div class="set-row-static">
          <span class="flex-1">{{ t('watchlist.about.version') }}</span>
          <span class="text-slate-500 dark:text-white/45 tabular-nums">{{ version }}</span>
        </div>
        <button type="button" class="set-row" @click="openExternal(PRIVACY_URL)">
          <span class="flex-1 text-left">{{ t('watchlist.about.privacy') }}</span>
          <Icon name="externalLink" class="w-4 h-4 text-slate-400" :sw="2" />
        </button>
      </section>
      <div class="set-credit">
        <img :src="tmdbLogo" alt="TMDB" class="h-2 w-auto" />
        <p>{{ t('watchlist.about.tmdb') }}</p>
      </div>
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
.set-icon-plug { background: linear-gradient(180deg, #34d399, #10b981); }
.set-icon-warn { background: linear-gradient(180deg, #fbbf24, #f59e0b); }
.set-icon-report { background: linear-gradient(180deg, #fb7185, #f43f5e); }
.set-row:disabled { cursor: default; opacity: 0.6; }

.set-avatar {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 9999px;
  flex-shrink: 0;
  font-size: 17px;
  font-weight: 600;
  color: #fff;
  background: linear-gradient(135deg, #818cf8, #a855f7);
}

.set-link {
  flex-shrink: 0;
  font-size: 14px;
  font-weight: 500;
  color: rgb(79 70 229);
  cursor: pointer;
}
.dark .set-link { color: rgb(196 181 253); }
.set-link:disabled { opacity: 0.45; cursor: default; }

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

.set-credit {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  margin: 28px 0 12px;
  padding: 0 32px;
  text-align: center;
  font-size: 10.5px;
  line-height: 1.4;
  color: rgb(100 116 139);
}
.dark .set-credit { color: rgba(255, 255, 255, 0.4); }

.set-fade-enter-active,
.set-fade-leave-active { transition: opacity 0.2s ease; }
.set-fade-enter-from,
.set-fade-leave-to { opacity: 0; }
</style>
