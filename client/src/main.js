import './assets/main.css'
import { createApp } from 'vue'
import App from './App.vue'
import router from './router/index.js'
import { registerFallback, initI18n } from '@core/useI18n.js'
import { isNative, installNativeNetworking, lockNativeZoom, setupNativeKeyboard } from './native.js'
import { installNetworkActivity } from './composables/useNetworkActivity.js'
import fallbackLocale from '../locales/en-US.json'
lockNativeZoom()
installNativeNetworking()
installNetworkActivity()
setupNativeKeyboard()
registerFallback(fallbackLocale)
if (isNative) initI18n('watchlist')
createApp(App).use(router).mount('#app')
