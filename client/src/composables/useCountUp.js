import { ref, onMounted, onBeforeUnmount } from 'vue'

// 0 -> 1 over `ms` once mounted; stays at 1 when the person prefers reduced motion.
export function useCountUp(ms = 800) {
  const shown = ref(1)
  let raf = 0
  onMounted(() => {
    const still = matchMedia('(prefers-reduced-motion: reduce)').matches || document.documentElement.dataset.nucMotion === 'none'
    if (still) return
    shown.value = 0
    const start = performance.now()
    const tick = (now) => {
      const p = Math.min(1, (now - start) / ms)
      shown.value = 1 - (1 - p) ** 3
      if (p < 1) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
  })
  onBeforeUnmount(() => cancelAnimationFrame(raf))
  return shown
}
