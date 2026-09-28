<script setup>
import { ref, watch, nextTick, onBeforeUnmount } from 'vue'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import { haptic } from '@/native.js'

// An iOS page sheet: slides up to just below the status bar while the page
// behind it recedes into a card, and goes away with the close button or by
// dragging its top edge down.
const props = defineProps({
  show: { type: Boolean, default: false },
  title: { type: String, default: '' },
  // Asked before closing when set — for a sheet holding unsaved input.
  confirmDiscard: { type: String, default: '' },
})
const emit = defineEmits(['close'])
const { t } = useI18n()

const root = document.documentElement
const sheet = ref(null)
const body = ref(null)
const dragging = ref(false)
const dragY = ref(0)

// ── The page behind ──────────────────────────────────────────────────────
// Scaling #app makes it the containing block of its position: fixed children
// (the background, bars), which would then jump to the top of the document.
// Each one is measured before and after and translated back to where it was.
let receded = null

function recede() {
  const app = document.getElementById('app')
  if (!app) return
  // Reopened while still sliding away: the page is receded already.
  if (receded) return root.style.setProperty('--ps-p', '1')
  // Only the page on top shows; the ones kept underneath (NavStack) are hidden.
  const page = app.querySelector('.nav-layer.is-top') || app
  const fixed = [...page.querySelectorAll('*')].filter((el) => getComputedStyle(el).position === 'fixed')
  const before = fixed.map((el) => el.getBoundingClientRect().top)
  const scrollY = window.scrollY
  root.style.setProperty('--ps-top', `${scrollY}px`)
  root.style.setProperty('--ps-bottom', `${Math.max(0, app.scrollHeight - scrollY - window.innerHeight)}px`)
  app.style.transformOrigin = `50% ${scrollY}px`
  root.style.setProperty('--ps-p', '0')
  root.classList.add('ps-active')
  receded = fixed.map((el, i) => {
    const delta = before[i] - el.getBoundingClientRect().top
    const original = el.style.translate
    const current = getComputedStyle(el).translate
    const [x = '0px', y = '0px', z] = current === 'none' ? [] : current.split(' ')
    el.style.translate = `${x} calc(${y} + ${delta}px)${z ? ` ${z}` : ''}`
    return { el, original }
  })
  receded.app = app
  // Next frame, so the identity transform above is what the transition starts from.
  requestAnimationFrame(() => requestAnimationFrame(() => root.style.setProperty('--ps-p', '1')))
}

function restore() {
  if (!receded) return
  root.classList.remove('ps-active', 'ps-dragging')
  for (const { el, original } of receded) el.style.translate = original
  receded.app.style.transformOrigin = ''
  for (const v of ['--ps-p', '--ps-top', '--ps-bottom']) root.style.removeProperty(v)
  receded = null
}

watch(() => props.show, (open) => {
  if (open) {
    dragY.value = 0
    recede()
  } else {
    root.style.setProperty('--ps-p', '0')
  }
})
onBeforeUnmount(restore)

// ── Closing ──────────────────────────────────────────────────────────────
function requestClose() {
  if (props.confirmDiscard && !window.confirm(props.confirmDiscard)) {
    settle()
    return
  }
  emit('close')
  // The parent may keep it open (a send in flight); don't leave it hanging.
  nextTick(() => { if (props.show) settle() })
}

function settle() {
  dragY.value = 0
  root.style.setProperty('--ps-p', '1')
}

// ── Drag to dismiss, from the top edge ───────────────────────────────────
let start = null
let samples = []

function onPointerDown(e) {
  if (e.button !== 0 || e.target.closest('button')) return
  start = { y: e.clientY, id: e.pointerId }
  samples = [{ y: e.clientY, t: e.timeStamp }]
  e.currentTarget.setPointerCapture(e.pointerId)
}

function onPointerMove(e) {
  if (!start || e.pointerId !== start.id) return
  const dy = e.clientY - start.y
  if (!dragging.value && Math.abs(dy) < 4) return
  if (!dragging.value) {
    dragging.value = true
    root.classList.add('ps-dragging')
  }
  // Upwards it only gives a little, like a rubber band.
  dragY.value = dy > 0 ? dy : -Math.sqrt(-dy) * 2
  const height = sheet.value?.offsetHeight || window.innerHeight
  root.style.setProperty('--ps-p', String(Math.max(0, 1 - Math.max(0, dragY.value) / height)))
  samples.push({ y: e.clientY, t: e.timeStamp })
  if (samples.length > 5) samples.shift()
}

function onPointerUp(e) {
  if (!start || e.pointerId !== start.id) return
  start = null
  if (!dragging.value) return
  dragging.value = false
  root.classList.remove('ps-dragging')
  const first = samples[0]
  const last = samples[samples.length - 1]
  const velocity = last.t > first.t ? (last.y - first.y) / (last.t - first.t) : 0 // px per ms
  const height = sheet.value?.offsetHeight || window.innerHeight
  if (dragY.value > height * 0.28 || (velocity > 0.55 && dragY.value > 24)) {
    haptic('Light')
    requestClose()
  } else {
    settle()
  }
}

defineExpose({ body })
</script>

