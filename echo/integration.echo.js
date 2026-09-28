import WatchlistCard from './WatchlistCard.vue'

export default {
  app: 'watchlist',

  renderers: {
    'watchlist.item': WatchlistCard,
  },

  composerActions: {
    share_watchlist: {
      source: {
        title: 'Share from Watchlist',
        layout: 'grid',
        fetch: () => fetch('/api/watchlist', { credentials: 'include' }).then(r => r.json()),
        map: i => ({
          key: i._id,
          title: i.title,
          subtitle: [i.type === 'show' ? 'Show' : 'Movie', i.status].filter(Boolean).join(' · '),
          thumb: i.posterUrl,
          message: { type: 'watchlist.item', payload: { itemId: i._id, title: i.title, type: i.type, status: i.status, posterUrl: i.posterUrl, year: i.year, rating: i.rating, tmdbRating: i.tmdbRating, runtime: i.runtime, seasons: i.seasons, episodes: i.episodes, showRuntime: i.showRuntime } },
        }),
      },
    },
  },
}
