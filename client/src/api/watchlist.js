import axios from 'axios'

const api = axios.create({ baseURL: '/api/watchlist' })

export const getItems = (params = {}) => api.get('/', { params }).then((r) => r.data)
export const createItem = (data) => api.post('/', data).then((r) => r.data)
export const updateItem = (id, data) => api.patch(`/${id}`, data).then((r) => r.data)
export const deleteItem = (id) => api.delete(`/${id}`).then((r) => r.data)

export async function uploadImage(file) {
  const form = new FormData()
  form.append('image', file)
  const res = await axios.post('/api/upload', form)
  return res.data.url
}
