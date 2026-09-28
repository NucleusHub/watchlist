<script setup>
import { ref, shallowRef, shallowReactive, watch, nextTick, onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import NavLayer from '@/components/NavLayer.vue'
import { revision } from '@/storage/localDb.js'

// Pages as a navigation stack, the way iOS does it: a page opened from another
// slides in over it, and the one it came from stays mounted underneath —
// which is what lets a swipe from the left edge drag the top page away and
// show the previous one, scrolled where you left it.
//
// The top page scrolls the window, as pages always have. While two pages
// move, both are lifted out of the flow (position: fixed, shifted up by their
// scroll), because a transformed page in the flow would drag its own
// position: fixed parts (background, bars) along with the document.

const DURATION = 480
const EDGE = 28

const router = useRouter()
if ('scrollRestoration' in history) history.scrollRestoration = 'manual'

let nextId = 0
const entry = (route) => shallowReactive({ id: ++nextId, route, scrollY: 0 })
const depthOf = (route) => route.meta.depth ?? 0
const samePage = (a, b) => a.matched[0] === b.matched[0]

const stack = shallowRef([])
// 0: the top page is in place; 1: it has slid off to the right.
const p = ref(0)
const lifted = ref(false)
const animating = ref(false)

let timer = null
let finish = null
let token = 0

function settle() {
  clearTimeout(timer)
  timer = null
  const done = finish
  finish = null
  done?.()
}

function animateTo(target, done) {
  const mine = ++token
  finish = done
  timer = setTimeout(settle, DURATION + 40)
  // Two frames, so the starting position is on screen before it moves.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    if (mine !== token || finish !== done) return
    animating.value = true
    p.value = target
  }))
}

function lift() {
  if (lifted.value) return
  stack.value.at(-1).scrollY = window.scrollY
  animating.value = false
  lifted.value = true
}

function land() {
  ++token
  lifted.value = false
  animating.value = false
  p.value = 0
  const top = stack.value.at(-1)
  nextTick(() => window.scrollTo(0, top?.scrollY || 0))
}

// A page opened straight from a link still has somewhere to go back to.
function chain(route) {
  const list = [entry(route)]
  for (let back = route.meta.back; back; ) {
    const r = router.resolve(back)
    list.unshift(entry(r))
    back = r.meta.back
  }
  return list
}

function push(to) {
  lift()
  stack.value = [...stack.value, entry(to)]
  p.value = 1
  animateTo(0, land)
}

let swipedBack = false
function pop(to) {
  const list = stack.value
  const top = list.at(-1)
  let i = list.length - 2
  while (i >= 0 && depthOf(list[i].route) > depthOf(to)) i--
  let under = i >= 0 ? list[i] : null
  if (under && samePage(under.route, to)) under.route = to
  else under = entry(to)
  const below = i >= 0 ? list.slice(0, i) : []

  if (swipedBack) {
    // The finger already did the animation.
    swipedBack = false
    stack.value = [...below, under]
    land()
    return
  }
  lift()
  stack.value = [...below, under, top]
  p.value = 0
  animateTo(1, () => {
    stack.value = stack.value.filter((e) => e !== top)
    land()
  })
}

watch(() => router.currentRoute.value, (to) => {
  if (!to.matched.length) return
  settle()
  const list = stack.value
  if (!list.length) {
    stack.value = chain(to)
    return
  }
  const top = list.at(-1)
  if (depthOf(to) > depthOf(top.route)) return push(to)
  if (depthOf(to) < depthOf(top.route)) return pop(to)
  if (samePage(top.route, to)) {
    top.route = to
  } else {
    stack.value = [...list.slice(0, -1), entry(to)]
    nextTick(() => window.scrollTo(0, 0))
  }
}, { immediate: true })

// ── Swipe from the left edge to go back ─────────────────────────────────
let drag = null

function blocked() {
  // A sheet or a modal is open over the page.
  return document.documentElement.classList.contains('ps-active') || document.body.style.overflow === 'hidden'
}

function onTouchStart(e) {
  drag = null
  if (e.touches.length !== 1 || stack.value.length < 2 || finish || lifted.value || blocked()) return
  const t = e.touches[0]
  if (t.clientX > EDGE) return
  drag = { x: t.clientX, y: t.clientY, active: false, samples: [] }
}

