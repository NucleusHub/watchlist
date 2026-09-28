import { ref, computed } from 'vue'
import { haptic } from '@/native.js'

const LOCK = 8
const LEFT_COMMIT = 80
const LEFT_MAX = 140
const RIGHT_COMMIT_RATIO = 0.55

export function useSwipeActions({ enabled, onLeft, onRight }) {
  const offset = ref(0)
  const dragging = ref(false)
  const leaving = ref(false)
  let start = null
  let axis = null
  let width = 0
  let moved = false

  const leftArmed = computed(() => offset.value <= -LEFT_COMMIT)
  const rightArmed = computed(() => width > 0 && offset.value >= width * RIGHT_COMMIT_RATIO)
  const progress = computed(() =>
    offset.value < 0
      ? Math.min(1, -offset.value / LEFT_COMMIT)
      : width ? Math.min(1, offset.value / (width * RIGHT_COMMIT_RATIO)) : 0
  )

  function onTouchStart(e) {
    if (!enabled.value || leaving.value || e.touches.length !== 1) return
    const t = e.touches[0]
    start = { x: t.clientX, y: t.clientY }
    axis = null
    moved = false
    width = e.currentTarget.getBoundingClientRect().width
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
    const wasLeft = leftArmed.value
    const wasRight = rightArmed.value
    offset.value = dx < 0 ? -resist(-dx, LEFT_MAX) : Math.min(dx, width)
    if (leftArmed.value !== wasLeft) haptic('Light')
    if (rightArmed.value !== wasRight) haptic('Heavy')
  }

  function resist(d, max) {
    return d <= max ? d : max + (d - max) * 0.25
  }

  function onTouchEnd() {
    if (!start && !dragging.value) return
    start = null
    dragging.value = false
    if (rightArmed.value) {
      leaving.value = true
      offset.value = width * 1.1
      setTimeout(() => onRight(), 220)
    } else {
      if (leftArmed.value) onLeft()
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

  return { offset, dragging, leaving, leftArmed, rightArmed, progress, handlers, onClickCapture, reset }
}
