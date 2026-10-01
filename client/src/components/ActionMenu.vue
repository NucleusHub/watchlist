<script setup>
import { ref, watch, nextTick, onUnmounted } from 'vue'
import TrashIcon from '@core/TrashIcon.vue'

// The iOS (Liquid Glass) context menu, measured off the Shell app's native one:
// the page dims, the pressed element stays bright in place, and a glass menu
// opens beside it. A menu taller than the screen scrolls inside itself.
const props = defineProps({
  show: { type: Boolean, default: false },
  // The pressed element's rect, or a zero-size one at the cursor for a right-click.
  anchor: { type: Object, default: null },
  // Where the finger was; the menu centres on it like iOS does.
  point: { type: Object, default: null },
  // The pressed element, drawn undimmed above the scrim.
  source: { type: Object, default: null },
  items: { type: Array, default: () => [] },
})
const emit = defineEmits(['close'])

const GUTTER = 16
const GAP = 20
const WIDTH = 250

const panel = ref(null)
const list = ref(null)
const ghost = ref(null)
const place = ref(null)

// Custom properties don't resolve env(), so the safe areas are read off a probe.
function insets() {
  const probe = document.createElement('div')
  probe.style.cssText = 'position:fixed;visibility:hidden;padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)'
  document.body.appendChild(probe)
  const { paddingTop, paddingBottom } = getComputedStyle(probe)
  probe.remove()
  const kb = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--kb')) || 0
  return { top: Math.max(GUTTER, parseFloat(paddingTop) + 8), bottom: Math.max(GUTTER, parseFloat(paddingBottom) + 8, kb) }
}

function mountGhost(a) {
  ghost.value?.replaceChildren()
  if (!props.source || !ghost.value) return
  const copy = props.source.cloneNode(true)
  copy.classList.remove('is-pressing')
  Object.assign(copy.style, { width: `${a.width}px`, height: `${a.height}px`, transform: 'none', margin: '0' })
  ghost.value.appendChild(copy)
}

async function position() {
  place.value = null
  await nextTick()
  const a = props.anchor
  if (!panel.value || !a) return
  const vw = window.innerWidth
  const vh = window.innerHeight
  const { top: minTop, bottom: bottomInset } = insets()
  const maxBottom = vh - bottomInset
  const width = Math.min(WIDTH, vw - GUTTER * 2)
  const natural = panel.value.scrollHeight

  const below = maxBottom - (a.bottom + GAP)
  const above = a.top - GAP - minTop
  let top
  let maxHeight
  let side
  if (below >= natural || (below >= above && below >= 160)) {
    top = a.bottom + GAP
    maxHeight = below
    side = 'top'
  } else if (above >= 160) {
    maxHeight = above
    top = a.top - GAP - Math.min(natural, maxHeight)
    side = 'bottom'
  } else {
    // Taller than the screen allows on either side: over the middle, like iOS.
    maxHeight = maxBottom - minTop
    top = minTop + Math.max(0, (maxHeight - natural) / 2)
    side = 'center'
  }
  const cx = props.point?.x ?? a.left + a.width / 2
  const left = Math.min(Math.max(cx - width / 2, GUTTER), vw - width - GUTTER)
  const ox = Math.min(Math.max(cx - left, 0), width)
  place.value = { left, top, width, maxHeight, origin: `${ox}px ${side}` }
  mountGhost(a)
}

function run(item) {
  item.action?.()
  emit('close')
}

function close() {
  emit('close')
}

function onKey(e) {
  if (e.key === 'Escape') close()
}

// iOS scrolls the page behind a fixed overlay, also with the finger that is
// still down from the long-press; only the menu's own list may move.
function onTouchMove(e) {
  if (!list.value?.contains(e.target)) e.preventDefault()
}

// If the page moves anyway, the menu and the undimmed copy would be left behind.
function onScroll(e) {
  if (e.target !== list.value) close()
}

let lockedOverflow = null
function lockPage(on) {
  const { style } = document.body
  if (on && lockedOverflow === null) {
    lockedOverflow = style.overflow
    style.overflow = 'hidden'
  } else if (!on && lockedOverflow !== null) {
    style.overflow = lockedOverflow
    lockedOverflow = null
  }
}

function bind(on) {
  const fn = on ? 'addEventListener' : 'removeEventListener'
  document[fn]('keydown', onKey)
  document[fn]('touchmove', onTouchMove, { passive: false })
  document[fn]('scroll', onScroll, { capture: true, passive: true })
  window[fn]('resize', close)
  lockPage(on)
}

watch(() => props.show, async (open) => {
  if (!open) return bind(false)
  await position()
  bind(true)
})

onUnmounted(() => bind(false))
</script>

