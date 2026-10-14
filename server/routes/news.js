import { Router } from 'express'
import { requireAuth } from '../middleware/auth.js'
import { parseFeed, merge } from '../newsParse.js'

// Fixed list (same as iOS): the proxy never fetches a URL the client supplies.
const FEEDS = [
  { name: 'Variety', url: 'https://variety.com/feed/' },
  { name: 'Deadline', url: 'https://deadline.com/feed/' },
  { name: 'The Hollywood Reporter', url: 'https://www.hollywoodreporter.com/feed/' },
  { name: 'IndieWire', url: 'https://www.indiewire.com/feed/' },
  { name: '/Film', url: 'https://www.slashfilm.com/feed/' },
]
const MAX_AGE = 15 * 60 * 1000
const MAX_BYTES = 3 * 1024 * 1024
const MAX_ARTICLES = 150

const HOSTS = new Set(FEEDS.map((f) => new URL(f.url).host))

// Redirects are followed by hand so they can't leave the feed hosts.
async function fetchFollowing(url) {
  let target = url
  for (let hop = 0; hop < 4; hop++) {
    const res = await fetch(target, { redirect: 'manual', signal: AbortSignal.timeout(15000), headers: { 'User-Agent': 'Watchlist (web)' } })
    const location = res.status >= 300 && res.status < 400 && res.headers.get('location')
    if (!location) return res
    const next = new URL(location, target)
    if (next.protocol !== 'https:' || !HOSTS.has(next.host)) throw new Error('redirect')
    target = next.href
  }
  throw new Error('redirect')
}

async function fetchFeed({ name, url }) {
  const res = await fetchFollowing(url)
  if (!res.ok) throw new Error(`${res.status}`)
  const chunks = []
  let size = 0
  for await (const chunk of res.body) {
    size += chunk.length
    if (size > MAX_BYTES) throw new Error('too large')
    chunks.push(chunk)
  }
  return parseFeed(Buffer.concat(chunks).toString('utf8'), name)
}

let cache = null
let pending = null

async function load() {
  const results = await Promise.allSettled(FEEDS.map(fetchFeed))
  const articles = merge(results.flatMap((r) => (r.status === 'fulfilled' ? r.value : []))).slice(0, MAX_ARTICLES)
  const failed = FEEDS.filter((_, i) => results[i].status === 'rejected').map((f) => f.name).sort()
  // Keep the last good list when every source failed.
  if (!articles.length && cache?.articles.length) return { ...cache, failed, loadedAt: Date.now() }
  return { articles, failed, loadedAt: Date.now() }
}

const router = Router()
router.use(requireAuth)

// { articles: [{ title, link, published, source, image, summary }], failed: [source names] }
router.get('/', async (req, res) => {
  const fresh = req.query.refresh === '1' ? cache?.articles.length && Date.now() - cache.loadedAt < 60_000 : cache?.articles.length && Date.now() - cache.loadedAt < MAX_AGE
  if (!fresh) {
    pending ??= load().finally(() => { pending = null })
    cache = await pending
  }
  res.json({ articles: cache.articles, failed: cache.failed })
})

export default router
