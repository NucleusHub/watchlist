import { ref, onMounted, onBeforeUnmount } from 'vue'

const refreshing = ref(false)
const counts = ref(null)

const handlers = {}
let pending = null

export function useTabsHeader() {
  return { refreshing, counts }
}

export function useHeaderActions(map) {
  onMounted(() => {
    Object.assign(handlers, map)
    if (pending && handlers[pending.name]) {
      const { name, args } = pending
      pending = null
      handlers[name](...args)
    }
  })
  onBeforeUnmount(() => {
    for (const k in map) if (handlers[k] === map[k]) delete handlers[k]
  })
}

export function runHeaderAction(name, router, ...args) {
  if (handlers[name]) return handlers[name](...args)
  pending = { name, args }
  router.push('/')
}
