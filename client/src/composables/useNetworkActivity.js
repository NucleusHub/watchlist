import { ref } from 'vue'

export const pendingRequests = ref(0)

const isApi = (url) => {
  try {
    return new URL(String(url), location.href).pathname.startsWith('/api/')
  } catch {
    return false
  }
}

const track = () => {
  pendingRequests.value++
  let done = false
  return () => {
    if (!done) { done = true; pendingRequests.value-- }
  }
}

export function installNetworkActivity() {
  const origFetch = window.fetch
  window.fetch = function (input, init) {
    const url = input instanceof Request ? input.url : input
    if (!isApi(url)) return origFetch.call(this, input, init)
    const end = track()
    return origFetch.call(this, input, init).finally(end)
  }

  const origOpen = XMLHttpRequest.prototype.open
  const origSend = XMLHttpRequest.prototype.send
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this.__nucApi = isApi(url)
    return origOpen.call(this, method, url, ...rest)
  }
  XMLHttpRequest.prototype.send = function (...args) {
    if (this.__nucApi) this.addEventListener('loadend', track(), { once: true })
    return origSend.apply(this, args)
  }
}
