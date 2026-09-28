export const MAX_GENRES = 12
const MAX_GENRE_LEN = 40

export function normalizeGenres(value) {
  const out = []
  const seen = new Set()
  for (const raw of Array.isArray(value) ? value : []) {
    if (typeof raw !== 'string') continue
    const name = raw.trim().replace(/\s+/g, ' ').slice(0, MAX_GENRE_LEN)
    if (!name) continue
    const key = name.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    out.push(name)
    if (out.length === MAX_GENRES) break
  }
  return out
}

export function genresFromTmdbDetail(detail) {
  return normalizeGenres((detail?.genres ?? []).map((g) => g?.name))
}

export function genreFacets(items) {
  const counts = new Map()
  for (const item of items ?? []) {
    for (const name of item?.genres ?? []) {
      const key = name.toLowerCase()
      const entry = counts.get(key)
      if (entry) entry.count++
      else counts.set(key, { name, count: 1 })
    }
  }
  return [...counts.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
}

export function hasGenre(item, name) {
  const key = String(name).toLowerCase()
  return (item?.genres ?? []).some((g) => g.toLowerCase() === key)
}

const PILL_CLASSES = [
  'bg-rose-500/10 text-rose-600 dark:bg-rose-400/10 dark:text-rose-300',
  'bg-amber-500/10 text-amber-600 dark:bg-amber-400/10 dark:text-amber-300',
  'bg-emerald-500/10 text-emerald-600 dark:bg-emerald-400/10 dark:text-emerald-300',
  'bg-sky-500/10 text-sky-600 dark:bg-sky-400/10 dark:text-sky-300',
  'bg-violet-500/10 text-violet-600 dark:bg-violet-400/10 dark:text-violet-300',
  'bg-fuchsia-500/10 text-fuchsia-600 dark:bg-fuchsia-400/10 dark:text-fuchsia-300',
  'bg-teal-500/10 text-teal-600 dark:bg-teal-400/10 dark:text-teal-300',
  'bg-orange-500/10 text-orange-600 dark:bg-orange-400/10 dark:text-orange-300',
]

export function genrePillClass(name) {
  const key = String(name ?? '').toLowerCase()
  let hash = 0
  for (let i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) | 0
  return PILL_CLASSES[Math.abs(hash) % PILL_CLASSES.length]
}