<template>
  <Teleport to="body">
    <Transition name="ps" :duration="{ enter: 520, leave: 380 }" @after-leave="restore">
      <div v-if="show" class="ps-root" role="dialog" aria-modal="true" :aria-label="title">
        <div class="ps-scrim" @click="requestClose" />
        <div
          ref="sheet"
          :class="['ps-sheet', { 'is-dragging': dragging }]"
          :style="{ '--ps-drag': `${dragY}px` }"
        >
          <header
            class="ps-header"
            @pointerdown="onPointerDown"
            @pointermove="onPointerMove"
            @pointerup="onPointerUp"
            @pointercancel="onPointerUp"
          >
            <span class="ps-grabber" aria-hidden="true" />
            <h2 class="ps-title">{{ title }}</h2>
            <button type="button" class="ps-close lg-glass nuc-press" :aria-label="t('watchlist.report.close')" @click="requestClose">
              <Icon name="close" class="relative w-[18px] h-[18px]" :sw="2.4" />
            </button>
          </header>
          <div ref="body" class="ps-body">
            <slot />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style>
/* The page behind the sheet — global, since it is #app itself. */
html.ps-active,
html.ps-active body { overflow: hidden; }
html.ps-active { background-color: #000; }
html.ps-active #app {
  transform:
    translateY(calc(max(env(safe-area-inset-top), 14px) * var(--ps-p)))
    scale(calc(1 - 0.075 * var(--ps-p)));
  clip-path: inset(var(--ps-top) 0 var(--ps-bottom) 0 round calc(14px * var(--ps-p)));
  transition:
    transform 0.52s cubic-bezier(0.32, 0.72, 0, 1),
    clip-path 0.52s cubic-bezier(0.32, 0.72, 0, 1);
  will-change: transform;
}
html.ps-dragging #app { transition: none; }
@media (min-width: 640px), (prefers-reduced-motion: reduce) {
  html.ps-active #app { transform: scale(1); clip-path: none; }
}
</style>

<style scoped>
.ps-root {
  position: fixed;
  inset: 0;
  z-index: 300;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}

.ps-scrim {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.32);
  opacity: var(--ps-p, 0);
  transition: opacity 0.52s cubic-bezier(0.32, 0.72, 0, 1);
}
html.ps-dragging .ps-scrim { transition: none; }
.dark .ps-scrim { background: rgba(0, 0, 0, 0.5); }

.ps-sheet {
  position: relative;
  display: flex;
  flex-direction: column;
  width: 100%;
  max-width: 640px;
  /* Just below the status bar, where iOS puts a page sheet. */
  height: calc(100% - max(env(safe-area-inset-top), 14px) - 10px);
  border-radius: 34px 34px 0 0;
  overflow: hidden;
  color: rgb(15 23 42);
  background: #f2f2f7;
  box-shadow: 0 -10px 40px rgba(0, 0, 0, 0.18);
  transform: translateY(max(0px, var(--ps-drag, 0px)));
  transition: transform 0.52s cubic-bezier(0.32, 0.72, 0, 1);
}
.ps-sheet.is-dragging { transition: none; transform: translateY(var(--ps-drag, 0px)); }
.dark .ps-sheet {
  color: #fff;
  background: #16131f;
  box-shadow: 0 -10px 40px rgba(0, 0, 0, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.08);
}
@media (min-width: 640px) {
  .ps-root { align-items: center; padding: 24px; }
  .ps-sheet { height: min(88vh, 820px); border-radius: 34px; }
}

.ps-header {
  position: relative;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 64px;
  padding: 10px 64px 0;
  touch-action: none;
  user-select: none;
  -webkit-user-select: none;
  cursor: grab;
}
.ps-grabber {
  position: absolute;
  top: 6px;
  left: 50%;
  width: 36px;
  height: 5px;
  margin-left: -18px;
  border-radius: 9999px;
  background: rgba(60, 60, 67, 0.3);
}
.dark .ps-grabber { background: rgba(235, 235, 245, 0.3); }
.ps-title {
  font-size: 17px;
  font-weight: 600;
  letter-spacing: -0.01em;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.ps-close {
  position: absolute;
  top: 16px;
  right: 16px;
  display: grid;
  place-items: center;
  width: 36px;
  height: 36px;
  border-radius: 9999px;
  cursor: pointer;
  color: rgb(60 60 67 / 0.75);
}
.dark .ps-close { color: rgb(235 235 245 / 0.8); }

.ps-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  -webkit-overflow-scrolling: touch;
  padding: 8px 16px calc(24px + max(env(safe-area-inset-bottom), var(--kb, 0px)));
}

/* Entering and leaving; the drag offset is where leaving starts from. */
.ps-enter-from .ps-sheet,
.ps-leave-to .ps-sheet { transform: translateY(100%); }
.ps-leave-active .ps-sheet { transition: transform 0.38s cubic-bezier(0.4, 0, 1, 1); }
@media (min-width: 640px) {
  .ps-enter-from .ps-sheet,
  .ps-leave-to .ps-sheet { transform: translateY(40px) scale(0.97); opacity: 0; }
  .ps-enter-active .ps-sheet,
  .ps-leave-active .ps-sheet { transition: transform 0.38s cubic-bezier(0.32, 0.72, 0, 1), opacity 0.3s ease; }
}
@media (prefers-reduced-motion: reduce) {
  .ps-enter-from .ps-sheet,
  .ps-leave-to .ps-sheet { transform: none; opacity: 0; }
  .ps-sheet { transition: opacity 0.2s ease; }
}
</style>
