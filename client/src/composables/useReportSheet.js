import { ref } from 'vue'
import { isNative, haptic } from '@/native.js'
import { readJson, writeJson } from '@/storage/persist.js'

// "Report a Problem" lives above every page, so shaking the phone opens it
// wherever you are. Settings opens the same sheet, and has the switch that
// turns shaking off — a per-device choice, so it isn't synced.
const open = ref(false)
const SHAKE_KEY = 'watchlist-shake-to-report'
const shakeToReport = ref(true)

let listening = false
function listenForShake() {
  if (!isNative || listening) return
  listening = true
  readJson(SHAKE_KEY, true).then((on) => { shakeToReport.value = on !== false })
  // Sent by ShakeWindow.motionEnded (ios/App/App/SceneDelegate.swift).
  window.addEventListener('nativeshake', () => {
    if (open.value || !shakeToReport.value) return
    haptic('Medium')
    open.value = true
  })
}

function setShakeToReport(on) {
  shakeToReport.value = on
  writeJson(SHAKE_KEY, on).catch(() => {})
}

export function useReportSheet() {
  return { open, listenForShake, shakeToReport, setShakeToReport }
}
