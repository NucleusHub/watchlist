const liveUrl = process.env.CAP_LIVE_URL

const config = {
  appId: 'com.nucleushome.watchlist',
  appName: 'Watchlist',
  webDir: 'dist-native',
  plugins: {
    Keyboard: { resize: 'none' },
  },
  ...(liveUrl && { server: { url: liveUrl, cleartext: true } }),
}

export { config as 'module.exports' }
