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
    { path: '/x/:surface', name: 'plugin-surface', component: PluginSurfaceView },
  ],
})
