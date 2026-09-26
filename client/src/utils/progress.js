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

export function watchedFraction(item) {
  if (item.status === 'completed') return 1
  if (item.type === 'movie') return 0
  const { totalEp, watchedEp, hasProgress } = showTotals(item)
  if (hasProgress && totalEp > 0) return watchedEp / totalEp
  return 0
}

export function itemRuntime(item) {
  return (item.type === 'movie' ? item.runtime : item.showRuntime) || 0
}

export function watchedMinutes(item) {
  return Math.round(itemRuntime(item) * watchedFraction(item))
}

export function remainingMinutes(item) {
  return itemRuntime(item) - watchedMinutes(item)
}

export function deriveStatus(watchedEp, totalEp) {
  if (totalEp > 0 && watchedEp >= totalEp) return 'completed'
  if (watchedEp > 0) return 'watching'
  return 'planned'
}
