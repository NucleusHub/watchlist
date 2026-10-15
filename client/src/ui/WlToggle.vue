<script setup>
// iOS switch: green when on.
defineProps({
  modelValue: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  label: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue'])
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="modelValue"
    :aria-label="label || undefined"
    :disabled="disabled"
    :class="['relative inline-flex shrink-0 w-[51px] h-[31px] rounded-full p-[2px] transition-colors duration-200', modelValue ? 'bg-[#34C759]' : 'bg-black/10 dark:bg-white/15', disabled ? 'opacity-50 cursor-default' : 'cursor-pointer']"
    @click.stop="emit('update:modelValue', !modelValue)"
  >
    <span
      class="block w-[27px] h-[27px] rounded-full bg-white shadow-[0_3px_8px_rgba(0,0,0,0.15),0_1px_1px_rgba(0,0,0,0.16)] transition-transform duration-300"
      :style="{ transform: modelValue ? 'translateX(20px)' : 'none', transitionTimingFunction: 'var(--nuc-ease)' }"
    />
  </button>
</template>
