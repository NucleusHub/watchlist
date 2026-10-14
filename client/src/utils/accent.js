// This app's accent, `{ id, custom, updatedAt }` in settings.accent, shared with iOS (NucleusAccent).
const KEY = 'watchlist-accent'

// Same swatches as the configurator and the iOS NucleusAccent presets.
export const PRESETS = [
  { id: 'nucleus', name: 'Nucleus', hex: '#A855F7' },
  { id: 'midnight', name: 'Midnight', hex: '#4F6BF6' },
  { id: 'arctic', name: 'Arctic', hex: '#22B8CF' },
  { id: 'ember', name: 'Ember', hex: '#F2711C' },
  { id: 'forest', name: 'Forest', hex: '#2FA36B' },
]

export const HEX = /^#[0-9a-f]{6}$/i

export function accentHex(accent) {
  if (accent?.id === 'custom') return HEX.test(accent.custom) ? accent.custom : null
  return PRESETS.find((p) => p.id === accent?.id)?.hex ?? null
}

// OKLCH hue in degrees.
export function hueOf(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
  const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
  const [lr, lg, lb] = [r, g, b].map(lin)
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
  const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
  return ((Math.atan2(bb, a) * 180) / Math.PI + 360) % 360
}

// Degrees from the Nucleus purple to the accent, the short way round.
export const hueShift = (hex) => ((hueOf(hex) - hueOf(PRESETS[0].hex) + 540) % 360) - 180

export const loadAccent = () => {
  try {
    const a = JSON.parse(localStorage.getItem(KEY))
    return a?.id ? a : null
  } catch {
    return null
  }
}

export const storeAccent = (accent) => {
  try {
    if (accent) localStorage.setItem(KEY, JSON.stringify(accent))
    else localStorage.removeItem(KEY)
  } catch {}
}

const FAMILIES = ['violet', 'purple', 'indigo', 'fuchsia']
const SHADES = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
const touched = []

// Turns Tailwind's purple family (the app's UI colour) to the accent's hue with relative colour syntax.
export function applyAccent(accent) {
  if (typeof document === 'undefined') return
  const root = document.documentElement
  for (const name of touched.splice(0)) root.style.removeProperty(name)
  const hex = accentHex(accent)
  const shift = hex ? hueShift(hex) : 0
  if (!shift || !CSS.supports('color', 'oklch(from red l c h)')) return
  const style = getComputedStyle(root)
  for (const family of FAMILIES) {
    for (const shade of SHADES) {
      const name = `--color-${family}-${shade}`
      const stock = style.getPropertyValue(name).trim()
      if (!stock) continue
      root.style.setProperty(name, `oklch(from ${stock} l c calc(h + ${shift.toFixed(2)}))`)
      touched.push(name)
    }
  }
}
