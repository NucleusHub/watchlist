import { createRouter, createWebHistory } from 'vue-router'
import WatchlistView from '@/views/WatchlistView.vue'
import CollectionsView from '@/views/CollectionsView.vue'
import CollectionDetailView from '@/views/CollectionDetailView.vue'
import TitlePreviewView from '@/views/TitlePreviewView.vue'
import PluginSurfaceView from '@/views/PluginSurfaceView.vue'
import PluginPageView from '@/views/PluginPageView.vue'

export default createRouter({
  history: createWebHistory('/watchlist/'),
  // Opening or closing a title's sheet changes only the query; the page behind keeps its scroll.
  scrollBehavior: (to, from, saved) => (to.path === from.path ? false : saved || { top: 0 }),
  routes: [
    { path: '/', name: 'watchlist', component: WatchlistView },
    { path: '/collections', name: 'collections', component: CollectionsView },
    { path: '/collections/:id', name: 'collection', component: CollectionDetailView, props: true },
    { path: '/item/:id', redirect: (to) => ({ path: '/', query: { item: to.params.id } }) },
    { path: '/title/:kind/:tmdbId', name: 'title', component: TitlePreviewView, props: true },
    { path: '/x/:surface', name: 'plugin-surface', component: PluginSurfaceView },
    { path: '/p/:plugin/:page/:arg?', name: 'plugin-page', component: PluginPageView },
    { path: '/stats', name: 'stats', component: () => import('@/views/StatsView.vue') },
    { path: '/settings', name: 'settings', component: () => import('@/views/settings/SettingsView.vue') },
    { path: '/settings/open', name: 'settings-open', component: () => import('@/views/settings/OpenDefaultsView.vue') },
    { path: '/settings/sources', name: 'settings-sources', component: () => import('@/views/settings/SearchSourcesView.vue') },
    { path: '/settings/plugins', name: 'settings-plugins', component: () => import('@/views/settings/PluginsView.vue') },
    { path: '/settings/tmdb', name: 'settings-tmdb', component: () => import('@/views/settings/TMDbKeyView.vue') },
    { path: '/settings/moviedna', name: 'moviedna', component: () => import('@/views/settings/MovieDNAView.vue') },
  ],
})

export { itemRoute, titleRoute, pageRoute } from '@/utils/routes.js'
