import { ref, readonly } from 'vue'
import { isNative } from '@/native.js'
import { readJson, writeJson, remove } from '@/storage/persist.js'
import { db, replaceDoc, clearData, mergeDocs, fingerprint, normalizeDoc, onLocalChange } from '@/storage/localDb.js'
import { nucleusFetch, useNucleusId, onSignedIn, onSignedOut } from '@/auth/nucleusId.js'

// Keeps the device database and the copy in the person's Nucleus ID account
// (one app-data key) in step. The device stays the working copy — the app
// works offline, and a sync is: fetch, merge (localDb.mergeDocs), write back
// with If-Match so a write from another device in between is merged too
// instead of overwritten.
const REMOTE_KEY = 'watchlist'
const STATE_KEY = 'watchlist-sync'
const PUSH_DELAY_MS = 1500
const MAX_ATTEMPTS = 4

const status = ref('idle') // idle | syncing | error | offline
const lastError = ref('')
const lastSyncedAt = ref(null)

let remoteVersion = null
let dirty = false
let pushTimer = null
let running = null
let again = false

const { isSignedIn } = useNucleusId()

async function saveState() {
  await writeJson(STATE_KEY, { version: remoteVersion, lastSyncedAt: lastSyncedAt.value, dirty })
}

const path = `/api/v1/app-data/${REMOTE_KEY}`

async function fetchRemote(ifNoneMatch) {
  const res = await nucleusFetch(path, { headers: ifNoneMatch ? { 'If-None-Match': `"${ifNoneMatch}"` } : {} })
  if (res.status === 304) return { unchanged: true }
  if (res.status === 404) return { value: null, version: null }
  if (!res.ok) throw await failure(res)
  const body = await res.json()
  return { value: body.value, version: body.version }
}

async function pushRemote(value, version) {
  const headers = { 'Content-Type': 'application/json' }
  if (version) headers['If-Match'] = `"${version}"`
  else headers['If-None-Match'] = '*'
  const res = await nucleusFetch(path, { method: 'PUT', headers, body: JSON.stringify({ value }) })
  if (res.status === 412) return { conflict: true }
  if (!res.ok) throw await failure(res)
  return { version: (await res.json()).version }
}

async function failure(res) {
  const body = await res.json().catch(() => ({}))
  const err = new Error(body.message || body.error?.message || body.error_description || `HTTP ${res.status}`)
  err.status = res.status
  return err
}

async function runSync() {
  // Nothing changed here and the account copy is still the version we last
  // saw: a cheap 304 and we're done.
  if (!dirty && remoteVersion) {
    const probe = await fetchRemote(remoteVersion)
    if (probe.unchanged) return
  }
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const remote = await fetchRemote()
    const local = db()
    const merged = remote.value ? mergeDocs(local, remote.value) : normalizeDoc(local)
    const localChanged = fingerprint(merged) !== fingerprint(local)
    if (localChanged) replaceDoc(merged, { silent: true })
    if (remote.value && fingerprint(merged) === fingerprint(normalizeDoc(remote.value))) {
      remoteVersion = remote.version
      return
    }
    const pushed = await pushRemote(merged, remote.version)
    if (!pushed.conflict) {
      remoteVersion = pushed.version
      return
    }
  }
  throw new Error('conflict')
}

export function syncNow() {
  if (!isSignedIn.value) return Promise.resolve()
  clearTimeout(pushTimer)
  if (running) {
    again = true
    return running
  }
  running = (async () => {
    status.value = 'syncing'
    const wasDirty = dirty
    dirty = false
    try {
      await runSync()
      lastSyncedAt.value = new Date().toISOString()
      lastError.value = ''
      status.value = 'idle'
    } catch (err) {
      dirty = dirty || wasDirty
      if (!isSignedIn.value) status.value = 'idle'
      else if (err instanceof TypeError || err.code === 'offline') status.value = 'offline'
      else {
        status.value = 'error'
        lastError.value = err.status === 413 ? 'tooLarge' : err.message
      }
    } finally {
      await saveState()
      running = null
      if (again) {
        again = false
        syncNow()
      }
    }
  })()
  return running
}

function schedulePush() {
  dirty = true
  saveState()
  if (!isSignedIn.value) return
  clearTimeout(pushTimer)
  pushTimer = setTimeout(syncNow, PUSH_DELAY_MS)
}

let initialized = false
export async function initCloudSync() {
  if (initialized || !isNative) return
  initialized = true
  const saved = await readJson(STATE_KEY)
  remoteVersion = saved?.version ?? null
  lastSyncedAt.value = saved?.lastSyncedAt ?? null
  dirty = !!saved?.dirty

  onLocalChange(schedulePush)
  onSignedIn(async (_user, { mode }) => {
    remoteVersion = null
    // Starting clean: nothing from this device goes up, the account's copy comes down.
    if (mode === 'clean') clearData()
    dirty = mode !== 'clean'
    await syncNow()
  })
  onSignedOut(async ({ clean }) => {
    clearTimeout(pushTimer)
    if (clean) clearData()
    remoteVersion = null
    lastSyncedAt.value = null
    status.value = 'idle'
    lastError.value = ''
    await remove(STATE_KEY)
  })

  const { App } = await import('@capacitor/app')
  App.addListener('resume', () => syncNow())
  App.addListener('pause', () => dirty && syncNow())
  syncNow()
}

export function useCloudSync() {
  return {
    status: readonly(status),
    lastError: readonly(lastError),
    lastSyncedAt: readonly(lastSyncedAt),
    syncNow,
  }
}
