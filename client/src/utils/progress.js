// Shared helpers for show season/episode progress and the "runtime left"
// calculations used by the card, the progress modal and the stats view.

// Episode totals for a show. Prefers the per-season `seasonProgress` breakdown;
// falls back to the flat `episodes` count for legacy items without it.
export function showTotals(item) {
  const sp = item.seasonProgress
  if (Array.isArray(sp) && sp.length) {
    let totalEp = 0
    let watchedEp = 0
    for (const s of sp) {
      const count = s.episodeCount || 0
      totalEp += count
      watchedEp += Math.min(s.watched || 0, count)
    }
    return { totalEp, watchedEp, hasProgress: true }
  }
  return { totalEp: item.episodes || 0, watchedEp: 0, hasProgress: false }
}

// Fraction of a title that has been watched (0–1). A `completed` status always
// reads as fully watched so the card bar and stats stay in sync with the badge.
export function watchedFraction(item) {
  if (item.status === 'completed') return 1
  if (item.type === 'movie') return 0
  const { totalEp, watchedEp, hasProgress } = showTotals(item)
  if (hasProgress && totalEp > 0) return watchedEp / totalEp
  return 0
}

// Full runtime of a title in minutes.
export function itemRuntime(item) {
  return (item.type === 'movie' ? item.runtime : item.showRuntime) || 0
}

// Minutes already watched — counts partial show progress.
export function watchedMinutes(item) {
  return Math.round(itemRuntime(item) * watchedFraction(item))
}

// Minutes left to watch.
export function remainingMinutes(item) {
  return itemRuntime(item) - watchedMinutes(item)
}

// Derive a status from episode counts so the card badge stays in sync with
// the progress the user just recorded.
export function deriveStatus(watchedEp, totalEp) {
  if (totalEp > 0 && watchedEp >= totalEp) return 'completed'
  if (watchedEp > 0) return 'watching'
  return 'planned'
}
