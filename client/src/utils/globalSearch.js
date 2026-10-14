// What the header search finds across every list: collections by name, titles by title or notes.
export function searchAll(items, collections, query, limit = 30) {
  const q = query.trim().toLowerCase()
  if (!q) return { collections: [], items: [] }
  return {
    collections: collections.filter((c) => c.name?.toLowerCase().includes(q)),
    items: items.filter((i) => i.title.toLowerCase().includes(q) || i.notes?.toLowerCase().includes(q)).slice(0, limit),
  }
}
