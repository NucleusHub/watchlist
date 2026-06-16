import WatchlistCard from './WatchlistCard.vue'

// Watchlist's Echo client integration — the single file Echo auto-discovers for
// this app. Owns the renderer for its message type plus the "share from
// watchlist" composer action. Server-side declaration: manifest.echo.json here.
export default {
  app: 'watchlist',

  renderers: {
    'watchlist.item': WatchlistCard,
  },

  // `source` drives Echo's generic share picker in grid (poster) layout.
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
          message: { type: 'watchlist.item', payload: { itemId: i._id, title: i.title, type: i.type, status: i.status, posterUrl: i.posterUrl, year: i.year, rating: i.rating, tmdbRating: i.tmdbRating } },
        }),
      },
    },
  },
}
