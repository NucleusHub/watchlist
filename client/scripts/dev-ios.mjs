import { networkInterfaces } from 'node:os'
import { execSync, spawn } from 'node:child_process'

const PORT = 5173
const ip = Object.values(networkInterfaces())
  .flat()
  .find((i) => i.family === 'IPv4' && !i.internal && !i.address.startsWith('100.'))?.address

if (!ip) {
  console.error('No LAN IPv4 address found — is Wi-Fi connected?')
  process.exit(1)
}

const url = `http://${ip}:${PORT}/`
execSync('npx cap sync ios', { stdio: 'inherit', env: { ...process.env, CAP_LIVE_URL: url } })
console.log(`\n⚡ iOS app now loads ${url} — build & run from Xcode once, then just save files.`)
console.log('  Run `npm run build:ios` to switch back to the bundled app.\n')

spawn('npx', ['vite', '--mode', 'native', '--host', '0.0.0.0', '--port', String(PORT), '--strictPort'], {
  stdio: 'inherit',
}).on('exit', (code) => process.exit(code ?? 0))
