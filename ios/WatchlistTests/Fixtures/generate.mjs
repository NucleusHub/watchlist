// Runs the original web app's merge (reference-localDb.js, frozen from the retired Vue client)
// on the cases below and writes what it returns to merge-cases.json, which MergeTests checks
// the Swift port against. Documents synced by that app must keep merging the same way.
// Re-run after changing either side: node ios/WatchlistTests/Fixtures/generate.mjs
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const here = (p) => fileURLToPath(new URL(p, import.meta.url))
const NOW = Date.parse('2026-10-01T12:00:00.000Z')

// localDb.js imports Vue and Capacitor storage; the merge itself needs neither.
const source = readFileSync(here('./reference-localDb.js'), 'utf8')
  .replace(/^import .*$/gm, '')
  .replace(/^export /gm, '')
  .replaceAll('Date.now()', '__NOW')
const { mergeDocs, fingerprint, normalizeDoc } = new Function(
  'ref', 'readJson', 'writeJson', '__NOW',
  `${source}; return { mergeDocs, fingerprint, normalizeDoc }`
)((v) => ({ value: v }), async () => null, async () => {}, NOW)

const item = (id, title, updatedAt, extra = {}) => ({
  _id: id, title, type: 'movie', status: 'planned', createdAt: '2026-01-01T00:00:00.000Z', updatedAt, ...extra,
})
const col = (id, name, updatedAt, extra = {}) => ({ _id: id, name, createdAt: '2026-01-01T00:00:00.000Z', updatedAt, ...extra })
const settings = (updatedAt, extra = {}) => ({ openDefaults: null, searchSources: ['tmdb'], pluginPlacements: {}, tmdbApiKey: '', updatedAt, ...extra })

const cases = {
  newerRemoteWins: [
    { items: [item('a', 'Local', '2026-05-01T00:00:00.000Z')] },
    { items: [item('a', 'Remote', '2026-06-01T00:00:00.000Z')] },
  ],
  tieKeepsLocal: [
    { items: [item('a', 'Local', '2026-05-01T00:00:00.000Z')] },
    { items: [item('a', 'Remote', '2026-05-01T00:00:00.000Z')] },
  ],
  unionKeepsOrder: [
    { items: [item('b', 'B', '2026-05-01T00:00:00.000Z'), item('a', 'A', '2026-05-01T00:00:00.000Z')] },
    { items: [item('c', 'C', '2026-05-01T00:00:00.000Z'), item('a', 'A2', '2026-07-01T00:00:00.000Z')] },
  ],
  deleteBeatsOlderEdit: [
    { items: [item('a', 'A', '2026-05-01T00:00:00.000Z')] },
    { items: [], deleted: { a: '2026-06-01T00:00:00.000Z' } },
  ],
  editAfterDeleteSurvives: [
    { items: [item('a', 'A', '2026-07-01T00:00:00.000Z')] },
    { items: [], deleted: { a: '2026-06-01T00:00:00.000Z' } },
  ],
  expiredTombstoneDropped: [
    { items: [], deleted: { old: '2025-01-01T00:00:00.000Z', fresh: '2026-09-01T00:00:00.000Z' } },
    { items: [], deleted: { fresh: '2026-09-15T00:00:00.000Z' } },
  ],
  newerTombstoneKept: [
    { deleted: { x: '2026-08-01T00:00:00.000Z' } },
    { deleted: { x: '2026-09-01T00:00:00.000Z' } },
  ],
  missingUpdatedAtUsesCreatedAt: [
    { items: [{ _id: 'a', title: 'NoStamp', createdAt: '2026-03-01T00:00:00.000Z' }] },
    { items: [item('a', 'Stamped', '2026-02-01T00:00:00.000Z')] },
  ],
  invalidRecordsDropped: [
    { items: [{ _id: '', title: 'no id' }, { _id: 'n', title: '' }, item('ok', 'Ok', '2026-01-02T00:00:00.000Z')], collections: [{ _id: 'c' }] },
    { items: null, collections: [col('c2', 'Named', '2026-01-02T00:00:00.000Z')] },
  ],
  settingsNewerRemote: [
    { settings: settings('2026-05-01T00:00:00.000Z', { tmdbApiKey: 'local' }) },
    { settings: settings('2026-06-01T00:00:00.000Z', { tmdbApiKey: 'remote' }) },
  ],
  settingsPartialFilled: [
    { settings: { tmdbApiKey: 'k' } },
    {},
  ],
  unknownFieldsAndStringNumbers: [
    { items: [item('a', 'A', '2026-05-01T00:00:00.000Z', { year: '1999', pluginField: { nested: [1, 2] }, rating: 7.5 })] },
    { collections: [col('c', 'C', '2026-05-01T00:00:00.000Z', { itemOrder: ['a'], kind: 'manual' })] },
  ],
}

const out = {}
for (const [name, [a, b]] of Object.entries(cases)) {
  const merged = mergeDocs(a, b)
  out[name] = { a, b, merged, fingerprint: fingerprint(merged), normalizedA: normalizeDoc(a) }
}
writeFileSync(here('./merge-cases.json'), JSON.stringify({ now: new Date(NOW).toISOString(), cases: out }, null, 2) + '\n')
console.log(`wrote ${Object.keys(out).length} cases`)