<template>
  <Teleport to="body">
    <Transition name="am">
      <div v-if="show" class="am-scrim fixed inset-0 z-[120]" @click.self="close" @contextmenu.prevent="close">
        <div
          v-if="anchor && source"
          ref="ghost"
          class="am-ghost fixed pointer-events-none"
          :style="{ left: `${anchor.left}px`, top: `${anchor.top}px`, width: `${anchor.width}px`, height: `${anchor.height}px` }"
        />
        <div
          ref="panel"
          role="menu"
          class="am-panel absolute flex flex-col overflow-hidden"
          :class="{ 'am-measuring': !place }"
          :style="place ? { left: `${place.left}px`, top: `${place.top}px`, width: `${place.width}px`, maxHeight: `${place.maxHeight}px`, transformOrigin: place.origin } : { width: `${WIDTH}px` }"
        >
          <div ref="list" class="am-list overflow-y-auto">
            <template v-for="(item, i) in items" :key="i">
              <div v-if="item.divider" class="am-divider" />
              <component
                :is="item.href ? 'a' : 'button'"
                v-else
                role="menuitem"
                :href="item.href"
                :download="item.download"
                class="am-item"
                :class="{ 'am-danger': item.danger }"
                @click="run(item)"
              >
                <span class="am-icon">
                  <TrashIcon v-if="item.iconTrash" class="w-[21px] h-[21px]" />
                  <svg v-else-if="item.iconHeart" class="w-[21px] h-[21px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round">
                    <path d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z" />
                    <path v-if="item.iconActive" d="M4 4l16 16" stroke-linecap="round" />
                  </svg>
                  <svg v-else-if="item.icon" class="w-[21px] h-[21px]" fill="none" stroke="currentColor" stroke-width="1.7" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" :d="item.icon" />
                  </svg>
                </span>
                <span class="am-label">{{ item.label }}</span>
              </component>
            </template>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<!-- Not scoped: the menu is teleported to <body>, and the am- prefix keeps it contained. -->
<style>
.am-scrim {
  --am-tint: rgb(99 102 241);
  --am-red: #ff3b30;
  --am-text: rgba(0, 0, 0, 0.88);
  background: rgba(0, 0, 0, 0.2);
  -webkit-tap-highlight-color: transparent;
}
.dark .am-scrim {
  --am-tint: #c4b5fd;
  --am-red: #ff5559;
  --am-text: #f7f7f7;
  background: rgba(0, 0, 0, 0.5);
}

.am-panel {
  border-radius: 34px;
  background:
    linear-gradient(to right, rgba(255, 255, 255, 0.35), rgba(255, 255, 255, 0) 12%),
    rgba(246, 246, 248, 0.86);
  -webkit-backdrop-filter: blur(24px) saturate(1.8);
  backdrop-filter: blur(24px) saturate(1.8);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.9),
    0 0 0 0.5px rgba(0, 0, 0, 0.12),
    0 18px 50px -10px rgba(0, 0, 0, 0.3);
}
.dark .am-panel {
  background:
    linear-gradient(to right, rgba(255, 255, 255, 0.035), rgba(255, 255, 255, 0) 12%),
    rgba(44, 43, 51, 0.94);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.24),
    inset 0 3px 6px -3px rgba(255, 255, 255, 0.12),
    0 0 0 0.5px rgba(0, 0, 0, 0.7),
    0 22px 60px -12px rgba(0, 0, 0, 0.8);
}
.am-measuring { visibility: hidden; left: 0; top: 0; }

.am-list {
  padding: 10px 0;
  overscroll-behavior: contain;
  -webkit-overflow-scrolling: touch;
}

.am-item {
  display: flex;
  align-items: center;
  width: 100%;
  min-height: 42px;
  padding: 0 22px 0 28px;
  gap: 13px;
  text-align: left;
  color: var(--am-text);
  font: 400 17px/1.25 -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif;
  letter-spacing: -0.41px;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background-color 0.15s ease;
}
.am-item:hover, .am-item:active { background: rgba(127, 127, 127, 0.14); }

.am-icon {
  width: 24px;
  display: flex;
  justify-content: center;
  flex-shrink: 0;
  color: var(--am-tint);
}
.am-label { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.am-danger, .am-danger .am-icon { color: var(--am-red); }

.am-divider {
  height: 1px;
  margin: 10px 24px;
  background: rgba(0, 0, 0, 0.1);
}
.dark .am-divider { background: rgba(255, 255, 255, 0.08); }

.am-enter-active { transition: background-color 0.25s ease; }
.am-enter-active .am-panel { transition: opacity 0.18s ease, transform 0.42s cubic-bezier(0.2, 1.1, 0.3, 1); }
.am-leave-active { transition: background-color 0.18s ease; }
.am-leave-active .am-panel { transition: opacity 0.15s ease, transform 0.18s ease; }
.am-enter-from, .am-leave-to { background-color: transparent; }
.am-enter-from .am-panel { opacity: 0; transform: scale(0.5); }
.am-leave-to .am-panel { opacity: 0; transform: scale(0.85); }

@media (prefers-reduced-motion: reduce) {
  .am-enter-active .am-panel, .am-leave-active .am-panel { transition: opacity 0.1s ease; }
  .am-enter-from .am-panel, .am-leave-to .am-panel { transform: none; }
}
</style>
