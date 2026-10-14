// RSS/Atom to small article objects; regex-based on purpose, feeds here are simple and trusted-ish.
const ENTITIES = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ', hellip: '…', rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”', ndash: '–', mdash: '—' }

export function decode(s) {
  return s.replace(/&(?:#(\d+)|#x([\da-f]+)|([a-z]+));/gi, (m, dec, hex, name) => {
    if (name) return ENTITIES[name.toLowerCase()] ?? m
    const code = dec ? Number(dec) : parseInt(hex, 16)
    return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : m
  })
}

const unwrap = (s) => s.replace(/^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/, '$1')

// Text without tags, entities decoded, whitespace collapsed; stripped twice for Atom's escaped HTML.
export function plain(html) {
  const strip = (s) => s.replace(/<[^>]+>/g, ' ')
  return strip(decode(strip(unwrap(html ?? '')))).replace(/\s+/g, ' ').trim()
}

const tag = (block, name) => {
  const m = block.match(new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`, 'i'))
  return m ? unwrap(m[1]).trim() : null
}

const attr = (block, name, a) => {
  const m = block.match(new RegExp(`<${name}\\s[^>]*?${a}\\s*=\\s*["']([^"']+)["']`, 'i'))
  return m ? decode(m[1]) : null
}

const httpUrl = (s) => {
  try { const u = new URL(s); return /^https?:$/.test(u.protocol) ? u.href : null } catch { return null }
}

function imageOf(block) {
  const url = attr(block, 'media:thumbnail', 'url') ?? attr(block, 'media:content', 'url')
    ?? (/<enclosure\s[^>]*type=["']image/i.test(block) ? attr(block, 'enclosure', 'url') : null)
    ?? decode(unwrap(tag(block, 'content:encoded') ?? tag(block, 'description') ?? '').match(/<img\s[^>]*?src=["']([^"']+)["']/i)?.[1] ?? '')
  return url ? httpUrl(url) : null
}

const MAX_BLOCKS = 200

// Linear scan: an unclosed <item> must not make the regex rescan the rest of the document per tag.
function blocksOf(xml) {
  const open = /<(item|entry)[\s>]/gi
  const out = []
  let m
  while (out.length < MAX_BLOCKS && (m = open.exec(xml))) {
    const close = new RegExp(`</${m[1]}>`, 'gi')
    close.lastIndex = open.lastIndex
    const end = close.exec(xml)
    if (!end) break
    out.push(xml.slice(m.index, close.lastIndex))
    open.lastIndex = close.lastIndex
  }
  return out
}

export function parseFeed(xml, source) {
  const blocks = blocksOf(xml)
  const out = []
  for (const b of blocks) {
    const title = plain(tag(b, 'title') ?? '')
    const link = httpUrl(decode(tag(b, 'link') ?? attr(b, 'link', 'href') ?? ''))
    if (!title || !link) continue
    const time = Date.parse(tag(b, 'pubDate') ?? tag(b, 'published') ?? tag(b, 'updated') ?? '')
    out.push({
      title,
      link,
      published: Number.isNaN(time) ? null : new Date(time).toISOString(),
      source,
      image: imageOf(b),
      summary: plain(tag(b, 'description') ?? tag(b, 'summary') ?? ''),
    })
  }
  return out
}

// Newest first, one per link, and one per headline when outlets syndicate a story.
export function merge(articles) {
  const links = new Set()
  const headlines = new Set()
  return [...articles]
    .sort((a, b) => (b.published ?? '').localeCompare(a.published ?? ''))
    .filter((a) => {
      const headline = a.title.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '')
      if (links.has(a.link) || headlines.has(headline)) return false
      links.add(a.link)
      headlines.add(headline)
      return true
    })
}
