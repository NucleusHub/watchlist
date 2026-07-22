import axios from 'axios'

const api = axios.create({ baseURL: '/api/watchlist' })

export const getItems = (params = {}) => api.get('/', { params }).then((r) => r.data)
export const createItem = (data) => api.post('/', data).then((r) => r.data)
export const updateItem = (id, data) => api.patch(`/${id}`, data).then((r) => r.data)
export const deleteItem = (id) => api.delete(`/${id}`).then((r) => r.data)

// Per-user app preferences (the per-type "open in" defaults).
export const getSettings = () => api.get('/settings').then((r) => r.data)
export const saveSettings = (openDefaults) => api.put('/settings', openDefaults).then((r) => r.data)

// Collections. Membership itself is stored on the item, so assigning/removing
// reuses updateItem(id, { collectionIds }); these endpoints manage the
// collections themselves (name/description) and derive each item count.
export const getCollections = () => api.get('/collections').then((r) => r.data)
export const createCollection = (data) => api.post('/collections', data).then((r) => r.data)
export const updateCollection = (id, data) => api.patch(`/collections/${id}`, data).then((r) => r.data)
export const deleteCollection = (id) => api.delete(`/collections/${id}`).then((r) => r.data)
// Bulk-add existing items to a collection ($addToSet server-side). Returns
// { items, modified }.
export const addItemsToCollection = (id, itemIds) =>
  api.post(`/collections/${id}/items`, { itemIds }).then((r) => r.data)
// Persist a collection's manual item order (array of item ids).
export const saveCollectionOrder = (id, itemIds) =>
  api.put(`/collections/${id}/order`, { itemIds }).then((r) => r.data)

export async function uploadImage(file) {
  const form = new FormData()
  form.append('image', file)
  const res = await axios.post('/api/upload', form)
  return res.data.url
}
