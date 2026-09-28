import { isNative } from '@/native.js'

// WKWebView localStorage can be evicted by iOS under storage pressure, so on
// device everything that must survive goes through Capacitor Preferences
// (UserDefaults). The browser build falls back to localStorage.
// The plugin is wrapped in an object on purpose: a Capacitor plugin is a Proxy
// that answers every property, `then` included, so resolving a promise with it
// directly makes the promise wait on a native "then" call that never returns.
let prefs = null
async function preferences() {
  if (!isNative) return null
  if (!prefs) prefs = { plugin: (await import('@capacitor/preferences')).Preferences }
  return prefs
}

export async function readJson(key, fallback = null) {
  try {
    const p = await preferences()
    const raw = p ? (await p.plugin.get({ key })).value : localStorage.getItem(key)
    return raw ? JSON.parse(raw) : fallback
  } catch {
    return fallback
  }
}

export async function writeJson(key, value) {
  const raw = JSON.stringify(value)
  const p = await preferences()
  if (p) await p.plugin.set({ key, value: raw })
  else localStorage.setItem(key, raw)
}

export async function remove(key) {
  try {
    const p = await preferences()
    if (p) await p.plugin.remove({ key })
    else localStorage.removeItem(key)
  } catch {}
}
