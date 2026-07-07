// Where a title opens when its poster is clicked.
//
// A "target" is `{ type, customUrl }`. The effective target for an item is its
// own `openTarget` when set, otherwise the per-type global default (Movies vs
// Shows) the user picked in Settings — see composables/useOpenSettings.js.

// Ordered for display in the settings/form pickers. `i18n` is the label key.
export const OPEN_OPTIONS = [
  { type: 'tmdb', i18n: 'watchlist.open.tmdb' },
  { type: 'csfd', i18n: 'watchlist.open.csfd' },
  { type: 'google', i18n: 'watchlist.open.google' },
  { type: 'custom', i18n: 'watchlist.open.custom' },
]

// How the {title} placeholder is shaped inside a custom URL. `raw` keeps the
// title as-is (just URL-encoded); the rest normalise words first.
export const TITLE_FORMATS = [
  { value: 'raw', i18n: 'watchlist.open.fmtRaw', example: 'The Matrix' },
  { value: 'lower', i18n: 'watchlist.open.fmtLower', example: 'the matrix' },
  { value: 'kebab', i18n: 'watchlist.open.fmtKebab', example: 'the-matrix' },
  { value: 'snake', i18n: 'watchlist.open.fmtSnake', example: 'the_matrix' },
  { value: 'pascal', i18n: 'watchlist.open.fmtPascal', example: 'TheMatrix' },
  { value: 'camel', i18n: 'watchlist.open.fmtCamel', example: 'theMatrix' },
]

const enc = (s) => encodeURIComponent(String(s ?? '').trim())

// Split a title into alphanumeric words, dropping punctuation/separators.
const words = (s) =>
  String(s ?? '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean)

const cap = (w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()

// Shape a title per the chosen format (see TITLE_FORMATS).
export function formatTitle(title, format) {
  const raw = String(title ?? '').trim()
  switch (format) {
    case 'lower':
      return raw.toLowerCase()
    case 'kebab':
      return words(raw).join('-').toLowerCase()
    case 'snake':
      return words(raw).join('_').toLowerCase()
    case 'pascal':
      return words(raw).map(cap).join('')
    case 'camel':
      return words(raw)
        .map((w, i) => (i === 0 ? w.toLowerCase() : cap(w)))
        .join('')
    case 'raw':
    default:
      return raw
  }
}

// Resolve the effective target for an item: its own override wins, else the
// global default for its type. `defaults` is `{ movie, show }`.
export function resolveTarget(item, defaults) {
  if (item?.openTarget?.type) return item.openTarget
  return defaults?.[item?.type] ?? null
}

// Build the destination URL for a target + item, or null when it can't (e.g. an
// empty custom template).
export function buildOpenUrl(target, item) {
  if (!target?.type || !item) return null
  const title = item.title || ''
  const year = item.year || ''
  switch (target.type) {
    case 'tmdb':
      return `https://www.themoviedb.org/search?query=${enc(title)}`
    case 'csfd':
      return `https://www.csfd.cz/hledat/?q=${enc(title)}`
    case 'google':
      return `https://www.google.com/search?q=${enc(`${title} ${year}`.trim())}`
    case 'custom': {
      const tpl = (target.customUrl || '').trim()
      if (!tpl) return null
      const shaped = formatTitle(title, target.titleFormat)
      return tpl.replaceAll('{title}', enc(shaped)).replaceAll('{year}', enc(year))
    }
    default:
      return null
  }
}
