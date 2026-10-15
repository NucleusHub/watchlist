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

