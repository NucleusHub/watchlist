import axios from 'axios'
import { isNative, useNativeUrls, toAbsolute } from '@/native.js'
import * as local from './localApi.js'

// Inside Nucleus the watchlist lives on the home server. The iOS app keeps it
// on the device (optionally synced to Nucleus ID, see sync/cloudSync.js).
const api = axios.create({ baseURL: '/api/watchlist' })
useNativeUrls(api)

const server = {
  getItems: (params = {}) => api.get('/', { params }).then((r) => r.data),
  createItem: (data) => api.post('/', data).then((r) => r.data),
  updateItem: (id, data) => api.patch(`/${id}`, data).then((r) => r.data),
  deleteItem: (id) => api.delete(`/${id}`).then((r) => r.data),

  getSettings: () => api.get('/settings').then((r) => r.data),
  saveSettings: (settings) => api.put('/settings', settings).then((r) => r.data),

  getCollections: () => api.get('/collections').then((r) => r.data),
  createCollection: (data) => api.post('/collections', data).then((r) => r.data),
  updateCollection: (id, data) => api.patch(`/collections/${id}`, data).then((r) => r.data),
  deleteCollection: (id) => api.delete(`/collections/${id}`).then((r) => r.data),
  addItemsToCollection: (id, itemIds) => api.post(`/collections/${id}/items`, { itemIds }).then((r) => r.data),
  saveCollectionOrder: (id, itemIds) => api.put(`/collections/${id}/order`, { itemIds }).then((r) => r.data),

  async uploadImage(file) {
    const form = new FormData()
    form.append('image', file)
    const res = await axios.post('/api/upload', form)
    return toAbsolute(res.data.url)
  },
}

const impl = isNative ? local : server

export const getItems = (params) => impl.getItems(params)
export const createItem = (data) => impl.createItem(data)
export const updateItem = (id, data) => impl.updateItem(id, data)
export const deleteItem = (id) => impl.deleteItem(id)

export const getSettings = () => impl.getSettings()
export const saveSettings = (settings) => impl.saveSettings(settings)

export const getCollections = () => impl.getCollections()
export const createCollection = (data) => impl.createCollection(data)
export const updateCollection = (id, data) => impl.updateCollection(id, data)
export const deleteCollection = (id) => impl.deleteCollection(id)
export const addItemsToCollection = (id, itemIds) => impl.addItemsToCollection(id, itemIds)
export const saveCollectionOrder = (id, itemIds) => impl.saveCollectionOrder(id, itemIds)

export const uploadImage = (file) => impl.uploadImage(file)
