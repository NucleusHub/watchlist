// The app manifest sits above the client folder; the glob is empty where it isn't shipped.
const manifests = import.meta.glob('../../../nucleus.app.json', { eager: true })
export const APP_VERSION = Object.values(manifests)[0]?.default?.version ?? ''
export const PRIVACY_URL = 'https://nucleus-home.dev/privacy/watchlist'
export const TMDB_KEY_URL = 'https://www.themoviedb.org/settings/api'
