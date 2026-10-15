// Route locations for opening a library item or a TMDb title in-app; `kind` is 'movie' or 'show'.
// A title opens as a sheet over the current page (see ItemSheet).
export const itemRoute = (id) => ({ query: { item: String(id) } })
export const titleRoute = (kind, tmdbId) => ({ name: 'title', params: { kind, tmdbId: String(tmdbId) } })
export const pageRoute = (plugin, page, arg = '') => ({ name: 'plugin-page', params: { plugin, page, arg: String(arg) } })
