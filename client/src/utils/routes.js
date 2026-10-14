// Route locations for opening a library item or a TMDb title in-app; `kind` is 'movie' or 'show'.
export const itemRoute = (id) => ({ name: 'item', params: { id: String(id) } })
export const titleRoute = (kind, tmdbId) => ({ name: 'title', params: { kind, tmdbId: String(tmdbId) } })
export const pageRoute = (plugin, page, arg = '') => ({ name: 'plugin-page', params: { plugin, page, arg: String(arg) } })
