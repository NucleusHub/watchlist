// Plugins ship client/watchlistSurface.vue and declare in their manifest:
//   "extensions": {
//     "watchlistSurface": {
//       "path": "discover",             // route segment under /x/
//       "label": "Discover",            // nav tab label (i18n key or literal)
//       "placements": ["tab", "panel"], // what it supports; default both
//       "defaultPlacement": "tab"       // until the user chooses
//     },
//     "movieDNAUse": { "purpose": "Picks what Discover shows you" }  // optional: says it reads MovieDNA
//   }
// The component receives:
//   :items      Array   the viewer's full watchlist, already loaded by the host
//   :placement  String  'tab' | 'panel' — so it can render compactly in a panel
//   :host       Object  what the app does for the plugin (see composables/useWatchlistHost.js):
//     movieDNA          { enabled, genres[{name,strength}], titles[{kind,tmdbID,name,strength}],
//                         people[{personID,name,strength,followed}], notInterested:Set<'movie:603'> }
//                       read-only, strongest first, -100..100; empty lists while MovieDNA is off
//     library           [{kind,tmdbID,title,genres,rating,favorite,isCompleted,finishedAt}]
//     titles            [{id,title,kind,posterURL,isCompleted,lastWatchedAt:Date|null,resume:{position,duration,fraction}|null,
//                         nextEpisode:{season,episode}|null,resumeHost}] — id is the item id
//     resume(id)        opens the saved page of a title in a new tab
//     resetActions(id)  [{id,title,isDestructive}] ways to reset a title's progress; perform(id, actionId) -> Promise
//     openItem(id)      goes to the title's detail page
//     hasTMDbKey, tmdb(path, query) -> parsed TMDb JSON; the key stays inside the app
//     inLibrary(kind, tmdbID), addToWatchlist(kind, tmdbID) -> Promise
//     markNotInterested(kind, tmdbID, title, genres)
//     isFollowing(personID), setFollowing(following, personID, name, photoURL), person(id) -> { credits }
//     credits(kind, tmdbID) -> { cast, crew: [{personID,name,role,department,photoURL}] }, cast in billing order
//     person(id) -> { id,name,biography,knownFor,birthday,deathday,birthplace,photoURL,wikidataID,imdbID,
//                     credits:[{titleID,kind,title,date,posterURL,role,department,voteCount,isSelf}] }
//     open({ type: 'title', kind, tmdbID } | { type: 'person', id, name } | { type: 'page', plugin, page, arg }
//           | { type: 'web', url }) — title/person/page navigate in-app, person needs a plugin owning the 'person' page
//     playTrailer(youTubeKey)   plays it in the app's own player
//     news(refresh)             -> { articles: [{title,link,published:ISO|null,source,image|null,summary}], failed:[source] }
//                               newest first, from the server's fixed feed list (cached ~15 min; refresh=true asks for a new fetch)
//     personSections            component: <component :is="host.personSections" :person-id :name /> renders what
//                               other plugins add to a person page
//   kind is 'movie' | 'show'. A plugin never imports app code; it only talks to the host.
// and may emit:
//   @changed           the host reloads items (e.g. the plugin added one)
//
// Other fixed filenames in plugins/*/client (each needs target 'watchlist', and the plugin enabled):
//   watchlistItemSection.vue    a section on a title's detail and preview pages. Props:
//                               kind, tmdbID (null when TMDb doesn't know it), title, host, canNavigate,
//                               credits ({cast,crew} entered by hand for titles without a tmdbID, else null)
//   watchlistPage.vue           pages opened at /p/:plugin/:page/:arg?; declared as
//                               "extensions": { "watchlistPages": ["person", "credits"] }. Props: page, arg, host.
//                               The page id 'person' answers open({type:'person'}); arg is the TMDb person id.
//   watchlistPersonSection.vue  a section on the person page. Props: personID, name, host
//   header buttons              "extensions": { "watchlistHeaderButtons": [{ "icon": "search", "title": "Label", "page": "id" }] }
//                               icon is a core icon name; the button opens that page of the plugin with an empty arg

import { defineAsyncComponent } from 'vue'

const manifests = import.meta.glob('../../plugins/*/nucleus.plugin.json', { eager: true, import: 'default' })
const modules = import.meta.glob('../../plugins/*/client/watchlistSurface.vue')
const itemSectionModules = import.meta.glob('../../plugins/*/client/watchlistItemSection.vue')
const pageModules = import.meta.glob('../../plugins/*/client/watchlistPage.vue')
const personSectionModules = import.meta.glob('../../plugins/*/client/watchlistPersonSection.vue')

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

const forWatchlist = (m) => (Array.isArray(m?.target) ? m.target : [m?.target]).includes('watchlist')

function contributions(globbed) {
  return Object.entries(globbed).flatMap(([file, loader]) => {
    const dir = dirOf(file)
    const manifest = Object.entries(manifests).find(([f]) => dirOf(f) === dir)?.[1]
    return forWatchlist(manifest) ? [{ pluginId: manifest.id || dir, manifest, component: defineAsyncComponent(loader) }] : []
  })
}

export const itemSections = contributions(itemSectionModules)
export const personSections = contributions(personSectionModules)

// One entry per page id the manifest declares; the plugin's single watchlistPage.vue draws all of them.
export const pages = contributions(pageModules).flatMap(({ manifest: m, ...rest }) =>
  (Array.isArray(m.extensions?.watchlistPages) ? m.extensions.watchlistPages : [])
    .filter((id) => typeof id === 'string' && id)
    .map((id) => ({ ...rest, id }))
)

export const pageOf = (plugin, id) => pages.find((p) => p.pluginId === plugin && p.id === id) ?? null

export const headerButtons = contributions(pageModules).flatMap(({ pluginId, manifest }) =>
  (Array.isArray(manifest.extensions?.watchlistHeaderButtons) ? manifest.extensions.watchlistHeaderButtons : [])
    .filter((b) => b?.page && b?.title)
    .map((b) => ({ pluginId, icon: b.icon, title: b.title, page: b.page }))
)

// Plugins that read MovieDNA, for the "used by" list in MovieDNA settings.
export const movieDNAUses = Object.entries(manifests).flatMap(([file, m]) => {
  const targets = Array.isArray(m?.target) ? m.target : [m?.target]
  const purpose = m?.extensions?.movieDNAUse?.purpose
  return targets.includes('watchlist') && typeof purpose === 'string' && purpose
    ? [{ pluginId: m.id || dirOf(file), purpose }]
    : []
})
