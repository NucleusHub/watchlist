import mongoose from 'mongoose'
import WatchlistItem from './models/WatchlistItem.js'
import { applyCommand, libraryView } from './crossAppLogic.js'

// Publishes the `library` view and settles markWatched / unmarkWatched commands from the inbox.

const APP = 'watchlist'
const POLL_MS = 15_000
const PUBLISH_DELAY_MS = 2_000
const MAX_VIEW_BYTES = 250_000

const db = () => mongoose.connection.db
const views = () => db().collection('app_views')

async function publishLibrary(account) {
  const items = await WatchlistItem.find({ profileId: account }).select('title type tmdbId posterUrl status seasonProgress createdAt').lean()
  const value = libraryView(items)
  while (value.items.length && Buffer.byteLength(JSON.stringify(value)) > MAX_VIEW_BYTES) value.items.pop()
  const key = { account: String(account), clientId: APP, name: 'library' }
  const row = await views().findOne(key, { projection: { value: 1 } })
  if (row && JSON.stringify(row.value) === JSON.stringify(value)) return
  await views().updateOne(
    key,
    { $set: { value, size: Buffer.byteLength(JSON.stringify(value)), updatedAt: new Date() }, $inc: { version: 1 } },
    { upsert: true },
  )
}

const timers = new Map()
export function schedulePublish(account) {
  account = String(account)
  if (timers.has(account)) return
  timers.set(account, setTimeout(() => {
    timers.delete(account)
    publishLibrary(account).catch((err) => console.error('[crossApp] publish failed', err.message))
  }, PUBLISH_DELAY_MS))
}

// Republishes the view after any successful write to the watchlist API.
export function republishOnWrite(req, res, next) {
  if (req.method !== 'GET') {
    res.on('finish', () => {
      if (res.statusCode < 400 && req.profile?.profileId) schedulePublish(req.profile.profileId)
    })
  }
  next()
}

export async function settlePending() {
  const cmds = db().collection('app_commands')
  const rows = await cmds.find({ to: APP, settledAt: null, status: { $in: ['pending', 'delivered'] } }).sort({ createdAt: 1, _id: 1 }).limit(100).toArray()
  const touched = new Set()
  for (const row of rows) {
    const id = row.payload?.itemId
    const item = mongoose.isValidObjectId(id)
      ? await WatchlistItem.findOne({ _id: id, profileId: row.account }).lean()
      : null
    const { status, result, patch } = applyCommand(row.type, row.payload, item)
    const now = new Date()
    // Claim first so a device settling the same command wins and the item isn't patched twice.
    const claim = await cmds.updateOne({ _id: row._id, settledAt: null }, { $set: { status, result, settledAt: now, deliveredAt: row.deliveredAt ?? now } })
    if (!claim.modifiedCount) continue
    if (patch && Object.keys(patch).length) await WatchlistItem.updateOne({ _id: id }, { $set: patch })
    touched.add(row.account)
  }
  for (const account of touched) schedulePublish(account)
}

export async function startCrossApp() {
  const accounts = await WatchlistItem.distinct('profileId')
  for (const a of accounts) schedulePublish(a)
  const tick = () => settlePending().catch((err) => console.error('[crossApp] inbox failed', err.message))
  setInterval(tick, POLL_MS).unref()
  tick()
}
