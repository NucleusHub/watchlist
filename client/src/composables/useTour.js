import { ref } from 'vue'

const KEY = 'watchlist-tour-seen'
export const tourOpen = ref(false)

export const openTour = () => { tourOpen.value = true }

export function closeTour() {
  tourOpen.value = false
  try { localStorage.setItem(KEY, '1') } catch {}
}

// Once per browser; storage that can't be read counts as seen so it never nags.
export function showTourOnce() {
  try {
    if (!localStorage.getItem(KEY)) tourOpen.value = true
  } catch {}
}
