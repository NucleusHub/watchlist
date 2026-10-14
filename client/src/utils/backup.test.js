// Run: npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildBackup, parseBackup, planImport, itemPayload, collectionPayload, remapIds, newerAccent, backupFileName } from './backup.js'

const id = (n) => String(n).padStart(24, 'a')
const item = (n, extra = {}) => ({ _id: id(n), title: `T${n}`, type: 'movie', updatedAt: '2026-01-01T00:00:00.000Z', ...extra })
const col = (n, extra = {}) => ({ _id: id(100 + n), name: `C${n}`, updatedAt: '2026-01-01T00:00:00.000Z', ...extra })

test('export carries the iOS format and drops server-only fields', () => {
  const now = new Date('2026-03-04T05:06:07.000Z')
  const doc = buildBackup({
    items: [{ ...item(1), profileId: 'p', __v: 0 }],
    collections: [{ ...col(1), itemCount: 3, previewPosters: [], coverPosters: [] }],
    settings: { searchSources: ['tmdb'] },
  }, now)
  assert.equal(doc.format, 'nucleus-watchlist')
  assert.equal(doc.version, 1)
  assert.equal(doc.exportedAt, '2026-03-04T05:06:07.000Z')
  assert.deepEqual(doc.deleted, {})
  assert.equal(doc.items[0].profileId, undefined)
  assert.equal(doc.collections[0].itemCount, undefined)
  assert.equal(doc.settings.updatedAt, doc.exportedAt)
  assert.equal(backupFileName(now), 'watchlist-2026-03-04.json')
})

test('parse takes an iOS backup and drops records without id or title', () => {
  const text = JSON.stringify({
    format: 'nucleus-watchlist', version: 1, exportedAt: '2026-01-02T00:00:00.000Z',
    items: [item(1), { _id: id(2) }, { title: 'no id' }], collections: [col(1), { _id: id(9), name: '' }],
    settings: { accent: { id: 'ember', updatedAt: '2026-01-01T00:00:00.000Z' } }, deleted: { x: 'y' },
  })
  const doc = parseBackup(text)
  assert.equal(doc.items.length, 1)
  assert.equal(doc.collections.length, 1)
  assert.equal(doc.settings.accent.id, 'ember')
  assert.equal(doc.exportedAt, '2026-01-02T00:00:00.000Z')
})

test('parse rejects anything that is not a backup', () => {
  for (const bad of ['nope', '{}', '[]', JSON.stringify({ format: 'other', items: [] }), JSON.stringify({ format: 'nucleus-watchlist' })]) {
    assert.throws(() => parseBackup(bad), /notABackup/)
  }
})

test('merge adds new records and takes only newer ones', () => {
  const current = { items: [item(1), item(2, { updatedAt: '2026-06-01T00:00:00.000Z' })], collections: [col(1)] }
  const file = {
    items: [item(1, { updatedAt: '2026-02-01T00:00:00.000Z' }), item(2), item(3)],
    collections: [col(1), col(2)],
  }
  const plan = planImport(current, file, false)
  assert.deepEqual(plan.items.map((p) => [p.record._id, p.id]), [[id(1), id(1)], [id(3), undefined]])
  assert.deepEqual(plan.collections.map((p) => p.record._id), [id(102)])
  assert.deepEqual([plan.deleteItems, plan.deleteCollections], [[], []])
})

test('replace upserts every file record and leaves only the leftovers to delete', () => {
  const current = { items: [item(1, { updatedAt: '2026-06-01T00:00:00.000Z' }), item(2)], collections: [col(1)] }
  const plan = planImport(current, { items: [item(1), item(3)], collections: [] }, true)
  assert.deepEqual(plan.items.map((p) => [p.record._id, p.id]), [[id(1), id(1)], [id(3), undefined]])
  assert.deepEqual(plan.deleteItems, [id(2)])
  assert.deepEqual(plan.deleteCollections, [id(101)])
})

test('parse drops items the server would reject and counts them', () => {
  const text = JSON.stringify({
    format: 'nucleus-watchlist',
    items: [
      item(1), item(2, { type: 'anime' }), item(3, { type: undefined }), item(4, { status: 'dropped' }),
      item(5, { status: 'watching', seasonProgress: [{ seasonNumber: 1 }] }),
      item(6, { seasonProgress: [{ name: 'no number' }] }), item(7, { seasonProgress: 'x' }),
    ],
    collections: [col(1), { _id: id(9) }],
  })
  const doc = parseBackup(text)
  assert.deepEqual(doc.items.map((i) => i._id), [id(1), id(5)])
  assert.equal(doc.skipped, 6)
})

test('payloads keep ObjectId item ids and only the writable collection fields', () => {
  assert.equal(itemPayload(item(1))._id, id(1))
  assert.equal(itemPayload({ ...item(1), _id: 'local-uuid' })._id, undefined)
  assert.deepEqual(collectionPayload({ ...col(1), kind: 'smart', parentId: 'x', coverCount: 4, description: 'd' }), { _id: id(101), name: 'C1', description: 'd', coverCount: 4 })
  assert.equal(collectionPayload({ ...col(1), _id: 'local', coverItemIds: ['x'] })._id, undefined)
  assert.equal(collectionPayload({ ...col(1), coverItemIds: ['x'] }).coverItemIds, undefined)
})

test('remapIds translates known ids and drops the rest', () => {
  assert.deepEqual(remapIds(['a', 'b', 'c'], new Map([['a', 'A'], ['c', 'C']])), ['A', 'C'])
  assert.deepEqual(remapIds(undefined, new Map()), [])
})

test('newest accent wins, and one that was never picked loses', () => {
  const old = { id: 'ember', updatedAt: '2026-01-01T00:00:00.000Z' }
  const fresh = { id: 'arctic', updatedAt: '2026-02-01T00:00:00.000Z' }
  assert.equal(newerAccent(old, fresh), fresh)
  assert.equal(newerAccent(fresh, old), fresh)
  assert.equal(newerAccent(null, old), old)
  assert.equal(newerAccent(old, null), old)
  assert.equal(newerAccent(null, null), null)
})
