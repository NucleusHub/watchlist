import { ref, computed } from 'vue'
import { haptic } from '@/native.js'

const LOCK = 8
const SHORT_COMMIT = 80
const SHORT_MAX = 140
const FULL_COMMIT_RATIO = 0.55

export function useSwipeActions({ enabled, shortDir = 1, canShort, onShort, onFull }) {
  const offset = ref(0)
  const dragging = ref(false)
  const leaving = ref(false)
  let start = null
  let axis = null
  let width = 0
  let moved = false

  const along = computed(() => offset.value * shortDir)
  const shortArmed = computed(() => along.value >= SHORT_COMMIT)
  const fullArmed = computed(() => width > 0 && -along.value >= width * FULL_COMMIT_RATIO)

  function onTouchStart(e) {
    if (!enabled.value || leaving.value || e.touches.length !== 1) return
    const t = e.touches[0]
    start = { x: t.clientX, y: t.clientY }
    axis = null
    moved = false
    width = e.currentTarget.getBoundingClientRect().width
  }

  function resist(d, max) {
    return d <= max ? d : max + (d - max) * 0.25
  }

  function onTouchMove(e) {
    if (!start) return
    const t = e.touches[0]
    const dx = t.clientX - start.x
    const dy = t.clientY - start.y
    if (!axis) {
      if (Math.abs(dx) < LOCK && Math.abs(dy) < LOCK) return
      axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y'
      if (axis === 'y') { start = null; return }
      dragging.value = true
    }
    moved = true
    const wasShort = shortArmed.value
    const wasFull = fullArmed.value
    const d = dx * shortDir
    const next = d > 0 ? (canShort?.value === false ? 0 : resist(d, SHORT_MAX)) : Math.max(d, -width)
    offset.value = next * shortDir
    if (shortArmed.value !== wasShort) haptic('Light')
    if (fullArmed.value !== wasFull) haptic('Heavy')
  }

  function onTouchEnd() {
    if (!start && !dragging.value) return
    start = null
    dragging.value = false
    if (fullArmed.value) {
      leaving.value = true
      offset.value = -shortDir * width * 1.1
      setTimeout(() => onFull(), 220)
    } else {
      if (shortArmed.value) onShort()
      offset.value = 0
    }
  }

  function reset() {
    leaving.value = false
    offset.value = 0
  }

  function onClickCapture(e) {
    if (!moved) return
    moved = false
    e.stopPropagation()
    e.preventDefault()
  }

  const handlers = {
    touchstart: onTouchStart,
    touchmove: onTouchMove,
    touchend: onTouchEnd,
    touchcancel: onTouchEnd,
  }

  return { offset, dragging, leaving, shortArmed, fullArmed, handlers, onClickCapture, reset }
}
