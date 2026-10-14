// Ported from the YouTube link rules in ios/Watchlist/Services/TMDbExtras.swift. Run: npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { youTubeKey, isYouTubeLink, parseExtras, trailerVideos } from './trailers.js'
import { jobForDepartment, creditFromPerson } from './credits.js'

test('youTubeKey reads every link shape', () => {
  for (const link of [
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3s',
    'https://youtu.be/dQw4w9WgXcQ?si=abc',
    'https://www.youtube.com/embed/dQw4w9WgXcQ',
    'https://www.youtube.com/shorts/dQw4w9WgXcQ',
    'https://www.youtube.com/live/dQw4w9WgXcQ',
    'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
    '  https://m.youtube.com/watch?v=dQw4w9WgXcQ  ',
  ]) assert.equal(youTubeKey(link), 'dQw4w9WgXcQ', link)
})

test('youTubeKey rejects what is not a YouTube video', () => {
  for (const link of ['', 'not a link', 'youtu.be/dQw4w9WgXcQ', 'https://vimeo.com/123456789', 'https://www.youtube.com/', 'https://youtu.be/abc', 'https://youtu.be/bad key!']) {
    assert.equal(youTubeKey(link), null, link)
  }
})

test('an empty trailer field is valid, a bad link is not', () => {
  assert.equal(isYouTubeLink(''), true)
  assert.equal(isYouTubeLink(null), true)
  assert.equal(isYouTubeLink('https://youtu.be/dQw4w9WgXcQ'), true)
  assert.equal(isYouTubeLink('https://example.com'), false)
})

test('parseExtras keeps YouTube videos, trailers first, official first, newest first', () => {
  const { overview, videos } = parseExtras({
    overview: '  A film.  ',
    videos: { results: [
      { site: 'Vimeo', key: 'vimeo1', type: 'Trailer' },
      { site: 'YouTube', key: 'clip001', type: 'Clip', official: true, published_at: '2024-01-01' },
      { site: 'YouTube', key: 'fan0001', type: 'Trailer', official: false, published_at: '2024-05-01' },
      { site: 'YouTube', key: 'old0001', type: 'Trailer', official: true, published_at: '2023-01-01' },
      { site: 'YouTube', key: 'new0001', type: 'Trailer', official: true, published_at: '2024-02-01' },
    ] },
  })
  assert.equal(overview, 'A film.')
  assert.deepEqual(videos.map((v) => v.key), ['new0001', 'old0001', 'fan0001', 'clip001'])
})

test('a pasted trailer goes first and is not repeated', () => {
  const tmdb = [{ key: 'aaaaaaa', name: 'A' }, { key: 'bbbbbbb', name: 'B' }]
  assert.deepEqual(trailerVideos({ trailerUrl: 'https://youtu.be/bbbbbbb' }, tmdb).map((v) => v.key), ['bbbbbbb', 'aaaaaaa'])
  assert.deepEqual(trailerVideos({ trailerUrl: 'junk' }, tmdb).map((v) => v.key), ['aaaaaaa', 'bbbbbbb'])
})

test('credits: department picks the job, actors are cast', () => {
  assert.equal(jobForDepartment('Directing'), 'Director')
  assert.equal(jobForDepartment('Acting'), null)
  assert.deepEqual(creditFromPerson({ id: 5, name: 'A', knownFor: 'Acting', photo: 'p' }), { name: 'A', role: '', cast: true, personId: 5, photo: 'p' })
  assert.deepEqual(creditFromPerson({ id: 6, name: 'B', knownFor: 'Sound' }), { name: 'B', role: 'Composer', cast: false, personId: 6, photo: null })
})
