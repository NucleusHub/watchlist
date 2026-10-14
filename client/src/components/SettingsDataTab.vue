<script setup>
import { ref, computed } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { exportBackup, importBackup } from '@/composables/useBackup.js'
import { verifyTMDbKey } from '@/api/tmdb.js'
import { parseBackup } from '@/utils/backup.js'
import { TMDB_KEY_URL } from '@/utils/about.js'

const { t } = useI18n()
const { tmdbApiKey, setTmdbApiKey } = useOpenSettings()

const key = ref('')
const checking = ref(false)
const problem = ref('')
const keySummary = computed(() => (tmdbApiKey.value ? `•••• ${tmdbApiKey.value.slice(-4)}` : t('watchlist.settings.keyNotSet')))

async function saveKey() {
  const candidate = key.value.trim().slice(0, 256)
  if (!candidate || checking.value) return
  checking.value = true
  problem.value = ''
  try {
    if (!(await verifyTMDbKey(candidate))) { problem.value = t('watchlist.settings.keyRejected'); return }
  } catch {
    // Offline: keep it anyway, it gets used as soon as there's a connection.
  }
  try {
    await setTmdbApiKey(candidate)
    key.value = ''
  } catch {
    problem.value = t('watchlist.settings.keySaveFailed')
  } finally {
    checking.value = false
  }
}

async function removeKey() {
  problem.value = ''
  try { await setTmdbApiKey('') } catch { problem.value = t('watchlist.settings.keySaveFailed') }
}

const busy = ref(false)
const flash = ref('')
const failed = ref(false)
const pending = ref(null)
const confirmingReplace = ref(false)

function say(message, bad = false) {
  flash.value = message
  failed.value = bad
}

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
    flash.value = ''
  } catch {
    say(t('watchlist.backup.notABackup'), true)
  }
}

async function apply(replace) {
  const file = pending.value
  busy.value = true
  try {
    const done = await importBackup(file, replace)
    pending.value = null
    say(t('watchlist.backup.imported', { count: done.items }) + (done.skipped ? ' ' + t('watchlist.backup.skipped', { count: done.skipped }) : ''))
    setTimeout(() => location.reload(), done.skipped ? 4000 : 1200)
  } catch {
    say(t('watchlist.backup.importFailed'), true)
  } finally {
    busy.value = false
  }
}

const exportedAt = computed(() => (pending.value?.exportedAt ? new Date(pending.value.exportedAt).toLocaleString() : ''))
const box = 'flex flex-col gap-3 rounded-xl border border-black/5 dark:border-white/10 bg-white/40 dark:bg-white/[0.03] p-4'
const input = 'flex-1 min-w-0 bg-white dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm font-mono placeholder:font-sans placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500'
const primary = 'cursor-pointer px-3 py-1.5 rounded-lg text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-default'
const quiet = 'cursor-pointer px-3 py-1.5 rounded-lg text-sm font-medium text-slate-600 dark:text-slate-300 bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15 transition-colors disabled:opacity-50 disabled:cursor-default'
</script>

<template>
  <div class="flex flex-col gap-4">
    <div :class="box">
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm font-semibold text-slate-900 dark:text-white">{{ t('watchlist.settings.tmdbKey') }}</span>
        <span class="text-xs font-mono text-slate-500 dark:text-slate-400">{{ keySummary }}</span>
      </div>
      <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.settings.tmdbKeyDesc') }}</p>
      <form class="flex gap-2" @submit.prevent="saveKey">
        <input v-model="key" type="text" autocomplete="off" spellcheck="false" :placeholder="t('watchlist.settings.keyPaste')" :class="input" @input="problem = ''" />
        <button type="submit" :disabled="!key.trim() || checking" :class="primary">{{ checking ? t('watchlist.settings.keyChecking') : t('watchlist.open.save') }}</button>
      </form>
      <p v-if="problem" class="text-sm text-red-500">{{ problem }}</p>
      <div class="flex items-center gap-4 text-sm">
        <a :href="TMDB_KEY_URL" target="_blank" rel="noopener" class="text-indigo-600 dark:text-indigo-400 hover:underline">{{ t('watchlist.settings.keyGet') }} ↗</a>
        <button v-if="tmdbApiKey" type="button" class="cursor-pointer text-red-500 hover:underline" @click="removeKey">{{ t('watchlist.settings.keyRemove') }}</button>
      </div>
    </div>

    <div :class="box">
      <span class="text-sm font-semibold text-slate-900 dark:text-white">{{ t('watchlist.backup.title') }}</span>
      <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('watchlist.backup.desc') }}</p>

      <div v-if="pending" class="flex flex-col gap-3 rounded-lg bg-black/[0.03] dark:bg-black/20 border border-black/5 dark:border-white/10 p-3">
        <p class="text-sm text-slate-700 dark:text-slate-200">
          {{ t('watchlist.backup.contents', { items: pending.items.length, collections: pending.collections.length }) }}
          <span v-if="exportedAt" class="text-slate-400 dark:text-slate-500">{{ t('watchlist.backup.exportedAt', { date: exportedAt }) }}</span>
        </p>
        <p v-if="confirmingReplace" class="text-sm text-red-500">{{ t('watchlist.backup.replaceWarning') }}</p>
        <div class="flex flex-wrap gap-2">
          <template v-if="!confirmingReplace">
            <button type="button" :disabled="busy" :class="primary" @click="apply(false)">{{ t('watchlist.backup.merge') }}</button>
            <button type="button" :disabled="busy" :class="quiet" @click="confirmingReplace = true">{{ t('watchlist.backup.replace') }}</button>
          </template>
          <button v-else type="button" :disabled="busy" class="cursor-pointer px-3 py-1.5 rounded-lg text-sm font-medium text-white bg-red-600 hover:bg-red-500 transition-colors disabled:opacity-50" @click="apply(true)">{{ t('watchlist.backup.replaceConfirm') }}</button>
          <button type="button" :disabled="busy" :class="quiet" @click="pending = null">{{ t('watchlist.open.cancel') }}</button>
        </div>
      </div>
      <div v-else class="flex flex-wrap gap-2">
        <button type="button" :disabled="busy" :class="primary" @click="doExport">{{ t('watchlist.backup.export') }}</button>
        <label :class="[quiet, 'inline-block']">
          {{ t('watchlist.backup.import') }}
          <input type="file" accept="application/json,.json" class="sr-only" @change="pickFile" />
        </label>
      </div>
      <p v-if="flash" :class="['text-sm', failed ? 'text-red-500' : 'text-emerald-600 dark:text-emerald-400']">{{ flash }}</p>
    </div>
  </div>
</template>
