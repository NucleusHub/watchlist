import './assets/main.css'
import { createApp } from 'vue'
import App from './App.vue'
import router from './router/index.js'
import { registerFallback } from '@core/useI18n.js'
import { vGlass, vSquircle } from '@/ui/glass.js'
import fallbackLocale from '../locales/en-US.json'
registerFallback(fallbackLocale)
// Global so plugin components get the same glass and corners without importing app code.
createApp(App).use(router).directive('glass', vGlass).directive('squircle', vSquircle).mount('#app')
