<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue'
import { pendingRequests } from '@/composables/useNetworkActivity.js'

const SHOW_DELAY = 150
const SETTLE = 120

const progress = ref(0)
const visible = ref(false)
let trickle, showTimer, settleTimer, hideTimer

function start() {
  clearTimeout(hideTimer)
  if (visible.value) return
  visible.value = true
  progress.value = 0.08
  clearInterval(trickle)
  trickle = setInterval(() => {
    progress.value += (0.9 - progress.value) * 0.12
  }, 200)
}

function finish() {
  clearInterval(trickle)
  if (!visible.value) return
  progress.value = 1
  hideTimer = setTimeout(() => {
    visible.value = false
    hideTimer = setTimeout(() => { progress.value = 0 }, 250)
  }, 250)
}

watch(pendingRequests, (n) => {
  if (n > 0) {
    clearTimeout(settleTimer)
    if (!visible.value && !showTimer) {
      showTimer = setTimeout(() => {
        showTimer = null
        if (pendingRequests.value > 0) start()
      }, SHOW_DELAY)
    }
  } else {
    clearTimeout(showTimer)
    showTimer = null
    settleTimer = setTimeout(finish, SETTLE)
  }
})

onMounted(() => {
  start()
  if (pendingRequests.value === 0) settleTimer = setTimeout(finish, 400)
})
onBeforeUnmount(() => {
  clearInterval(trickle)
  ;[showTimer, settleTimer, hideTimer].forEach(clearTimeout)
})
</script>

<template>
  <div
    class="loading-bar"
    :class="{ 'is-visible': visible }"
    role="progressbar"
    aria-label="Loading"
    :aria-hidden="!visible"
    :aria-valuenow="Math.round(progress * 100)"
    aria-valuemin="0"
    aria-valuemax="100"
  >
    <div class="loading-bar__fill" :style="{ transform: `scaleX(${progress})` }" />
  </div>
</template>

<style scoped>
.loading-bar {
  position: fixed;
  top: env(safe-area-inset-top);
  left: 0;
  right: 0;
  height: 2px;
  z-index: 100;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.25s ease;
}
.loading-bar.is-visible { opacity: 1; }

.loading-bar__fill {
  height: 100%;
  transform-origin: left;
  background: linear-gradient(90deg, #8b5cf6, #6366f1, #3b82f6);
  box-shadow: 0 0 8px rgba(139, 92, 246, 0.7);
  transition: transform 0.2s ease-out;
}

@media (prefers-reduced-motion: reduce) {
  .loading-bar__fill { transition: none; }
}
</style>
