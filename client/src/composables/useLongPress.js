import { ref } from 'vue'
import { haptic } from '@/native.js'

const DELAY = 300
const SLOP = 10

export function useLongPress(onLongPress) {
  const pressing = ref(false)
  let timer = null
  let start = null
  let fired = false

  function cancel() {
    clearTimeout(timer)
    timer = null
    pressing.value = false
  }

  function onTouchStart(e) {
    if (e.touches.length !== 1) return cancel()
    if (e.target.closest('button, a, input, select, textarea')) return
    const t = e.touches[0]
    start = { x: t.clientX, y: t.clientY }
    fired = false
    pressing.value = true
    timer = setTimeout(() => {
      timer = null
      pressing.value = false
      fired = true
      haptic('Medium')
      onLongPress(start)
    }, DELAY)
  }

  function onTouchMove(e) {
    if (!timer) return
    const t = e.touches[0]
    if (Math.hypot(t.clientX - start.x, t.clientY - start.y) > SLOP) cancel()
  }

  function onTouchEnd(e) {
    if (fired) {
      e.preventDefault()
      fired = false
    }
    cancel()
  }

  function onClickCapture(e) {
    if (!fired) return
    fired = false
    e.stopPropagation()
    e.preventDefault()
  }

  const handlers = {
    touchstart: onTouchStart,
    touchmove: onTouchMove,
    touchend: onTouchEnd,
    touchcancel: cancel,
  }

  return { pressing, handlers, onClickCapture }
}
