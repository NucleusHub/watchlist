import { test } from 'node:test'
import assert from 'node:assert/strict'
import { STANDARD, normalizeLayout, layoutRows, moveEntry } from './statsLayout.js'
import { searchAll } from './globalSearch.js'
import { hueShift, accentHex } from './accent.js'
import { buildReport, validEmail } from './report.js'

test('normalise: nothing or junk gives the standard layout', () => {
  assert.deepEqual(normalizeLayout(null), STANDARD)
  assert.deepEqual(normalizeLayout('x'), STANDARD)
})

test('normalise: drops unknown and repeated cards, appends missing ones, fixes bad fields', () => {
  const out = normalizeLayout([
    { card: 'topYears', visible: false, size: 'small' },
    { card: 'nope', visible: true, size: 'large' },
    { card: 'topYears', visible: true, size: 'large' },
    { card: 'watched', size: 'huge' },
  ])
  assert.deepEqual(out.slice(0, 2), [
    { card: 'topYears', visible: false, size: 'small' },
    { card: 'watched', visible: true, size: 'large' },
  ])
  assert.equal(out.length, STANDARD.length)
  assert.equal(new Set(out.map((e) => e.card)).size, STANDARD.length)
})

test('rows pair small cards, keep large ones alone and skip hidden or unavailable', () => {
  const rows = layoutRows(STANDARD).map((r) => r.map((e) => e.card))
  assert.deepEqual(rows, [['watched'], ['inProgress', 'planned'], ['total', 'ratings'], ['byType'], ['availableOn'], ['topYears']])
  const sparse = layoutRows(
    [
      { card: 'planned', visible: true, size: 'small' },
      { card: 'total', visible: false, size: 'small' },
      { card: 'byType', visible: true, size: 'large' },
      { card: 'ratings', visible: true, size: 'small' },
    ],
    new Set(['planned', 'byType', 'ratings', 'total'])
  ).map((r) => r.map((e) => e.card))
  assert.deepEqual(sparse, [['planned'], ['byType'], ['ratings']])
  assert.deepEqual(layoutRows(STANDARD, new Set(['topYears'])).map((r) => r.map((e) => e.card)), [['topYears']])
})

test('moveEntry reorders and ignores out-of-range moves', () => {
  const list = ['a', 'b', 'c']
  assert.deepEqual(moveEntry(list, 0, 1), ['b', 'a', 'c'])
  assert.deepEqual(moveEntry(list, 2, 0), ['c', 'a', 'b'])
  assert.equal(moveEntry(list, 0, -1), list)
  assert.equal(moveEntry(list, 2, 3), list)
})

test('search finds collections by name and titles by title or notes across lists', () => {
  const items = [{ title: 'Dune', status: 'completed' }, { title: 'Arrival', notes: 'dune-like', status: 'planned' }, { title: 'Heat' }]
  const hit = searchAll(items, [{ name: 'Sand Dune picks' }, { name: 'Other' }], '  DUNE ')
  assert.equal(hit.items.length, 2)
  assert.deepEqual(hit.collections.map((c) => c.name), ['Sand Dune picks'])
  assert.deepEqual(searchAll(items, [], '   '), { collections: [], items: [] })
})

test('accent: preset and custom hex resolve, hue shift is zero for the default', () => {
  assert.equal(accentHex({ id: 'ember' }), '#F2711C')
  assert.equal(accentHex({ id: 'custom', custom: '#123456' }), '#123456')
  assert.equal(accentHex({ id: 'custom', custom: 'red' }), null)
  assert.equal(accentHex({ id: 'unknown' }), null)
  assert.equal(hueShift('#A855F7'), 0)
  assert.ok(hueShift('#2FA36B') < -100)
})

test('report body follows the iOS payload and skips an empty email', () => {
  const body = buildReport({ title: ' Bug ', details: ' It broke ', email: ' ', shots: ['abc'], version: '0.7.0', locale: 'en-US', ua: 'Mozilla/5.0 (Macintosh)', platform: 'MacIntel' })
  assert.equal(body.title, 'Bug')
  assert.equal(body.email, undefined)
  assert.equal(body.app.id, 'watchlist')
  assert.equal(body.device.platform, 'web')
  assert.equal(body.device.os, 'macos')
  assert.deepEqual(body.attachments, [{ type: 'image/jpeg', data: 'abc' }])
  assert.equal(buildReport({ title: 't', details: 'd', email: 'a@b.cz', shots: [], version: '', locale: 'cs', ua: '' }).email, 'a@b.cz')
  assert.ok(validEmail('') && validEmail('a@b.cz') && !validEmail('nope'))
})
