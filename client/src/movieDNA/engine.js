// Port of ios/Watchlist/Services/MovieDNAEngine.swift and Model/MovieDNA.swift; keep the two in step.
// Pure: settings in, settings out, so the same code serves the UI, the host and the tests.

export const BOOST_VALUE = 0.6
export const BOOST_FALLOFF = 0.8
export const BOOST_HALF_LIFE = 45
export const MAX_BOOSTS = 20
export const FOLLOW_VALUE = 2
export const NOT_INTERESTED_PENALTY = 0.4

const KINDS = ['genre', 'title', 'person']
const DAY = 86400000

export const genreKey = (name) => `genre:${String(name).trim().toLowerCase()}`
export const personKey = (tmdbID) => `person:${tmdbID}`
export const titleKey = (type, tmdbID) => `${type}:${tmdbID}`
// Typed-in titles have no TMDb id, so they fall back to the record id.
export const itemKey = (item) => (item.tmdbId ? titleKey(item.type, item.tmdbId) : `item:${item._id}`)

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))
const roundAway = (v) => Math.sign(v) * Math.round(Math.abs(v))
const strArray = (v) => (Array.isArray(v) ? v.filter((s) => typeof s === 'string') : [])
const clone = (v) => JSON.parse(JSON.stringify(v))

function parseEntry(o) {
  if (!o || typeof o !== 'object' || !KINDS.includes(o.kind)) return null
  const entry = { kind: o.kind, name: typeof o.name === 'string' ? o.name : '' }
  if (typeof o.strength === 'number') entry.strength = o.strength
  if (o.hidden === true) entry.hidden = true
  const boosts = strArray(o.boosts)
  if (boosts.length) entry.boosts = boosts
  const genres = strArray(o.genres)
  if (genres.length) entry.genres = genres
  if (typeof o.poster === 'string') entry.poster = o.poster
  if (o.followed === true) entry.followed = true
  return entry
}

function mapValues(obj, fn) {
  const out = {}
  for (const [key, value] of Object.entries(obj && typeof obj === 'object' ? obj : {})) {
    const parsed = fn(value)
    if (parsed) out[key] = parsed
  }
  return out
}

// The stored shape: what the person set, never what was learned.
export function normalizeSettings(raw) {
  return {
    enabled: typeof raw?.enabled === 'boolean' ? raw.enabled : true,
    entries: mapValues(raw?.entries, parseEntry),
    notInterested: mapValues(raw?.notInterested, (n) =>
      n && typeof n === 'object' ? { name: typeof n.name === 'string' ? n.name : '', genres: strArray(n.genres), at: typeof n.at === 'string' ? n.at : '' } : null
    ),
  }
}

const isEmpty = (e) => e.strength == null && !e.hidden && !e.boosts?.length && !e.followed

// Changes one entry, creating it if needed; entries left with nothing in them are dropped.
function edit(settings, key, kind, name, change) {
  const entry = settings.entries[key] ?? { kind, name }
  if (name) entry.name = name
  const next = change(entry) ?? entry
  if (isEmpty(next)) delete settings.entries[key]
  else settings.entries[key] = next
}

// How strongly the title itself pulls, before Interested presses.
export function score(item) {
  let s = 0
  if (item.rating > 0) s += 1.5 * clamp((item.rating - 6) / 4, -1, 1)
  else if (item.status === 'completed') s += 0.3
  if (item.favorite) s += 1
  if (item.status === 'watching') s += 0.4
  else if (item.status === 'planned') s += 0.2
  return s
}

// Later presses add less, and every press fades.
export function boost(presses, now = Date.now()) {
  return (presses ?? []).reduce((sum, press, i) => {
    const at = Date.parse(press)
    if (Number.isNaN(at)) return sum
    const days = Math.max(0, (now - at) / DAY)
    return sum + BOOST_VALUE * BOOST_FALLOFF ** i * 0.5 ** (days / BOOST_HALF_LIFE)
  }, 0)
}

// Squashes a raw score onto -100…100; `scale` is the score that reaches about 76.
export const strength = (raw, scale) => roundAway(100 * Math.tanh(raw / scale))

const EMPTY = { traits: [] }

