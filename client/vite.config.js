import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig(({ mode }) => ({
  base: '/watchlist/',
  plugins: [
    vue(),
    mode !== 'production' && vueDevTools(),
    tailwindcss(),
  ].filter(Boolean),
  css: {
    transformer: 'lightningcss',
    lightningcss: {
      // Concrete versions so Lightning CSS actually vendor-prefixes (e.g. adds
      // -webkit-backdrop-filter for Safari while keeping the standard property
      // for Firefox/Chrome). Open-ended "safari >= 15" ranges resolve to an
      // empty target set, which silently disables prefixing.
      targets: {
        safari: (15 << 16) | (4 << 8),
        ios_saf: (15 << 16) | (4 << 8),
        firefox: 103 << 16,
        chrome: 90 << 16,
        edge: 90 << 16,
      },
    },
  },
  build: { cssMinify: 'lightningcss' },
  resolve: {
    preserveSymlinks: true,
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '@core': fileURLToPath(new URL('./core', import.meta.url)),
      // Shared widget package (via the ./widgets symlink → repo /widgets), so
      // this app can render Pulse widgets that opt in to showing here.
      '@widgets-core': fileURLToPath(new URL('./widgets/core', import.meta.url)),
    },
  },
  server: {
    host: '0.0.0.0',
    proxy: {
      // Pulse state (widgets opting in to show here). Must precede the '/api'
      // catch-all so it routes to Pulse, not the watchlist server. Dev-only;
      // prod nginx routes /api/pulse centrally.
      '/api/pulse': {
        target: process.env.PULSE_TARGET || 'http://localhost:3004',
        changeOrigin: true,
      },
      '/api': {
        target: process.env.API_TARGET || 'http://localhost:3000',
        changeOrigin: true,
      },
      '/uploads': {
        target: process.env.API_TARGET || 'http://localhost:3000',
        changeOrigin: true,
      },
    },
    allowedHosts: [process.env.NUCLEUS_HOST || 'nucleus.olm-altair.ts.net']
  },
}))
