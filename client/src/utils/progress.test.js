// Ported from ios/WatchlistTests/StoreTests.swift (reset and mark watched). Run: npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { markWatchedPatch, resetActions, resetPatch, hasProgress, currentSeasonIndex, clock } from './progress.js'

const show = (extra = {}) => ({
  type: 'show', status: 'watching',
  seasonProgress: [
    { seasonNumber: 1, episodeCount: 10, watched: 10 },
    { seasonNumber: 2, episodeCount: 8, watched: 3 },
  ],
  ...extra,
})

test('mark watched spends playback and page and completes every season', () => {
  const patch = markWatchedPatch(show())
  assert.equal(patch.status, 'completed')
  assert.equal(patch.playback, null)
  assert.equal(patch.lastPage, null)
  assert.deepEqual(patch.seasonProgress.map((s) => s.watched), [10, 8])
  assert.equal('seasonProgress' in markWatchedPatch({ type: 'movie' }), false)
})

test('reset actions fit the title', () => {
  assert.deepEqual(resetActions(show()).map((a) => a.id), ['current', 'season', 'show'])
  assert.deepEqual(resetActions(show()).map((a) => a.destructive), [false, true, true])
  assert.equal(resetActions({ type: 'movie' }).length, 0)
  assert.deepEqual(resetActions({ type: 'movie', playback: { url: 'x', position: 1, duration: 9 } }).map((a) => a.id), ['current'])
  assert.deepEqual(resetActions({ type: 'show', lastPage: 'https://x.test' }).map((a) => a.id), ['current', 'show'])
})

test('the current season is the first unfinished one, else the last', () => {
  assert.equal(currentSeasonIndex(show()), 1)
  assert.equal(currentSeasonIndex(show({ seasonProgress: [{ episodeCount: 2, watched: 2 }, { episodeCount: 3, watched: 3 }] })), 1)
  assert.equal(currentSeasonIndex({ type: 'show' }), null)
})

test('reset current only forgets the saved time and page', () => {
  const patch = resetPatch(show({ playback: { url: 'x', position: 1, duration: 9 } }), 'current')
  assert.deepEqual(patch, { playback: null, lastPage: null, lastWatchedAt: null })
})

test('reset season unwatches the season in progress and status follows', () => {
  const patch = resetPatch(show(), 'season')
  assert.deepEqual(patch.seasonProgress.map((s) => s.watched), [10, 0])
  assert.equal(patch.status, 'watching')
})

test('reset show unwatches everything', () => {
  const patch = resetPatch(show(), 'show')
  assert.deepEqual(patch.seasonProgress.map((s) => s.watched), [0, 0])
  assert.equal(patch.status, 'planned')
  assert.equal(resetPatch({ type: 'show', status: 'watching' }, 'show').status, 'planned')
  assert.equal('status' in resetPatch({ type: 'show', status: 'watching' }, 'season'), false)
})

test('a movie only ever forgets time and page', () => {
  assert.equal('status' in resetPatch({ type: 'movie', status: 'completed' }, 'show'), false)
})

test('has progress', () => {
  assert.equal(hasProgress({ type: 'movie' }), false)
  assert.equal(hasProgress(show()), true)
  assert.equal(hasProgress({ type: 'movie', lastWatchedAt: '2026-01-01' }), true)
})

test('clock', () => {
  assert.equal(clock(1421), '23:41')
  assert.equal(clock(6730), '1:52:10')
  assert.equal(clock(-3), '0:00')
})