// Returns { traits } strongest first; each trait is { key, kind, name, poster, strength, learned, isManual, boosts, followed }.
export function profile(items, settingsIn, now = Date.now()) {
  const settings = normalizeSettings(settingsIn)
  if (!settings.enabled) return EMPTY
  const { entries, notInterested } = settings
  const genreScore = {}
  const genreName = {}
  const titleScore = {}

  const feed = (genres, raw) => {
    for (const g of genres) {
      const key = genreKey(g)
      genreScore[key] = (genreScore[key] ?? 0) + raw
      genreName[key] ??= g
    }
  }

  const seen = new Set()
  for (const item of items) {
    const key = itemKey(item)
    if (seen.has(key)) continue
    seen.add(key)
    if (entries[key]?.hidden || notInterested[key]) continue
    const entry = entries[key]
    const raw = score(item) + boost(entry?.boosts, now)
    feed(item.genres ?? [], raw)
    // Titles only on the list feed their genres but aren't a trait of their own.
    if (item.rating != null || item.favorite || entry?.boosts?.length) {
      titleScore[key] = { name: item.title, poster: item.posterUrl, raw }
    }
  }
  // Titles boosted from elsewhere (Discover, a person's page) that aren't in the library.
  for (const [key, entry] of Object.entries(entries)) {
    if (entry.kind !== 'title' || seen.has(key) || entry.hidden || !entry.boosts?.length) continue
    const raw = boost(entry.boosts, now)
    feed(entry.genres ?? [], raw)
    titleScore[key] = { name: entry.name, poster: entry.poster, raw }
  }
  for (const title of Object.values(notInterested)) feed(title.genres, -NOT_INTERESTED_PENALTY)

  const traits = []
  const add = (key, kind, name, poster, learned) => {
    const entry = entries[key]
    if (entry?.hidden) return
    const value = entry?.strength ?? learned
    if (value == null) return
    traits.push({
      key,
      kind,
      name: entry?.name ? entry.name : name,
      poster: poster ?? entry?.poster ?? null,
      strength: clamp(value, -100, 100),
      learned,
      isManual: entry?.strength != null,
      boosts: entry?.boosts?.length ?? 0,
      followed: !!entry?.followed,
    })
  }

  for (const [key, raw] of Object.entries(genreScore)) add(key, 'genre', genreName[key] ?? key, null, strength(raw, 4))
  for (const [key, t] of Object.entries(titleScore)) add(key, 'title', t.name, t.poster, strength(t.raw, 1.5))
  for (const [key, entry] of Object.entries(entries)) {
    if (key in genreScore || key in titleScore) continue
    if (entry.kind === 'person') {
      const raw = (entry.followed ? FOLLOW_VALUE : 0) + boost(entry.boosts, now)
      add(key, 'person', entry.name, null, raw === 0 ? null : strength(raw, 2))
    } else {
      add(key, entry.kind, entry.name, null, null)
    }
  }
  traits.sort((a, b) => b.strength - a.strength || a.name.localeCompare(b.name))
  return { traits }
}

export const traitsOf = (dna, kind) => dna.traits.filter((t) => t.kind === kind)
export const traitFor = (dna, key) => dna.traits.find((t) => t.key === key) ?? null
export const traitType = (trait) => (trait.key.startsWith('show:') ? 'show' : 'movie')

// Inlined custom images would bloat the synced settings; the library item still has them.
export const syncablePoster = (url) => (url && !url.startsWith('data:') ? url : null)

// Mutations: each takes the stored settings and returns a changed copy.
function mutate(settings, fn) {
  const next = normalizeSettings(clone(settings))
  fn(next)
  return next
}

export const setEnabled = (settings, enabled) => mutate(settings, (s) => { s.enabled = enabled })

// One Interested press: boosts the title and its genres; it can be pressed again, and it fades.
export function markInterested(settings, item, now = Date.now()) {
  if (!normalizeSettings(settings).enabled) return normalizeSettings(settings)
  return mutate(settings, (s) => {
    edit(s, itemKey(item), 'title', item.title, (e) => {
      delete e.hidden
      e.genres = item.genres ?? []
      const poster = syncablePoster(item.posterUrl)
      if (poster) e.poster = poster
      else delete e.poster
      e.boosts = [...(e.boosts ?? []), new Date(now).toISOString()].slice(-MAX_BOOSTS)
    })
  })
}

export const interestCount = (settings, item) => settings.entries?.[itemKey(item)]?.boosts?.length ?? 0

// Sets a strength by hand; null goes back to what the library says.
export const setStrength = (settings, trait, value) =>
  mutate(settings, (s) => {
    edit(s, trait.key, trait.kind, trait.name, (e) => {
      if (value == null) delete e.strength
      else e.strength = clamp(roundAway(value), -100, 100)
    })
  })

export const addToDNA = (settings, { kind, key, name, poster, strength: value }) =>
  mutate(settings, (s) => {
    edit(s, key, kind, name, (e) => {
      delete e.hidden
      const synced = syncablePoster(poster)
      if (synced) e.poster = synced
      e.strength = clamp(roundAway(value), -100, 100)
    })
  })

// Keeps a title out of suggestions for good; its genres count a little against it.
export const markNotInterested = (settings, key, name, genres, now = Date.now()) =>
  mutate(settings, (s) => { s.notInterested[key] = { name, genres: genres ?? [], at: new Date(now).toISOString() } })

export const clearNotInterested = (settings, key) => mutate(settings, (s) => { delete s.notInterested[key] })

// Follows work with MovieDNA off too; they only count once it's on.
export const setFollowing = (settings, personID, name, photo, following) =>
  mutate(settings, (s) => {
    edit(s, personKey(personID), 'person', name, (e) => {
      if (following) e.followed = true
      else delete e.followed
      delete e.hidden
      const synced = syncablePoster(photo)
      if (following && synced) e.poster = synced
    })
  })

export const isFollowing = (settings, personID) => !!settings.entries?.[personKey(personID)]?.followed

// Takes a trait out until the next rebuild; for a person it also unfollows.
export const removeFromDNA = (settings, trait) =>
  mutate(settings, (s) => {
    edit(s, trait.key, trait.kind, trait.name, () => {
      const entry = { kind: trait.kind, name: trait.name }
      // Something learned from the library would come straight back, so it's hidden instead.
      if (trait.learned != null && !trait.followed) entry.hidden = true
      return entry
    })
  })

// Starts over from the library: drops hand edits, removals and Interested presses; follows and Not interested stay.
export const rebuild = (settings) =>
  mutate(settings, (s) => {
    const kept = {}
    for (const [key, e] of Object.entries(s.entries)) {
      if (e.followed) kept[key] = { kind: e.kind, name: e.name, followed: true }
    }
    s.entries = kept
  })
