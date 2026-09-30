import './assets/main.css'
import { createApp } from 'vue'
import App from './App.vue'
import router from './router/index.js'
import { registerFallback } from '@core/useI18n.js'
import { isNative, installNativeNetworking, lockNativeZoom, setupNativeKeyboard } from './native.js'
import { installNetworkActivity } from './composables/useNetworkActivity.js'
import fallbackLocale from '../locales/en-US.json'
import { applyDeviceLocale } from './nativeLocale.js'
import { loadDb } from './storage/localDb.js'
import { initNucleusId } from './auth/nucleusId.js'
import { initCloudSync } from './sync/cloudSync.js'
import { initWatchInbox } from './sync/watchInbox.js'
import { initNativePlugins } from './plugins/runtime.js'
import { showLaunchCopy, handOver } from './launchHandover.js'
lockNativeZoom()
installNativeNetworking()
installNetworkActivity()
setupNativeKeyboard()
registerFallback(fallbackLocale)
if (isNative) applyDeviceLocale()

async function boot() {
  if (isNative) showLaunchCopy()
  // On device the data lives locally; it has to be in memory before any view
  // asks for it.
  if (isNative) {
    try {
      await loadDb()
      await initNucleusId()
      await initNativePlugins()
      await initWatchInbox()
      initCloudSync().catch((err) => console.error('[watchlist] sync setup failed', err))
    } catch (err) {
      console.error('[watchlist] startup failed', err)
    }
  }
  createApp(App).use(router).mount('#app')
  if (isNative) handOver()
}
boot()
