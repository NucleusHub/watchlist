import { onBeforeUnmount } from 'vue'

const listeners = new Set()

export function emitItemChange(event) {
  for (const fn of listeners) fn(event)
}

export function onItemChange(fn) {
  listeners.add(fn)
  onBeforeUnmount(() => listeners.delete(fn))
}
