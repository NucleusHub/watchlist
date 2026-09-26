// Plugins ship client/watchlistSurface.vue and declare in their manifest:
//   "extensions": {
//     "watchlistSurface": {
//       "path": "for-you",              // route segment under /x/
//       "label": "For you",             // nav tab label (i18n key or literal)
//       "placements": ["tab", "panel"], // what it supports; default both
//       "defaultPlacement": "tab"       // until the user chooses
//     }
//   }
// The component receives:
//   :items      Array  the viewer's full watchlist, already loaded by the host
//   :placement  String 'tab' | 'panel' — so it can render compactly in a panel
// and may emit:
//   @changed           the host reloads items (e.g. the plugin added one)

import { defineAsyncComponent } from 'vue'

const manifests = import.meta.glob('../../plugins/*/nucleus.plugin.json', { eager: true, import: 'default' })
const modules = import.meta.glob('../../plugins/*/client/watchlistSurface.vue')

const dirOf = (file) => file.match(/\/plugins\/([^/]+)\//)?.[1]

export const PLACEMENTS = ['tab', 'panel', 'hidden']

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
    const placements = Array.isArray(decl.placements) && decl.placements.length
      ? decl.placements.filter((p) => p === 'tab' || p === 'panel')
      : ['tab', 'panel']
    if (!placements.length) continue

    out.push({
      pluginId,
      path: typeof decl.path === 'string' && decl.path ? decl.path : pluginId,
      label: decl.label || manifest?.name || pluginId,
      placements,
      defaultPlacement: placements.includes(decl.defaultPlacement) ? decl.defaultPlacement : placements[0],
      component: defineAsyncComponent(loader),
    })
  }
  return out
}

export const watchlistSurfaces = build()

export const surfaceByPath = (path) => watchlistSurfaces.find((s) => s.path === path) ?? null
