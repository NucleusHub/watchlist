import { createRouter, createWebHistory } from 'vue-router'
import WatchlistView from '@/views/WatchlistView.vue'
import CollectionsView from '@/views/CollectionsView.vue'
import CollectionDetailView from '@/views/CollectionDetailView.vue'
import ItemDetailView from '@/views/ItemDetailView.vue'
import TitlePreviewView from '@/views/TitlePreviewView.vue'
import PluginSurfaceView from '@/views/PluginSurfaceView.vue'
import PluginPageView from '@/views/PluginPageView.vue'

export default createRouter({
  history: createWebHistory('/watchlist/'),
  routes: [
    { path: '/', name: 'watchlist', component: WatchlistView },
    { path: '/collections', name: 'collections', component: CollectionsView },
    { path: '/collections/:id', name: 'collection', component: CollectionDetailView, props: true },
    { path: '/item/:id', name: 'item', component: ItemDetailView, props: true },
    { path: '/title/:kind/:tmdbId', name: 'title', component: TitlePreviewView, props: true },
    { path: '/x/:surface', name: 'plugin-surface', component: PluginSurfaceView },
    { path: '/p/:plugin/:page/:arg?', name: 'plugin-page', component: PluginPageView },
  ],
})

export { itemRoute, titleRoute, pageRoute } from '@/utils/routes.js'
