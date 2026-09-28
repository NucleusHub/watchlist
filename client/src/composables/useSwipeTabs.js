import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useWatchlistTabs } from '@/composables/useWatchlistTabs.js'

const MIN_DISTANCE = 60
const MIN_RATIO = 1.5
const MAX_DURATION = 700

function ownsHorizontalGesture(target, root) {
  if (target.closest('input, textarea, select, [contenteditable], [data-no-swipe]')) return true
  for (let el = target; el && el !== root; el = el.parentElement) {
    if (el.scrollWidth > el.clientWidth) {
      const { overflowX } = getComputedStyle(el)
      if (overflowX === 'auto' || overflowX === 'scroll') return true
    }
  }
  return false
}

export function useSwipeTabs(rootRef) {
  const route = useRoute()
  const router = useRouter()
  const { tabs, indexOf } = useWatchlistTabs()

  const direction = ref('none')
  const removeGuard = router.beforeEach((to, from) => {
    const a = indexOf(from)
    const b = indexOf(to)
    direction.value = a < 0 || b < 0 || a === b ? 'none' : b > a ? 'left' : 'right'
  })

  let start = null

  function onStart(e) {
    start = null
    if (e.touches.length !== 1) return
    if (ownsHorizontalGesture(e.target, rootRef.value)) return
    const t = e.touches[0]
    start = { x: t.clientX, y: t.clientY, time: e.timeStamp }
  }

  function onEnd(e) {
    if (!start) return
    const t = e.changedTouches[0]
    const dx = t.clientX - start.x
    const dy = t.clientY - start.y
    const elapsed = e.timeStamp - start.time
    start = null
    if (Math.abs(dx) < MIN_DISTANCE || Math.abs(dx) < MIN_RATIO * Math.abs(dy) || elapsed > MAX_DURATION) return
    if (window.getSelection()?.toString()) return

    const i = indexOf(route)
    if (i < 0) return
    const next = tabs.value[i + (dx < 0 ? 1 : -1)]
    if (next) router.push(next.to)
  }

  const onCancel = () => { start = null }

  onMounted(() => {
    const el = rootRef.value
    el.addEventListener('touchstart', onStart, { passive: true })
    el.addEventListener('touchend', onEnd, { passive: true })
    el.addEventListener('touchcancel', onCancel, { passive: true })
  })
  onBeforeUnmount(() => {
    removeGuard()
    const el = rootRef.value
    el?.removeEventListener('touchstart', onStart)
    el?.removeEventListener('touchend', onEnd)
    el?.removeEventListener('touchcancel', onCancel)
  })

  return { direction }
}
