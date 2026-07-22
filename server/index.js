import 'dotenv/config'
import express from 'express'
import cors from 'cors'
import cookieParser from 'cookie-parser'
import mongoose from 'mongoose'
import multer from 'multer'
import path from 'path'
import { fileURLToPath } from 'url'
import watchlistRoutes from './routes/watchlist.js'
import collectionsRoutes from './routes/collections.js'
import WatchlistItem from './models/WatchlistItem.js'
import { requireAppEnabled } from './core/server/appAccess.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const uploadsDir = path.resolve(__dirname, 'uploads')

const app = express()
const PORT = process.env.PORT || 3000

app.use(cors({ origin: true, credentials: true }))
app.use(express.json())
app.use(cookieParser())
app.use('/uploads', express.static(uploadsDir))

const storage = multer.diskStorage({
  destination: uploadsDir,
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase()
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2)}${ext}`)
  },
})

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) cb(null, true)
    else cb(new Error('Only image files are allowed'))
  },
})

app.post('/api/upload', upload.single('image'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' })
  res.json({ url: `/uploads/${req.file.filename}` })
})

app.get('/api/watchlist/health', (_, res) => res.json({ ok: true }))
// Refuse all Watchlist API access for users who have Watchlist disabled (admin override).
app.use('/api/watchlist', requireAppEnabled('watchlist'))
// Mounted before the item routes; the paths don't collide (item routes are
// /:id single-segment) but keeping collections first makes the intent explicit.
app.use('/api/watchlist/collections', collectionsRoutes)
app.use('/api/watchlist', watchlistRoutes)

async function backfillDateAdded() {
  const items = await WatchlistItem.find({ dateAdded: { $exists: false } }).sort({ createdAt: 1, _id: 1 })
  if (!items.length) return
  const now = Date.now()
  for (let i = 0; i < items.length; i++) {
    await WatchlistItem.findByIdAndUpdate(items[i]._id, {
      dateAdded: new Date(now - (items.length - 1 - i) * 60_000),
    })
  }
  console.log(`Backfilled dateAdded for ${items.length} items`)
}

mongoose
  .connect(process.env.MONGODB_URI)
  .then(async () => {
    console.log('Connected to MongoDB')
    await backfillDateAdded()
    app.listen(PORT, () => console.log(`Server running on port ${PORT}`))
  })
  .catch((err) => {
    console.error('MongoDB connection error:', err)
    process.exit(1)
  })
