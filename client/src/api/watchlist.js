import axios from 'axios'
import { useNativeUrls, toAbsolute } from '@/native.js'

const api = axios.create({ baseURL: '/api/watchlist' })
useNativeUrls(api)

export const getItems = (params = {}) => api.get('/', { params }).then((r) => r.data)
export const createItem = (data) => api.post('/', data).then((r) => r.data)
export const updateItem = (id, data) => api.patch(`/${id}`, data).then((r) => r.data)
export const deleteItem = (id) => api.delete(`/${id}`).then((r) => r.data)

export const getSettings = () => api.get('/settings').then((r) => r.data)
export const saveSettings = (settings) => api.put('/settings', settings).then((r) => r.data)

export const getCollections = () => api.get('/collections').then((r) => r.data)
export const createCollection = (data) => api.post('/collections', data).then((r) => r.data)
export const updateCollection = (id, data) => api.patch(`/collections/${id}`, data).then((r) => r.data)
export const deleteCollection = (id) => api.delete(`/collections/${id}`).then((r) => r.data)
export const addItemsToCollection = (id, itemIds) =>
  api.post(`/collections/${id}/items`, { itemIds }).then((r) => r.data)
export const saveCollectionOrder = (id, itemIds) =>
  api.put(`/collections/${id}/order`, { itemIds }).then((r) => r.data)

export async function uploadImage(file) {
  const form = new FormData()
  form.append('image', file)
  const res = await axios.post('/api/upload', form)
  return toAbsolute(res.data.url)
}
