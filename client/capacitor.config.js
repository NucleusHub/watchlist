const liveUrl = process.env.CAP_LIVE_URL

const config = {
  appId: 'com.nucleushome.watchlist',
  appName: 'Watchlist',
  webDir: 'dist-native',
  // The launch screen's color, so no white or black shows between it and the first page.
  backgroundColor: '#0d0d1a',
  plugins: {
    Keyboard: { resize: 'none' },
    // Held until the app has mounted (main.js), not dropped on a timer.
    SplashScreen: { launchAutoHide: false, backgroundColor: '#0d0d1a', showSpinner: false },
  },
  ...(liveUrl && { server: { url: liveUrl, cleartext: true } }),
}

export { config as 'module.exports' }
