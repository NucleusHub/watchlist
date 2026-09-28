import { Capacitor } from '@capacitor/core'

export const isNative = Capacitor.isNativePlatform()
export const API_ORIGIN = isNative ? (import.meta.env.VITE_API_ORIGIN || '').replace(/\/+$/, '') : ''

const isServerPath = (u) =>
  typeof u === 'string' && (u.startsWith('/api/') || u.startsWith('/uploads/') || u === '/appearance.json')

export const toAbsolute = (u) => (API_ORIGIN && isServerPath(u) ? API_ORIGIN + u : u)
export const toRelative = (u) =>
  API_ORIGIN && typeof u === 'string' && u.startsWith(API_ORIGIN + '/uploads/') ? u.slice(API_ORIGIN.length) : u

function mapStrings(value, fn) {
  if (typeof value === 'string') return fn(value)
  if (Array.isArray(value)) return value.map((v) => mapStrings(v, fn))
  if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, mapStrings(v, fn)]))
  }
  return value
}

export function useNativeUrls(instance) {
  if (!API_ORIGIN) return
  instance.interceptors.request.use((config) => ({ ...config, data: mapStrings(config.data, toRelative) }))
  instance.interceptors.response.use((res) => ({ ...res, data: mapStrings(res.data, toAbsolute) }))
}

export function installNativeNetworking() {
  if (!isNative) return
  if (!API_ORIGIN) {
    console.error('[native] VITE_API_ORIGIN is not set — API calls will fail. Create client/.env.native.')
    return
  }
  const origFetch = window.fetch.bind(window)
  window.fetch = (input, init) => origFetch(isServerPath(input) ? API_ORIGIN + input : input, init)

  const origOpen = XMLHttpRequest.prototype.open
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    return origOpen.call(this, method, isServerPath(url) ? API_ORIGIN + url : url, ...rest)
  }
}

export function lockNativeZoom() {
  if (!isNative) return
  document.documentElement.classList.add('native')
  const meta = document.querySelector('meta[name="viewport"]')
  if (meta) meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover'
}

function revealFocusedInModal() {
  const el = document.activeElement
  if (el?.closest?.('.tm-panel')) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
}

export async function setupNativeKeyboard() {
  if (!isNative) return
  try {
    const { Keyboard } = await import('@capacitor/keyboard')
    await Keyboard.setAccessoryBarVisible({ isVisible: false })
    const root = document.documentElement
    Keyboard.addListener('keyboardWillShow', ({ keyboardHeight }) => {
      root.style.setProperty('--kb', `${keyboardHeight}px`)
      setTimeout(revealFocusedInModal, 340)
    })
    Keyboard.addListener('keyboardWillHide', () => root.style.setProperty('--kb', '0px'))
  } catch {}
}

export async function haptic(style = 'Medium') {
  if (!isNative) return
  try {
    const { Haptics, ImpactStyle } = await import('@capacitor/haptics')
    await Haptics.impact({ style: ImpactStyle[style] })
  } catch {}
}
