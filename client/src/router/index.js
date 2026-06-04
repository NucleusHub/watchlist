import { createRouter, createWebHistory } from 'vue-router'
import WatchlistView from '@/views/WatchlistView.vue'

export default createRouter({
  history: createWebHistory('/watchlist/'),
  routes: [
    { path: '/', component: WatchlistView },
  ],
})
