import { ref, onMounted, onBeforeUnmount } from 'vue'

// True once the page has left the top. A sentinel watched by IntersectionObserver, so nothing runs while scrolling.
export function useScrolled() {
  const scrolled = ref(false)
  const sentinel = ref(null)
  let io = null
  onMounted(() => {
    io = new IntersectionObserver(([entry]) => { scrolled.value = !entry.isIntersecting })
    if (sentinel.value) io.observe(sentinel.value)
  })
  onBeforeUnmount(() => io?.disconnect())
  return { scrolled, sentinel }
}
