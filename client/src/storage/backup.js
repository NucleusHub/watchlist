import { isNative } from '@/native.js'
import { db, replaceDoc, mergeDocs, normalizeDoc, exportDoc, now, FORMAT } from './localDb.js'

// Export the whole watchlist to a JSON file and read one back — the way to
// move data between devices without an account, and a backup with one.

export async function exportBackup() {
  const json = JSON.stringify(exportDoc(), null, 2)
  const filename = `watchlist-${now().slice(0, 10)}.json`

  if (!isNative) {
    const url = URL.createObjectURL(new Blob([json], { type: 'application/json' }))
    const a = Object.assign(document.createElement('a'), { href: url, download: filename })
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
    return
  }

  const { Filesystem, Directory, Encoding } = await import('@capacitor/filesystem')
  const { Share } = await import('@capacitor/share')
  const { uri } = await Filesystem.writeFile({ path: filename, data: json, directory: Directory.Cache, encoding: Encoding.UTF8 })
  try {
    await Share.share({ title: filename, files: [uri] })
  } catch (err) {
    // Dismissing the share sheet rejects; that's not an error worth showing.
    if (!/cancel/i.test(err?.message || '')) throw err
  }
}

export class BackupError extends Error {}

/** Parse a picked file. Returns the document and a summary to confirm against. */
export async function readBackup(file) {
  let raw
  try {
    raw = JSON.parse(await file.text())
  } catch {
    throw new BackupError('invalid')
  }
  if (raw?.format !== FORMAT || !Array.isArray(raw.items)) throw new BackupError('invalid')
  const doc = normalizeDoc(raw)
  return { doc, items: doc.items.length, collections: doc.collections.length, exportedAt: raw.exportedAt || null }
}

/**
 * Apply a backup. `merge` adds what the file has on top of what's here;
 * `replace` makes the device match the file exactly. Replacing is written as
 * deletions + fresh edits, so a sync afterwards carries it to the account
 * instead of merging the old data back in.
 */
export function applyBackup(doc, mode) {
  if (mode === 'merge') {
    replaceDoc(mergeDocs(db(), doc))
    return
  }
  const at = now()
  const keep = new Set([...doc.items, ...doc.collections].map((r) => r._id))
  const deleted = { ...doc.deleted }
  for (const r of [...db().items, ...db().collections]) if (!keep.has(r._id)) deleted[r._id] = at
  for (const id of keep) delete deleted[id]
  const touch = (r) => ({ ...r, updatedAt: at })
  replaceDoc({
    items: doc.items.map(touch),
    collections: doc.collections.map(touch),
    settings: { ...doc.settings, updatedAt: at },
    deleted,
  })
}
