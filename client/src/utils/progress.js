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

export function formatRuntime(minutes) {
  if (!minutes) return null
  if (minutes < 60) return `${minutes} min`
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return m ? `${h}h ${m}m` : `${h}h`
}

// "2023 · 2h 10m" for a movie, "2023 · 3 seasons · 24 ep · 20h" for a show; `t` is the i18n function.
export function metaLine(item, t) {
  const parts = []
  if (item.year) parts.push(item.year)
  if (item.type === 'movie') {
    const rt = formatRuntime(item.runtime)
    if (rt) parts.push(rt)
  } else {
    if (item.seasons) parts.push(t(item.seasons === 1 ? 'watchlist.card.seasonOne' : 'watchlist.card.seasonMany', { count: item.seasons }))
    if (item.episodes) parts.push(t('watchlist.card.episodesShort', { count: item.episodes }))
    const rt = formatRuntime(item.showRuntime)
    if (rt) parts.push(rt)
  }
  return parts.join(' · ')
}

// Marking watched spends the saved playback and page, as on iOS.
export function markWatchedPatch(item) {
  const patch = { status: 'completed', playback: null, lastPage: null }
  if (item.type === 'show' && item.seasonProgress?.length) {
    patch.seasonProgress = item.seasonProgress.map((s) => ({ ...s, watched: s.episodeCount }))
  }
  return patch
}

// The season being watched: the first unfinished one, or the last once all are done.
export function currentSeasonIndex(item) {
  const seasons = item.seasonProgress
  if (!Array.isArray(seasons) || !seasons.length) return null
  const i = seasons.findIndex((s) => (s.watched || 0) < (s.episodeCount || 0))
  return i === -1 ? seasons.length - 1 : i
}

// Anything a reset would clear: saved time, a remembered page or watched episodes.
export function hasProgress(item) {
  return !!(item.playback || item.lastPage || item.lastWatchedAt || showTotals(item).watchedEp > 0)
}

// The ways to take back progress, as on iOS; empty when there is nothing to reset.
export function resetActions(item) {
  if (!hasProgress(item)) return []
  if (item.type !== 'show') return [{ id: 'current', destructive: false }]
  const actions = [{ id: 'current', destructive: false }]
  if (item.seasonProgress?.length) actions.push({ id: 'season', destructive: true })
  actions.push({ id: 'show', destructive: true })
  return actions
}

// Always forgets the saved time and page; `season` and `show` also unwatch episodes.
export function resetPatch(item, scope) {
  const patch = { playback: null, lastPage: null, lastWatchedAt: null }
  if (item.type !== 'show' || scope === 'current') return patch
  if (item.seasonProgress?.length) {
    const current = currentSeasonIndex(item)
    const seasons = item.seasonProgress.map((s, i) => (scope === 'show' || i === current ? { ...s, watched: 0 } : s))
    const { totalEp, watchedEp } = showTotals({ seasonProgress: seasons })
    patch.seasonProgress = seasons
    patch.status = deriveStatus(watchedEp, totalEp)
  } else if (scope === 'show') {
    patch.status = 'planned'
  }
  return patch
}

// "23:41", or "1:52:10" past an hour.
export function clock(seconds) {
  const s = Math.max(0, Math.floor(Number(seconds) || 0))
  const pad = (n) => String(n).padStart(2, '0')
  return s >= 3600 ? `${Math.floor(s / 3600)}:${pad(Math.floor((s % 3600) / 60))}:${pad(s % 60)}` : `${Math.floor(s / 60)}:${pad(s % 60)}`
}