function onTouchMove(e) {
  if (!drag) return
  const t = e.touches[0]
  const dx = t.clientX - drag.x
  const dy = t.clientY - drag.y
  if (!drag.active) {
    if (Math.abs(dy) > 10 && Math.abs(dy) > dx) {
      drag = null
      return
    }
    if (dx < 8) return
    drag.active = true
    lift()
  }
  e.preventDefault()
  p.value = Math.min(1, Math.max(0, dx / window.innerWidth))
  drag.samples.push({ x: t.clientX, t: e.timeStamp })
  if (drag.samples.length > 5) drag.samples.shift()
}

function onTouchEnd() {
  const d = drag
  drag = null
  if (!d?.active) return
  const first = d.samples[0]
  const last = d.samples.at(-1)
  const velocity = last && last.t > first.t ? (last.x - first.x) / (last.t - first.t) : 0 // px per ms
  const back = velocity > 0.45 || (p.value > 0.4 && velocity > -0.2)
  animating.value = true
  p.value = back ? 1 : 0
  ++token
  finish = back ? goBack : land
  timer = setTimeout(settle, DURATION * 0.75)
}

function goBack() {
  const top = stack.value.at(-1)
  swipedBack = true
  if (window.history.state?.back) router.back()
  else router.push(top.route.meta.back || '/')
  // Should the navigation not happen, don't leave the page off screen.
  setTimeout(() => {
    if (!swipedBack) return
    swipedBack = false
    animating.value = true
    p.value = 0
    finish = land
    timer = setTimeout(settle, DURATION)
  }, 800)
}

onMounted(() => {
  document.addEventListener('touchstart', onTouchStart, { passive: true })
  document.addEventListener('touchmove', onTouchMove, { passive: false })
  document.addEventListener('touchend', onTouchEnd, { passive: true })
  document.addEventListener('touchcancel', onTouchEnd, { passive: true })
})
onBeforeUnmount(() => {
  document.removeEventListener('touchstart', onTouchStart)
  document.removeEventListener('touchmove', onTouchMove)
  document.removeEventListener('touchend', onTouchEnd)
  document.removeEventListener('touchcancel', onTouchEnd)
  clearTimeout(timer)
})

function layerStyle(i) {
  const n = stack.value.length
  if (!lifted.value || i < n - 2) return null
  const x = i === n - 1 ? p.value * 100 : -30 * (1 - p.value)
  return { transform: `translate3d(${x}%, 0, 0)` }
}
const role = (i) => {
  const n = stack.value.length
  if (i === n - 1) return 'top'
  return lifted.value && i === n - 2 ? 'under' : 'hidden'
}
</script>

<template>
  <div :class="['nav-stack', { 'is-animating': animating }]">
    <div
      v-for="(e, i) in stack"
      :key="`${e.id}#${revision}`"
      :class="['nav-layer', `is-${role(i)}`, { 'is-lifted': lifted || i < stack.length - 1 }]"
      :style="layerStyle(i)"
      :inert="i !== stack.length - 1 || lifted"
      :aria-hidden="i !== stack.length - 1 ? 'true' : undefined"
    >
      <div class="nav-page" :style="lifted || i < stack.length - 1 ? { marginTop: `-${e.scrollY}px` } : null">
        <NavLayer :route="e.route" />
      </div>
      <div v-if="role(i) === 'under'" class="nav-dim" :style="{ opacity: 1 - p }" />
    </div>
  </div>
</template>

<style scoped>
.nav-layer {
  position: relative;
  isolation: isolate;
}
.nav-layer.is-lifted {
  position: fixed;
  inset: 0;
  overflow: hidden;
}
.nav-layer.is-hidden {
  visibility: hidden;
  pointer-events: none;
}
.nav-layer.is-under { pointer-events: none; }
.nav-layer.is-top.is-lifted {
  box-shadow: -8px 0 32px rgba(0, 0, 0, 0.18);
  will-change: transform;
}
.nav-layer.is-under { will-change: transform; }

.nav-dim {
  position: absolute;
  inset: 0;
  z-index: 1;
  pointer-events: none;
  background: rgba(0, 0, 0, 0.12);
}
.dark .nav-dim { background: rgba(0, 0, 0, 0.35); }

.is-animating .nav-layer,
.is-animating .nav-dim {
  transition:
    transform 0.48s cubic-bezier(0.32, 0.72, 0, 1),
    opacity 0.48s cubic-bezier(0.32, 0.72, 0, 1);
}
@media (prefers-reduced-motion: reduce) {
  .is-animating .nav-layer,
  .is-animating .nav-dim { transition-duration: 1ms; }
}
</style>
