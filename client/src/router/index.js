import { createRouter, createWebHistory } from 'vue-router'
import WatchlistView from '@/views/WatchlistView.vue'
import CollectionsView from '@/views/CollectionsView.vue'
import CollectionDetailView from '@/views/CollectionDetailView.vue'
import PluginSurfaceView from '@/views/PluginSurfaceView.vue'
import TabsLayout from '@/layouts/TabsLayout.vue'
import SettingsView from '@/views/SettingsView.vue'
import StatsView from '@/views/StatsView.vue'

export default createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      component: TabsLayout,
      meta: { depth: 0 },
      children: [
        { path: '', name: 'watchlist', component: WatchlistView },
        { path: 'collections', name: 'collections', component: CollectionsView },
        { path: 'x/:surface', name: 'plugin-surface', component: PluginSurfaceView },
      ],
    },
    { path: '/collections/:id', name: 'collection', component: CollectionDetailView, props: true, meta: { depth: 1 } },
    { path: '/settings', name: 'settings', component: SettingsView, meta: { depth: 1 } },
    { path: '/stats', name: 'stats', component: StatsView, meta: { depth: 1 } },
  ],
})
