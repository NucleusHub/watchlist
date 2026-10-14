// Pure part of the cross-app side of Nucleus ID, same semantics as ios/Watchlist/Account/CrossApp.swift:
// the `library` view other apps read, and the markWatched / unmarkWatched commands they send.

const TYPES = ['markWatched', 'unmarkWatched']

const rejected = (reason) => ({ status: 'rejected', result: { reason } })
const applied = (result, patch = {}) => ({ status: 'applied', result, patch })

export function libraryView(items) {
  const sorted = [...items].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt) || String(a._id).localeCompare(String(b._id)))
  return {
    items: sorted.map((i) => ({
      id: String(i._id),
      title: i.title,
      type: i.type,
      tmdbId: i.tmdbId ?? null,
      // Inlined/uploaded posters aren't reachable from other apps.
      poster: /^https?:/.test(i.posterUrl ?? '') ? i.posterUrl : null,
      status: i.status,
      seasons: i.type === 'show'
        ? (i.seasonProgress ?? []).map((s) => ({ number: s.seasonNumber, name: s.name ?? '', episodeCount: s.episodeCount ?? 0, watched: s.watched ?? 0 }))
        : [],
    })),
  }
}

const totals = (seasons) => seasons.reduce(
  (t, s) => ({ total: t.total + Math.max(0, s.episodeCount), watched: t.watched + Math.min(Math.max(0, s.watched), Math.max(0, s.episodeCount)) }),
  { total: 0, watched: 0 },
)

const statusOf = ({ total, watched }) => (total > 0 && watched >= total ? 'completed' : watched > 0 ? 'watching' : 'planned')

// undefined when absent or null, NaN when not a whole number.
const optInt = (v) => (v == null ? undefined : Number.isInteger(v) ? v : NaN)

// Only what changed, with completedAt following the status.
function diff(item, next) {
  const patch = {}
  for (const k of ['seasonProgress', 'status', 'playback', 'lastPage']) {
    if (JSON.stringify(next[k] ?? null) !== JSON.stringify(item[k] ?? null)) patch[k] = next[k] ?? null
  }
  if (patch.status) patch.completedAt = patch.status === 'completed' ? new Date() : null
  return patch
}

function setSeasons(item, seasons) {
  return { ...item, seasonProgress: seasons, status: statusOf(totals(seasons)) }
}

// Safe to repeat: marks only add progress and unmarks only take it back.
export function applyCommand(type, payload, item) {
  if (!TYPES.includes(type)) return rejected('unknownType')
  const p = payload && typeof payload === 'object' ? payload : null
  const [season, fromEp, toEp, restoreTo] = ['season', 'fromEp', 'toEp', 'restoreTo'].map((k) => optInt(p?.[k]))
  if (!p || typeof p.itemId !== 'string' || !p.itemId || [season, fromEp, toEp, restoreTo].some(Number.isNaN)) return rejected('badPayload')
  if (!item) return rejected('itemNotFound')

  const isShow = item.type === 'show'
  const seasons = isShow ? item.seasonProgress ?? [] : []
  const seasonNumber = isShow ? season : undefined
  const current = seasonNumber === undefined ? undefined : seasons.find((s) => s.seasonNumber === seasonNumber)
  if (seasonNumber !== undefined && !current) return rejected('seasonNotFound')
  const previousStatus = item.status
  const previousWatched = current?.watched
  const result = previousWatched === undefined ? { previousStatus } : { previousWatched, previousStatus }
  const done = (next) => applied(result, diff(item, next))

  const mapSeason = (n, fn) => seasons.map((s) => (s.seasonNumber === n ? { ...s, watched: fn(s) } : s))

  if (type === 'markWatched') {
    if (seasonNumber !== undefined) {
      if (fromEp !== undefined && fromEp < 1) return rejected('badPayload')
      const through = toEp ?? current.episodeCount
      if (through < (fromEp ?? 1)) return rejected('badPayload')
      const next = setSeasons(item, mapSeason(seasonNumber, (s) => Math.max(s.watched, Math.min(through, s.episodeCount))))
      const after = next.seasonProgress.find((s) => s.seasonNumber === seasonNumber).watched
      return applied({ previousWatched: previousWatched ?? 0, watched: after, previousStatus }, diff(item, next))
    }
    const t = totals(seasons)
    const alreadyDone = item.status === 'completed' && (!seasons.length || t.watched >= t.total)
    const next = alreadyDone ? item : {
      ...item, status: 'completed', playback: null, lastPage: null,
      seasonProgress: seasons.length ? seasons.map((s) => ({ ...s, watched: s.episodeCount })) : item.seasonProgress,
    }
    // A whole show marks every season, so an unmark needs each one's count to put back.
    return applied(
      seasons.length ? { previousStatus, previousSeasons: seasons.map((s) => ({ number: s.seasonNumber, watched: s.watched })) } : result,
      diff(item, next),
    )
  }

  if (seasonNumber !== undefined && restoreTo !== undefined) {
    const expected = optInt(p.expectWatched)
    if (restoreTo < 0 || Number.isNaN(expected)) return rejected('badPayload')
    // Watched past what the task marked: rolling back would take that progress too.
    if (expected !== undefined && previousWatched > expected) return rejected('progressMoved')
    return done(setSeasons(item, mapSeason(seasonNumber, (s) => Math.min(s.watched, restoreTo))))
  }
  if (isShow && Array.isArray(p.restoreSeasons)) {
    const keep = new Map()
    for (const s of p.restoreSeasons) {
      if (s && Number.isInteger(s.number) && Number.isInteger(s.watched) && s.watched >= 0) keep.set(s.number, Math.min(s.watched, keep.get(s.number) ?? Infinity))
    }
    return done(setSeasons(item, seasons.map((s) => (keep.has(s.seasonNumber) ? { ...s, watched: Math.min(s.watched, keep.get(s.seasonNumber)) } : s))))
  }
  if (!['planned', 'watching', 'completed'].includes(p.restoreStatus)) return rejected('badPayload')
  return done(item.status === 'completed' && p.restoreStatus !== 'completed' ? { ...item, status: p.restoreStatus } : item)
}

