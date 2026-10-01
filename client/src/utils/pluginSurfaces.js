import { defineAsyncComponent, markRaw, shallowReactive } from 'vue'

const manifests = import.meta.glob('../../plugins/*/nucleus.plugin.json', { eager: true, import: 'default' })
const modules = import.meta.glob('../../plugins/*/client/watchlistSurface.vue')

const dirOf = (file) => file.match(/\/plugins\/([^/]+)\//)?.[1]

export const PLACEMENTS = ['tab', 'panel', 'hidden']

function normalize(pluginId, decl, component) {
  const placements = Array.isArray(decl.placements) && decl.placements.length
    ? decl.placements.filter((p) => p === 'tab' || p === 'panel')
    : ['tab', 'panel']
  if (!placements.length) return null
  return {
    pluginId,
    path: typeof decl.path === 'string' && decl.path ? decl.path : pluginId,
    label: decl.label || pluginId,
    placements,
    defaultPlacement: placements.includes(decl.defaultPlacement) ? decl.defaultPlacement : placements[0],
    component: markRaw(component),
  }
}

function build() {
  const manifestByDir = {}
  for (const [file, m] of Object.entries(manifests)) manifestByDir[dirOf(file)] = m

  const out = []
  for (const [file, loader] of Object.entries(modules)) {
    const dir = dirOf(file)
    const manifest = manifestByDir[dir]
    const targets = Array.isArray(manifest?.target) ? manifest.target : [manifest?.target]
    if (!targets.includes('watchlist')) continue

    const pluginId = manifest?.id || dir
    const decl = manifest?.extensions?.watchlistSurface ?? {}
    const surface = normalize(pluginId, { ...decl, label: decl.label || manifest?.name }, defineAsyncComponent(loader))
    if (surface) out.push(surface)
  }
  return out
}

// Reactive so that surfaces installed at runtime in the iOS app (see
// plugins/runtime.js) appear without a reload.
export const watchlistSurfaces = shallowReactive(build())

export const surfaceByPath = (path) => watchlistSurfaces.find((s) => s.path === path) ?? null

/** Register a runtime plugin's surface: its bundle's default export. */
export function addRuntimeSurface(pluginId, exported) {
  removeRuntimeSurface(pluginId)
  if (!exported?.component) throw new Error('Its surface has no component.')
  const surface = normalize(pluginId, exported, exported.component)
  if (!surface) throw new Error('Its surface has no placement this app supports.')
  if (watchlistSurfaces.some((s) => s.path === surface.path)) throw new Error(`Another plugin already uses /x/${surface.path}.`)
  watchlistSurfaces.push(surface)
}

export function removeRuntimeSurface(pluginId) {
  for (let i = watchlistSurfaces.length - 1; i >= 0; i--) {
    if (watchlistSurfaces[i].pluginId === pluginId) watchlistSurfaces.splice(i, 1)
  }
}
