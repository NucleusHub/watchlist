// Ported from ios/WatchlistTests/MovieDNATests.swift. Run: npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import * as dna from './engine.js'

let n = 0
const item = (title, tmdbId, genres, extra = {}) => ({ _id: `id${++n}`, title, type: 'movie', tmdbId, genres, status: 'completed', ...extra })
const empty = () => dna.normalizeSettings(null)
const profile = (items, settings = empty(), now) => dna.profile(items, settings, now)

test('ratings and favorites shape genres', () => {
  const items = [item('Alien', 348, ['Horror', 'Sci-Fi'], { rating: 10, favorite: true }), item('Bad Rom-Com', 1, ['Romance'], { rating: 2 })]
  const p = profile(items)
  assert.ok(dna.traitFor(p, dna.genreKey('Horror')).strength > 0)
  assert.ok(dna.traitFor(p, dna.genreKey('romance')).strength < 0)
  assert.equal(dna.traitsOf(p, 'title')[0].name, 'Alien')
  assert.equal(p.traits[0].kind, 'title')
})

test('list-only titles feed genres but are no trait', () => {
  const planned = item('Planned', 5, ['Drama'], { status: 'planned' })
  const p = profile([planned])
  assert.equal(dna.traitFor(p, dna.itemKey(planned)), null)
  assert.ok(dna.traitFor(p, dna.genreKey('Drama')).strength > 0)
})

test('neutral genres stay and titles carry posters', () => {
  const meh = item('Meh', 7, ['Comedy'], { rating: 6, posterUrl: 'https://image.tmdb.org/t/p/w500/x.jpg' })
  const p = profile([meh])
  assert.equal(dna.traitFor(p, dna.genreKey('Comedy')).strength, 0)
  assert.equal(dna.traitFor(p, dna.itemKey(meh)).poster, meh.posterUrl)
  const s = dna.addToDNA(empty(), { kind: 'title', key: 'movie:99', name: 'Elsewhere', poster: 'data:image/png;base64,AAAA', strength: 40 })
  assert.equal(s.entries['movie:99'].poster, undefined)
})

test('interested stacks with falloff and fades', () => {
  const now = Date.now()
  const at = new Date(now).toISOString()
  const one = dna.boost([at], now)
  const two = dna.boost([at, at], now)
  assert.ok(Math.abs(one - dna.BOOST_VALUE) < 1e-4)
  assert.ok(two > one && two < 2 * one)
  const old = dna.boost([new Date(now - dna.BOOST_HALF_LIFE * 86400000).toISOString()], now)
  assert.ok(Math.abs(old - one / 2) < 1e-4)
})

test('interested presses are counted and capped', () => {
  const dune = item('Dune', 438631, ['Sci-Fi'], { status: 'planned', type: 'movie' })
  let s = empty()
  for (let i = 0; i < dna.MAX_BOOSTS + 5; i++) s = dna.markInterested(s, dune)
  assert.equal(dna.interestCount(s, dune), dna.MAX_BOOSTS)
  const trait = dna.traitFor(profile([dune], s), dna.itemKey(dune))
  assert.equal(trait.boosts, dna.MAX_BOOSTS)
  assert.ok(trait.strength > 0)
})

test('manual strength overrides and resets', () => {
  const items = [item('Alien', 348, ['Horror'], { rating: 9 })]
  const horror = dna.traitFor(profile(items), dna.genreKey('Horror'))
  let s = dna.setStrength(empty(), horror, -40)
  let t = dna.traitFor(profile(items, s), horror.key)
  assert.equal(t.strength, -40)
  assert.equal(t.isManual, true)
  s = dna.setStrength(s, horror, null)
  assert.equal(dna.traitFor(profile(items, s), horror.key).strength, horror.learned)
  assert.equal(s.entries[horror.key], undefined)
})

test('a removed learned trait stays out and stops feeding genres', () => {
  const alien = item('Alien', 348, ['Horror'], { rating: 10 })
  const title = dna.traitFor(profile([alien]), dna.itemKey(alien))
  const p = profile([alien], dna.removeFromDNA(empty(), title))
  assert.equal(dna.traitFor(p, title.key), null)
  assert.equal(dna.traitFor(p, dna.genreKey('Horror')), null)
})

test('added traits can be removed again', () => {
  let s = dna.addToDNA(empty(), { kind: 'genre', key: dna.genreKey('Western'), name: 'Western', strength: 73 })
  const western = dna.traitFor(profile([], s), dna.genreKey('Western'))
  assert.equal(western.strength, 73)
  assert.equal(western.learned, null)
  s = dna.removeFromDNA(s, western)
  assert.equal(dna.traitFor(profile([], s), western.key), null)
  assert.deepEqual(s.entries, {})
})

test('rebuild keeps follows and not interested only', () => {
  const alien = item('Alien', 348, ['Horror'], { rating: 10 })
  let s = dna.markInterested(empty(), alien)
  s = dna.addToDNA(s, { kind: 'genre', key: dna.genreKey('Western'), name: 'Western', strength: 50 })
  s = dna.setFollowing(s, 287, 'Brad Pitt', null, true)
  s = dna.markNotInterested(s, 'movie:9', 'Nope', ['Romance'])
  s = dna.rebuild(s)
  assert.deepEqual(Object.keys(s.entries), [dna.personKey(287)])
  assert.ok(s.notInterested['movie:9'])
  const p = profile([alien], s)
  assert.equal(dna.traitFor(p, dna.personKey(287)).followed, true)
  assert.ok(dna.traitFor(p, dna.genreKey('Romance')).strength < 0)
})

test('disabled learns nothing and keeps entries', () => {
  const alien = item('Alien', 348, ['Horror'], { rating: 10 })
  let s = dna.addToDNA(empty(), { kind: 'genre', key: dna.genreKey('Western'), name: 'Western', strength: 50 })
  s = dna.setEnabled(s, false)
  assert.deepEqual(profile([alien], s).traits, [])
  s = dna.markInterested(s, alien)
  assert.equal(dna.interestCount(s, alien), 0)
  s = dna.setEnabled(s, true)
  assert.equal(dna.traitFor(profile([alien], s), dna.genreKey('Western')).strength, 50)
})

test('settings round-trip through JSON and unfollow drops the entry', () => {
  let s = dna.setFollowing(empty(), 1, 'A', null, true)
  assert.deepEqual(dna.normalizeSettings(JSON.parse(JSON.stringify(s))), s)
  s = dna.setFollowing(s, 1, 'A', null, false)
  assert.deepEqual(s.entries, {})
})

test('title keys match across types and typed-in titles', () => {
  assert.equal(dna.itemKey({ _id: 'abc', type: 'movie', title: 'Home video' }), 'item:abc')
  assert.equal(dna.itemKey({ _id: 'x', type: 'show', tmdbId: 1399 }), 'show:1399')
  assert.equal(dna.genreKey(' Sci-Fi '), 'genre:sci-fi')
})
