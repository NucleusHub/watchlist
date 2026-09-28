import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue'

export function useSlidingPill(activeKey) {
  const container = ref(null)
  const items = new Map()
  const setItem = (key, el) => {
    const node = el?.$el ?? el
    node ? items.set(key, node) : items.delete(key)
  }

  const pill = ref(null)
  const animate = ref(false)

  function place() {
    const el = items.get(activeKey.value)
    pill.value = el ? { x: el.offsetLeft, w: el.offsetWidth } : null
  }

  watch(activeKey, () => nextTick(place))

  const observer = new ResizeObserver(place)
  let enableFrame
  watch(container, (el, prev) => {
    if (prev) observer.unobserve(prev)
    animate.value = false
    cancelAnimationFrame(enableFrame)
    if (!el) return
    observer.observe(el)
    enableFrame = requestAnimationFrame(() => {
      enableFrame = requestAnimationFrame(() => { animate.value = true })
    })
  })
  onBeforeUnmount(() => {
    observer.disconnect()
    cancelAnimationFrame(enableFrame)
  })

  const pillStyle = computed(() =>
    pill.value ? { width: `${pill.value.w}px`, transform: `translateX(${pill.value.x}px)` } : { display: 'none' }
  )

  return { container, setItem, pillStyle, animate }
}
