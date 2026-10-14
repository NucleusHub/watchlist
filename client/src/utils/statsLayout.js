// The statistics page as arranged by the person (ios/Watchlist/Model/StatsLayout.swift). Kept per browser.
const KEY = 'watchlist-stats-layout'

export const STANDARD = [
  { card: 'watched', visible: true, size: 'large' },
  { card: 'inProgress', visible: true, size: 'small' },
  { card: 'planned', visible: true, size: 'small' },
  { card: 'total', visible: true, size: 'small' },
  { card: 'ratings', visible: true, size: 'small' },
  { card: 'byType', visible: true, size: 'large' },
  { card: 'availableOn', visible: true, size: 'large' },
  { card: 'topYears', visible: true, size: 'large' },
]

const standard = () => STANDARD.map((e) => ({ ...e }))

// Unknown and repeated cards go; cards missing from an older layout are added at the end, visible.
export function normalizeLayout(raw) {
  const known = new Map(STANDARD.map((e) => [e.card, e]))
  const seen = new Set()
  const out = []
  for (const e of Array.isArray(raw) ? raw : []) {
    if (!known.has(e?.card) || seen.has(e.card)) continue
    seen.add(e.card)
    out.push({ card: e.card, visible: e.visible !== false, size: e.size === 'small' || e.size === 'large' ? e.size : known.get(e.card).size })
  }
  for (const e of STANDARD) if (!seen.has(e.card)) out.push({ ...e })
  return out
}

// Visible cards in rows: two small ones side by side, a large one (or a lone small one) alone.
export function layoutRows(entries, available = null) {
  const rows = []
  let pending = null
  for (const e of entries) {
    if (!e.visible || (available && !available.has(e.card))) continue
    if (e.size === 'small') {
      if (pending) { rows.push([pending, e]); pending = null } else pending = e
    } else {
      if (pending) { rows.push([pending]); pending = null }
      rows.push([e])
    }
  }
  if (pending) rows.push([pending])
  return rows
}

export function moveEntry(entries, from, to) {
  if (to < 0 || to >= entries.length || from === to) return entries
  const next = [...entries]
  next.splice(to, 0, next.splice(from, 1)[0])
  return next
}

export function loadLayout() {
  try {
    return normalizeLayout(JSON.parse(localStorage.getItem(KEY)))
  } catch {
    return standard()
  }
}

export function saveLayout(entries) {
  try { localStorage.setItem(KEY, JSON.stringify(entries)) } catch {}
}

export const standardLayout = standard
