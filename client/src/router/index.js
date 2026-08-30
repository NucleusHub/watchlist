import { createRouter, createWebHistory } from 'vue-router'
import WatchlistView from '@/views/WatchlistView.vue'
import CollectionsView from '@/views/CollectionsView.vue'
import CollectionDetailView from '@/views/CollectionDetailView.vue'
import PluginSurfaceView from '@/views/PluginSurfaceView.vue'

export default createRouter({
  history: createWebHistory('/watchlist/'),
  routes: [
    { path: '/', name: 'watchlist', component: WatchlistView },
    { path: '/collections', name: 'collections', component: CollectionsView },
    { path: '/collections/:id', name: 'collection', component: CollectionDetailView, props: true },
    // Plugin-contributed surfaces placed as their own tab (see
    // utils/pluginSurfaces.js). One wildcard route rather than one route per
    // discovered surface: the plugin set is fixed per bundle, but whether a
    // given surface is enabled and tab-placed is a live, per-user question the
    // view answers on render — a stale bookmark lands on its "unavailable"
    // state instead of a 404 the router would have to be rebuilt to avoid.
    { path: '/x/:surface', name: 'plugin-surface', component: PluginSurfaceView },
  ],
})
