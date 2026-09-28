import { ref, readonly } from 'vue'
import { readJson, writeJson, remove } from '@/storage/persist.js'
import { sha256Hex } from '@/auth/pkce.js'
import { NUCLEUS_ID_ORIGIN } from '@/auth/nucleusId.js'
import { addRuntimeSources, removeRuntimeSources } from '@/api/sources.js'

// Plugins installed from the Nucleus Marketplace at runtime — the iOS app's
// counterpart to a self-hosted Nucleus cloning a plugin into plugins/. The
// marketplace serves each plugin's code as one self-contained ES module per
// extension point (nucleus-web: routes/native.js); it is checked against the
// listing's SHA-256, kept on the device, and imported from a blob on launch.
const MARKETPLACE = `${NUCLEUS_ID_ORIGIN}/api/v1/native`
const TARGET = 'watchlist'
const INDEX_KEY = 'watchlist-plugins'
const codeKey = (id, extension) => `watchlist-plugin:${id}:${extension}`

// The extension points this app can load at runtime, and how. Keep in step
// with NATIVE_EXTENSIONS in nucleus-web's lib/native.js.
const EXTENSIONS = {
  watchlistSources: (pluginId, exported) => addRuntimeSources(pluginId, exported),
}
const RELEASE = {
  watchlistSources: (pluginId) => removeRuntimeSources(pluginId),
}

const installed = ref([]) // [{ id, name, tagline, version, iconSvg, author, bundles: [{ extension, sha256 }], installedAt }]
const problems = ref({}) // id → why it didn't load

const supported = (listing) => (listing.bundles || []).filter((b) => EXTENSIONS[b.extension])

async function importCode(code) {
  const url = URL.createObjectURL(new Blob([code], { type: 'text/javascript' }))
  try {
    // A module namespace, never a Capacitor proxy — safe to await.
    return await import(/* @vite-ignore */ url)
  } finally {
    URL.revokeObjectURL(url)
  }
}

async function activate(plugin) {
  const sourceIds = []
  for (const { extension } of plugin.bundles) {
    const code = await readJson(codeKey(plugin.id, extension))
    if (typeof code !== 'string') throw new Error('Its code is missing — reinstall it.')
    const mod = await importCode(code)
    const ids = EXTENSIONS[extension]?.(plugin.id, mod.default)
    if (Array.isArray(ids)) sourceIds.push(...ids)
  }
  const { [plugin.id]: _, ...rest } = problems.value
  problems.value = rest
  return sourceIds
}

function deactivate(id) {
  for (const release of Object.values(RELEASE)) release(id)
}

export async function initNativePlugins() {
  installed.value = (await readJson(INDEX_KEY, [])) || []
  for (const plugin of installed.value) {
    try {
      await activate(plugin)
    } catch (err) {
      problems.value = { ...problems.value, [plugin.id]: err.message || String(err) }
    }
  }
}

/** What the marketplace offers this app. */
export async function fetchCatalogue() {
  const res = await fetch(`${MARKETPLACE}/plugins?target=${TARGET}`)
  if (!res.ok) throw new Error(`Marketplace ${res.status}`)
  const { plugins } = await res.json()
  return plugins.filter((p) => supported(p).length)
}

/**
 * Download, verify and load a listing (install or update). Returns the search
 * source ids it registered, so the caller can switch them on.
 */
export async function install(listing) {
  const bundles = supported(listing)
  if (!bundles.length) throw new Error('This plugin has nothing this app can run.')

  // Everything is downloaded and checked before anything is replaced, so a
  // failed update leaves the working version in place.
  const downloaded = []
  for (const b of bundles) {
    const res = await fetch(`${MARKETPLACE}/plugins/${encodeURIComponent(listing.id)}/${b.extension}`)
    if (!res.ok) throw new Error(`Download failed (${res.status})`)
    const code = await res.text()
    if ((await sha256Hex(code)) !== b.sha256) throw new Error('The download did not match the marketplace listing.')
    downloaded.push({ extension: b.extension, sha256: b.sha256, code })
  }

  deactivate(listing.id)
  for (const d of downloaded) await writeJson(codeKey(listing.id, d.extension), d.code)
  const entry = {
    id: listing.id,
    name: listing.name,
    tagline: listing.tagline,
    version: listing.version,
    iconSvg: listing.iconSvg || null,
    author: listing.author || null,
    bundles: downloaded.map(({ extension, sha256 }) => ({ extension, sha256 })),
    installedAt: new Date().toISOString(),
  }
  installed.value = [...installed.value.filter((p) => p.id !== listing.id), entry]
  await writeJson(INDEX_KEY, installed.value)
  return activate(entry)
}

export async function uninstall(id) {
  const plugin = installed.value.find((p) => p.id === id)
  deactivate(id)
  for (const b of plugin?.bundles || []) await remove(codeKey(id, b.extension))
  installed.value = installed.value.filter((p) => p.id !== id)
  const { [id]: _, ...rest } = problems.value
  problems.value = rest
  await writeJson(INDEX_KEY, installed.value)
}

/** A newer version, or different code, than what's installed. */
export function hasUpdate(listing) {
  const mine = installed.value.find((p) => p.id === listing.id)
  if (!mine) return false
  const shas = (list) => list.map((b) => `${b.extension}:${b.sha256}`).sort().join()
  return mine.version !== listing.version || shas(mine.bundles) !== shas(supported(listing))
}

export function useNativePlugins() {
  return {
    installed: readonly(installed),
    problems: readonly(problems),
    nameOf: (id) => installed.value.find((p) => p.id === id)?.name ?? null,
  }
}
