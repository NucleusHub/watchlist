<script>
// Shared by every instance: where each `memory` pill last was.
const remembered = {}
</script>

<script setup>
// The sliding-pill segmented control (NucleusSegmented). Items: { key, label, to? }; with `to` they're links.
import { ref, watch, nextTick, onMounted, onBeforeUnmount } from 'vue'
import { RouterLink } from 'vue-router'

const props = defineProps({
  items: { type: Array, required: true },
  modelValue: { type: [String, Number, Boolean, null], default: null },
  fill: { type: Boolean, default: false },
  small: { type: Boolean, default: false },
  glass: { type: Boolean, default: false },
  // Pills that live on several routes (Home's tabs) start where they last were, so they slide across.
  memory: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue'])

const track = ref(null)
const pill = ref({ x: 0, y: 0, w: 0, h: 0, ready: false })

function measure() {
  const el = track.value?.querySelector('[aria-selected="true"]')
  if (!el) { pill.value = { ...pill.value, w: 0 }; return }
  pill.value = { x: el.offsetLeft, y: el.offsetTop, w: el.offsetWidth, h: el.offsetHeight, ready: pill.value.ready || pill.value.w > 0 }
  if (props.memory) remembered[props.memory] = { ...pill.value }
}

let ro = null
onMounted(() => {
  const from = remembered[props.memory]
  if (from?.w) {
    pill.value = { ...from, ready: false }
    requestAnimationFrame(() => requestAnimationFrame(() => {
      pill.value.ready = true
      measure()
    }))
  } else measure()
  ro = new ResizeObserver(measure)
  ro.observe(track.value)
  // Fonts settle after mount and change label widths.
  document.fonts?.ready.then(measure)
})
onBeforeUnmount(() => ro?.disconnect())
watch(() => [props.modelValue, props.items.map((i) => i.label).join('|')], () => nextTick(measure))
</script>

<template>
  <div
    ref="track"
    role="tablist"
    v-glass="glass ? 'live' : false"
    :class="['wl-seg', fill ? 'flex w-full' : '']"
  >
    <span
      v-show="pill.w"
      class="wl-seg-pill"
      :style="{ width: `${pill.w}px`, height: `${pill.h}px`, top: 0, left: 0, transform: `translate(${pill.x}px, ${pill.y}px)`, transition: pill.ready ? undefined : 'none' }"
    />
    <component
      :is="item.to ? RouterLink : 'button'"
      v-for="item in items"
      :key="item.key"
      :to="item.to || undefined"
      :type="item.to ? undefined : 'button'"
      role="tab"
      :aria-selected="item.key === modelValue ? 'true' : 'false'"
      :title="item.title || undefined"
      :class="['wl-seg-item', fill ? 'flex-1 text-center !px-1.5' : '', small ? '!py-1 !px-3 !text-[13px]' : '']"
      @click="item.to || emit('update:modelValue', item.key)"
    >
      <slot name="item" :item="item">{{ item.label }}</slot>
    </component>
  </div>
</template>
