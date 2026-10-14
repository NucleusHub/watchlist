import test from 'node:test'
import assert from 'node:assert/strict'
import { applyCommand, libraryView } from './crossAppLogic.js'

const show = (watched = [0, 0], status = 'planned') => ({
  _id: 'a', type: 'show', status, playback: { url: 'u', position: 1, duration: 2 }, lastPage: 'p',
  seasonProgress: watched.map((w, i) => ({ seasonNumber: i + 1, name: `S${i + 1}`, episodeCount: 10, watched: w })),
})
const movie = (status = 'planned') => ({ _id: 'm', type: 'movie', status, playback: null, lastPage: 'p' })

test('libraryView shapes items newest first and drops non-http posters', () => {
  const v = libraryView([
    { _id: 'a', title: 'A', type: 'show', status: 'watching', posterUrl: '/uploads/x.jpg', createdAt: '2026-01-01', seasonProgress: [{ seasonNumber: 1, name: 'S1', episodeCount: 8, watched: 3 }] },
    { _id: 'b', title: 'B', type: 'movie', status: 'planned', posterUrl: 'https://i/p.jpg', tmdbId: 5, createdAt: '2026-02-01' },
  ])
  assert.deepEqual(v.items.map((i) => i.id), ['b', 'a'])
  assert.equal(v.items[0].poster, 'https://i/p.jpg')
  assert.equal(v.items[1].poster, null)
  assert.deepEqual(v.items[1].seasons, [{ number: 1, name: 'S1', episodeCount: 8, watched: 3 }])
})

test('rejects unknown type, bad payload, missing item and season', () => {
  assert.equal(applyCommand('nope', {}, null).result.reason, 'unknownType')
  assert.equal(applyCommand('markWatched', { itemId: 'a', season: 1.5 }, show()).result.reason, 'badPayload')
  assert.equal(applyCommand('markWatched', { itemId: 'a' }, null).result.reason, 'itemNotFound')
  assert.equal(applyCommand('markWatched', { itemId: 'a', season: 9 }, show()).result.reason, 'seasonNotFound')
})

test('markWatched on a movie completes it and clears resume state', () => {
  const r = applyCommand('markWatched', { itemId: 'm' }, movie())
  assert.equal(r.status, 'applied')
  assert.deepEqual(r.result, { previousStatus: 'planned' })
  assert.equal(r.patch.status, 'completed')
  assert.equal(r.patch.lastPage, null)
  assert.ok(r.patch.completedAt instanceof Date)
})

test('markWatched on a season range only adds progress', () => {
  const r = applyCommand('markWatched', { itemId: 'a', season: 1, fromEp: 1, toEp: 4 }, show([6, 0], 'watching'))
  assert.deepEqual(r.result, { previousWatched: 6, watched: 6, previousStatus: 'watching' })
  assert.deepEqual(r.patch, {})
  const r2 = applyCommand('markWatched', { itemId: 'a', season: 2, toEp: 4 }, show([6, 0], 'watching'))
  assert.equal(r2.patch.seasonProgress[1].watched, 4)
  assert.equal(r2.result.watched, 4)
})

test('markWatched on a whole show reports previousSeasons and completes', () => {
  const r = applyCommand('markWatched', { itemId: 'a' }, show([2, 0], 'watching'))
  assert.deepEqual(r.result.previousSeasons, [{ number: 1, watched: 2 }, { number: 2, watched: 0 }])
  assert.equal(r.patch.status, 'completed')
  assert.deepEqual(r.patch.seasonProgress.map((s) => s.watched), [10, 10])
})

test('unmarkWatched season rollback, guarded by expectWatched', () => {
  const ok = applyCommand('unmarkWatched', { itemId: 'a', season: 1, restoreTo: 2, expectWatched: 10 }, show([10, 10], 'completed'))
  assert.equal(ok.patch.seasonProgress[0].watched, 2)
  assert.equal(ok.patch.status, 'watching')
  assert.equal(applyCommand('unmarkWatched', { itemId: 'a', season: 1, restoreTo: 2, expectWatched: 5 }, show([8, 0])).result.reason, 'progressMoved')
})

test('unmarkWatched restoreSeasons and restoreStatus', () => {
  const r = applyCommand('unmarkWatched', { itemId: 'a', restoreSeasons: [{ number: 1, watched: 0 }, { number: 2, watched: 0 }] }, show([10, 10], 'completed'))
  assert.equal(r.patch.status, 'planned')
  assert.equal(r.patch.completedAt, null)
  const m = applyCommand('unmarkWatched', { itemId: 'm', restoreStatus: 'planned' }, movie('completed'))
  assert.equal(m.patch.status, 'planned')
  assert.equal(applyCommand('unmarkWatched', { itemId: 'm' }, movie('completed')).result.reason, 'badPayload')
})
