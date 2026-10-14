// Port of TMDb.Video.youTubeKey and the trailer ordering in ios/Watchlist/Services/TMDbExtras.swift.

// The video id in a YouTube link: watch?v=, youtu.be/, /embed/, /shorts/, /live/ or /v/.
export function youTubeKey(link) {
  let url
  try {
    url = new URL(String(link ?? '').trim())
  } catch {
    return null
  }
  const host = url.hostname.toLowerCase()
  const parts = url.pathname.split('/').filter(Boolean)
  let key = null
  if (host.endsWith('youtu.be')) {
    key = parts[0]
  } else if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    key = url.searchParams.get('v') || (['embed', 'shorts', 'live', 'v'].includes(parts[0]) ? parts[1] : null)
  }
  return key && /^[A-Za-z0-9_-]{6,}$/.test(key) ? key : null
}

export const isYouTubeLink = (link) => !link || !String(link).trim() || youTubeKey(link) !== null

export const videoThumb = (key) => `https://img.youtube.com/vi/${key}/hqdefault.jpg`
export const videoWatchUrl = (key) => `https://www.youtube.com/watch?v=${key}`
export const videoEmbedUrl = (key) => `https://www.youtube-nocookie.com/embed/${key}?autoplay=1&rel=0`

const KIND_RANK = { Trailer: 0, Teaser: 1, Clip: 2, Featurette: 3 }

function videoBefore(a, b) {
  const ra = KIND_RANK[a.kind] ?? 9
  const rb = KIND_RANK[b.kind] ?? 9
  if (ra !== rb) return ra - rb
  if (a.official !== b.official) return a.official ? -1 : 1
  return (b.publishedAt || '').localeCompare(a.publishedAt || '')
}

// Overview and YouTube videos from a TMDb detail fetched with append_to_response=videos.
export function parseExtras(detail) {
  const videos = (detail?.videos?.results || [])
    .filter((v) => v.site === 'YouTube' && v.key)
    .map((v) => ({ key: v.key, name: v.name || '', kind: v.type || '', official: !!v.official, publishedAt: v.published_at || null }))
    .sort(videoBefore)
  return { overview: String(detail?.overview ?? '').trim(), videos }
}

// A pasted trailer goes first; it's the one the person picked.
export function trailerVideos(item, tmdbVideos = [], ownName = 'Trailer') {
  const key = item?.trailerUrl ? youTubeKey(item.trailerUrl) : null
  const own = key ? [{ key, name: ownName, kind: 'Trailer', official: false, publishedAt: null }] : []
  return [...own, ...tmdbVideos.filter((v) => v.key !== key)]
}
