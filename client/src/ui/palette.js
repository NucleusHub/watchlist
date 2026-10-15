// Colours shared with the iOS app (Poster.swift WatchStatus.color, WatchlistTab GenrePalette, Color.interest).
export const STATUS_COLOR = { planned: '#EB6834', watching: '#2A78D6', completed: '#1BAF7A' }
export const INTEREST = '#F97316'

const GENRE_HUES = ['#6366F1', '#8B5CF6', '#EC4899', '#F43F5E', '#F59E0B', '#10B981', '#0EA5E9', '#14B8A6']

// Same hash as iOS (UInt32 wrapping), so a genre has one colour on both.
export function genreColor(name) {
  let hash = 7
  for (const ch of String(name ?? '').toLowerCase()) hash = (Math.imul(hash, 31) + ch.codePointAt(0)) >>> 0
  return GENRE_HUES[hash % GENRE_HUES.length]
}
